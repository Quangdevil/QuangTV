package app.tvviewer.player

import android.app.Activity
import android.app.PictureInPictureParams
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.graphics.Color
import android.view.View
import android.view.WindowManager
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat

/** Minimal YouTube Web shell. No credential interception, media extraction or background service. */
class QuangTubeActivity : Activity() {
    // Adapted from Quangdevil/QuangTubeAuto at ccfa95915545b3fe9a82a8a8a7d8b2c4e3c27ff3.
    // Playback follows the original shell; this host owns system/keyboard insets.
    companion object {
        private var current: java.lang.ref.WeakReference<QuangTubeActivity>? = null
        fun status(): Map<String, Any> = current?.get()?.let {
            mapOf("url" to (it.web.url ?: ""), "position" to it.position,
                "playing" to it.playing, "error" to it.pageError)
        } ?: mapOf("url" to "", "position" to 0.0, "playing" to false, "error" to "closed")
        fun close() { current?.get()?.finish() }
    }
    private var pageReady = false
    private var position = 0.0
    private var playing = false
    private var pageError = ""
    private var lastRecordedVideo = ""
    private val probeHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val probe = object : Runnable {
        override fun run() {
            if (pageReady) recordPlayingVideo()
            if (pageReady && applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                web.evaluateJavascript("""JSON.stringify((()=>{const v=document.querySelector('video');const e=document.querySelector('.ytp-error-content-wrap,ytm-player-error-message-renderer');const status=window.ytInitialPlayerResponse?.playabilityStatus;const body=(document.body?.innerText||'').replace(/\s+/g,' ');const blocked=/sign in to confirm.*not a bot/i.test(body);const reason=blocked?'YouTube requires sign-in to confirm this network is not a bot':(e?.innerText||((status&&status.status!=='OK')?status.reason:'')||'');return {position:v?v.currentTime:0,playing:v?!v.paused:false,error:reason.slice(0,256)};})())""") { value ->
                    try {
                        val decoded = org.json.JSONTokener(value).nextValue() as? String ?: "{}"
                        val state = org.json.JSONObject(decoded)
                        position = state.optDouble("position", 0.0)
                        playing = state.optBoolean("playing", false)
                        pageError = state.optString("error", "")
                    } catch (_: Exception) {}
                }
            }
            probeHandler.postDelayed(this, 1000)
        }
    }
    private lateinit var root: FrameLayout
    private lateinit var web: WebView
    private lateinit var adSkip: QuangTubeAdSkipController
    private var fullscreenView: View? = null
    private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = java.lang.ref.WeakReference(this)
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS or WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION)
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        window.statusBarColor = Color.WHITE
        window.navigationBarColor = Color.BLACK
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        root = FrameLayout(this)
        // Android 15 enforces edge-to-edge. Keep all WebView content inside
        // system bars/cutouts; the keyboard only reduces the bottom viewport.
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            val keyboard = insets.getInsets(WindowInsetsCompat.Type.ime())
            view.setPadding(bars.left, bars.top, bars.right, maxOf(bars.bottom, keyboard.bottom))
            WindowInsetsCompat.CONSUMED
        }
        web = WebView(this)
        root.addView(web, FrameLayout.LayoutParams(-1, -1).apply { bottomMargin = (48 * resources.displayMetrics.density).toInt() })
        val actions = android.widget.LinearLayout(this)
        actions.addView(android.widget.Button(this).apply { text = "Đã xem"; setAllCaps(false); setOnClickListener { showHistory() } }, android.widget.LinearLayout.LayoutParams(0, -1, 1f))
        actions.addView(android.widget.Button(this).apply { text = "Tải video YouTube"; setAllCaps(false); setOnClickListener { QuangYouTube.showChoices(this@QuangTubeActivity, web.url ?: "") } }, android.widget.LinearLayout.LayoutParams(0, -1, 1f))
        root.addView(actions, FrameLayout.LayoutParams(-1, (48 * resources.displayMetrics.density).toInt(), android.view.Gravity.BOTTOM))
        setContentView(root)
        ViewCompat.requestApplyInsets(root)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
        web.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                pageReady = false
            }
            override fun onPageFinished(view: WebView?, url: String?) {
                pageReady = true
            }
            override fun shouldOverrideUrlLoading(view: WebView?, request: android.webkit.WebResourceRequest?): Boolean {
                val url = request?.url ?: return true
                val host = url.host?.lowercase() ?: return true
                return !(host == "youtube.com" || host.endsWith(".youtube.com") ||
                    host == "youtu.be" || host == "accounts.google.com")
            }
        }
        adSkip = QuangTubeAdSkipController(web)
        web.webChromeClient = object : WebChromeClient() {
            override fun onShowCustomView(view: View?, callback: CustomViewCallback?) {
                if (view == null || fullscreenView != null) { callback?.onCustomViewHidden(); return }
                fullscreenView = view
                fullscreenCallback = callback
                web.visibility = View.INVISIBLE
                root.addView(view, FrameLayout.LayoutParams(-1, -1))
            }
            override fun onHideCustomView() { exitFullscreen() }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            setPictureInPictureParams(PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .setAutoEnterEnabled(true)
                .build())
        }
        try {
            // The IPTV switch represents the app's persisted proxy state. Turn it off
            // before loading YouTube so no requests use the paid relay.
            if (QuangProxy.state(this)["enabled"] == true) QuangProxy.toggle(this, false)
        } catch (_: Exception) {
            android.widget.Toast.makeText(this, "Không thể tắt proxy. Không mở YouTube để tránh phát sinh phí.", android.widget.Toast.LENGTH_LONG).show()
            finish()
            return
        }
        QuangProxy.applyWeb(this, {
        if (savedInstanceState == null) web.loadUrl(intent.getStringExtra("url") ?: "https://m.youtube.com/") else web.restoreState(savedInstanceState)
        }, { android.widget.Toast.makeText(this, "Không áp dụng được proxy. Hãy kiểm tra Cài đặt.", android.widget.Toast.LENGTH_LONG).show(); finish() })
    }

    private fun recordPlayingVideo() {
        web.evaluateJavascript("""JSON.stringify((()=>{const v=document.querySelector('video');const id=new URL(location.href).searchParams.get('v');return v&&!v.paused&&v.currentTime>1&&id?{id:id,title:document.title.replace(/\s*-\s*YouTube\s*$/i,'').trim()}:null})())""") { value ->
            try {
                val raw = org.json.JSONTokener(value).nextValue() as? String ?: return@evaluateJavascript
                val item = org.json.JSONObject(raw)
                val id = item.optString("id")
                val title = item.optString("title")
                if (!id.matches(Regex("[A-Za-z0-9_-]{11}")) || title.isBlank() || id == lastRecordedVideo) return@evaluateJavascript
                val prefs = getSharedPreferences("quangtube_history", MODE_PRIVATE)
                val old = org.json.JSONArray(prefs.getString("videos", "[]"))
                val updated = org.json.JSONArray().put(org.json.JSONObject().put("id", id).put("title", title.take(200)))
                for (i in 0 until old.length()) {
                    val entry = old.optJSONObject(i) ?: continue
                    if (entry.optString("id") != id && updated.length() < 30) updated.put(entry)
                }
                prefs.edit().putString("videos", updated.toString()).apply()
                lastRecordedVideo = id
            } catch (_: Exception) { }
        }
    }

    private fun showHistory() {
        val items = try { org.json.JSONArray(getSharedPreferences("quangtube_history", MODE_PRIVATE).getString("videos", "[]")) } catch (_: Exception) { org.json.JSONArray() }
        if (items.length() == 0) {
            android.widget.Toast.makeText(this, "Chưa có video đã xem", android.widget.Toast.LENGTH_SHORT).show()
            return
        }
        val entries = (0 until items.length()).mapNotNull { items.optJSONObject(it) }
        android.app.AlertDialog.Builder(this).setTitle("Video đã xem")
            .setItems(entries.map { it.optString("title") }.toTypedArray()) { _, which ->
                val item = entries[which]
                android.app.AlertDialog.Builder(this).setTitle(item.optString("title"))
                    .setItems(arrayOf("Xem lại", "Tìm video tương tự")) { _, action ->
                        val url = if (action == 0) android.net.Uri.parse("https://m.youtube.com/watch").buildUpon().appendQueryParameter("v", item.optString("id")).build()
                            else android.net.Uri.parse("https://m.youtube.com/results").buildUpon().appendQueryParameter("search_query", item.optString("title")).build()
                        web.loadUrl(url.toString())
                    }.show()
            }.setNegativeButton("Đóng", null).show()
    }

    private fun exitFullscreen() {
        fullscreenView?.let { root.removeView(it) }
        fullscreenView = null
        fullscreenCallback?.onCustomViewHidden()
        fullscreenCallback = null
        web.visibility = View.VISIBLE
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature("android.software.picture_in_picture")) {
            try { enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()) }
            catch (_: Exception) { }
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (!isInPictureInPictureMode) {
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        }
    }

    override fun onBackPressed() {
        if (fullscreenView != null) exitFullscreen()
        else if (web.canGoBack()) web.goBack()
        else super.onBackPressed()
    }
    override fun onSaveInstanceState(outState: Bundle) {
        web.saveState(outState)
        super.onSaveInstanceState(outState)
    }
    override fun onResume() {
        super.onResume()
        adSkip.start()
        probeHandler.post(probe)
    }
    override fun onPause() {
        probeHandler.removeCallbacks(probe)
        adSkip.stop()
        super.onPause()
    }
    override fun onDestroy() {
        exitFullscreen()
        probeHandler.removeCallbacks(probe)
        current = null
        web.destroy()
        super.onDestroy()
    }
}

