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
    private val probeHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val probe = object : Runnable {
        override fun run() {
            if (pageReady && applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                web.evaluateJavascript("""JSON.stringify((()=>{const v=document.querySelector('video');const e=document.querySelector('.ytp-error-content-wrap,ytm-player-error-message-renderer');return {position:v?v.currentTime:0,playing:v?!v.paused:false,error:e?(e.innerText||''):''};})())""") { value ->
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
        root.addView(android.widget.Button(this).apply { text = "Tải video YouTube"; setAllCaps(false); setOnClickListener { QuangYouTube.showChoices(this@QuangTubeActivity, web.url ?: "") } }, FrameLayout.LayoutParams(-1, (48 * resources.displayMetrics.density).toInt(), android.view.Gravity.BOTTOM))
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
        QuangProxy.applyWeb(this, {
        if (savedInstanceState == null) web.loadUrl(intent.getStringExtra("url") ?: "https://m.youtube.com/") else web.restoreState(savedInstanceState)
        }, { android.widget.Toast.makeText(this, "Không áp dụng được proxy. Hãy kiểm tra Cài đặt.", android.widget.Toast.LENGTH_LONG).show(); finish() })
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
        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) probeHandler.post(probe)
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

