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
            mapOf("requestedUrl" to (it.intent.getStringExtra("url") ?: "https://m.youtube.com/"), "url" to (it.web.url ?: ""), "position" to it.position,
                "playing" to it.playing, "error" to it.pageError)
        } ?: mapOf("url" to "", "position" to 0.0, "playing" to false, "error" to "closed")
        fun close() { current?.get()?.finish() }
        fun historyState(): Map<String, Any> = current?.get()?.let { activity ->
            mapOf("searches" to activity.historyItems("searches").map { it.optString("query") }, "videos" to activity.historyItems("videos").size)
        } ?: emptyMap()
        fun testAction(action: String) { current?.get()?.let { activity ->
            when (action) {
                "searchOne" -> activity.web.loadUrl("https://m.youtube.com/results?search_query=quangtv-history-one")
                "searchTwo" -> activity.web.loadUrl("https://m.youtube.com/results?search_query=quangtv-history-two")
                "showSearchHistory" -> activity.showRecords("searches")
                "deleteFirst" -> activity.firstHistoryDelete?.performClick()
                "clearAll" -> activity.historyDialog?.getButton(android.app.AlertDialog.BUTTON_POSITIVE)?.performClick()
                "confirmClear" -> activity.historyConfirm?.getButton(android.app.AlertDialog.BUTTON_POSITIVE)?.performClick()
            }
        } }

    }
    private var pageReady = false
    private var position = 0.0
    private var playing = false
    private var pageError = ""
    private var lastRecordedVideo = ""
    private var lastRecordedSearch = ""
    private var historyDialog: android.app.AlertDialog? = null
    private var historyConfirm: android.app.AlertDialog? = null
    private var firstHistoryDelete: android.widget.Button? = null
    private val probeHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val probe = object : Runnable {
        override fun run() {
            recordSearch(web.url)
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
        val legacy = intent.getStringArrayListExtra("searchHistory").orEmpty()
        val prefs = getSharedPreferences("quangtube_history", MODE_PRIVATE)
        if (!prefs.getBoolean("legacySearchImported", false) && legacy.isNotEmpty()) {
            val old = historyItems("searches").map { it.optString("query") }
            saveHistory("searches", (old + legacy).distinct().take(100).map { org.json.JSONObject().put("query", it) })
            prefs.edit().putBoolean("legacySearchImported", true).apply()
        }
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
        actions.addView(android.widget.Button(this).apply { text = "Lịch sử"; setAllCaps(false); setOnClickListener { showHistory() } }, android.widget.LinearLayout.LayoutParams(0, -1, 1f))
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
                recordSearch(url)
            }
            override fun onPageFinished(view: WebView?, url: String?) {
                pageReady = true
                recordSearch(url)
            }
            override fun doUpdateVisitedHistory(view: WebView?, url: String?, isReload: Boolean) {
                super.doUpdateVisitedHistory(view, url, isReload)
                recordSearch(url)
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
        web.evaluateJavascript("""JSON.stringify((()=>{const v=document.querySelector('video');const id=new URL(location.href).searchParams.get('v')||location.pathname.match(/^\/(?:shorts|live)\/([A-Za-z0-9_-]{11})/)?.[1];return v&&!v.paused&&v.currentTime>1&&id?{id:id,title:document.title.replace(/\s*-\s*YouTube\s*$/i,'').trim()}:null})())""") { value ->
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
                    if (entry.optString("id") != id && updated.length() < 100) updated.put(entry)
                }
                prefs.edit().putString("videos", updated.toString()).apply()
                lastRecordedVideo = id
            } catch (_: Exception) { }
        }
    }

    private fun historyItems(key: String): List<org.json.JSONObject> {
        val prefs = getSharedPreferences("quangtube_history", MODE_PRIVATE)
        val array = try { org.json.JSONArray(prefs.getString(key, "[]")) } catch (_: Exception) { org.json.JSONArray() }
        return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
    }
    private fun saveHistory(key: String, items: List<org.json.JSONObject>) {
        val array = org.json.JSONArray()
        items.take(100).forEach { array.put(it) }
        getSharedPreferences("quangtube_history", MODE_PRIVATE).edit().putString(key, array.toString()).apply()
    }
    private fun recordSearch(url: String?) {
        val uri = try { android.net.Uri.parse(url ?: "") } catch (_: Exception) { return }
        val host = uri.host?.lowercase() ?: return
        if (host != "youtube.com" && !host.endsWith(".youtube.com")) return
        val query = if (uri.path == "/results") uri.getQueryParameter("search_query")?.trim()?.take(300).orEmpty() else ""
        if (query.isEmpty()) { lastRecordedSearch = ""; return }
        if (query == lastRecordedSearch) return
        lastRecordedSearch = query
        val items = historyItems("searches").filter { it.optString("query") != query }
        saveHistory("searches", listOf(org.json.JSONObject().put("query", query)) + items)
    }
    private fun showHistory() {
        android.app.AlertDialog.Builder(this).setTitle("Lịch sử QuangTube")
            .setItems(arrayOf("Lịch sử tìm kiếm", "Video đã xem")) { _, index -> showRecords(if (index == 0) "searches" else "videos") }
            .setNegativeButton("Đóng", null).show()
    }
    private fun showRecords(key: String) {
        val items = historyItems(key)
        val isSearch = key == "searches"
        val title = if (isSearch) "Lịch sử tìm kiếm" else "Video đã xem"
        val rows = android.widget.LinearLayout(this).apply { orientation = android.widget.LinearLayout.VERTICAL }
        firstHistoryDelete = null
        val dialog = android.app.AlertDialog.Builder(this).setTitle(title)
            .setView(android.widget.ScrollView(this).apply { addView(rows) })
            .setNegativeButton("Đóng", null)
            .setPositiveButton("Xóa tất cả", null).create()
        if (items.isEmpty()) rows.addView(android.widget.TextView(this).apply { text = "Chưa có lịch sử"; setPadding(24, 24, 24, 24) })
        for (item in items) {
            val label = if (isSearch) item.optString("query") else item.optString("title")
            val row = android.widget.LinearLayout(this).apply { gravity = android.view.Gravity.CENTER_VERTICAL }
            row.addView(android.widget.TextView(this).apply {
                text = label; textSize = 15f; setPadding(24, 18, 12, 18); maxLines = 2
                setOnClickListener {
                    val target = android.net.Uri.parse(if (isSearch) "https://m.youtube.com/results" else "https://m.youtube.com/watch").buildUpon()
                        .appendQueryParameter(if (isSearch) "search_query" else "v", if (isSearch) label else item.optString("id")).build()
                    dialog.dismiss(); web.loadUrl(target.toString())
                }
            }, android.widget.LinearLayout.LayoutParams(0, -2, 1f))
            val remove = android.widget.Button(this).apply {
                text = "×"; contentDescription = "Xóa $label"
                setOnClickListener {
                    val identity = if (isSearch) "query" else "id"
                    saveHistory(key, historyItems(key).filter { it.optString(identity) != item.optString(identity) })
                    dialog.dismiss(); showRecords(key)
                }
            }
            if (firstHistoryDelete == null) firstHistoryDelete = remove
            row.addView(remove, android.widget.LinearLayout.LayoutParams((52 * resources.displayMetrics.density).toInt(), -2))
            rows.addView(row)
        }
        historyDialog = dialog
        dialog.setOnShowListener {
            dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE).isEnabled = items.isNotEmpty()
            dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                historyConfirm = android.app.AlertDialog.Builder(this).setTitle("Xóa toàn bộ $title?")
                    .setNegativeButton("Hủy", null).setPositiveButton("Xóa tất cả") { _, _ ->
                        saveHistory(key, emptyList())
                        if (isSearch) getSharedPreferences("quangtube_history", MODE_PRIVATE).edit().putBoolean("legacySearchImported", true).apply()
                        dialog.dismiss()
                    }.show()
            }
        }
        dialog.show()
        dialog.window?.setLayout(-1, minOf(resources.displayMetrics.heightPixels * 3 / 4, resources.displayMetrics.heightPixels - 120))
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
        if (current?.get() === this) current = null
        web.destroy()
        super.onDestroy()
    }
}

