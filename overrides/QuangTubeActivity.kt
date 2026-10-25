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
import android.webkit.CookieManager
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.ProgressBar
import android.view.Gravity
import android.os.Handler
import android.os.Looper
import java.lang.ref.WeakReference
import org.json.JSONObject
import android.widget.FrameLayout

/** Minimal YouTube Web shell. No credential interception, media extraction or background service. */
class QuangTubeActivity : Activity() {
    companion object {
        private var current: WeakReference<QuangTubeActivity>? = null
        fun status(): Map<String, Any> = current?.get()?.let {
            mapOf("url" to (it.web.url ?: ""), "progress" to it.pageProgress,
                "position" to it.position, "playing" to it.playing, "error" to it.pageError)
        } ?: mapOf("url" to "", "progress" to 0, "position" to 0.0, "playing" to false, "error" to "closed")
        fun close() { current?.get()?.finish() }
    }
    private var pageReady = false
    private var pageProgress = 0
    private var pageError = ""
    private var position = 0.0
    private var playing = false
    private val probeHandler = Handler(Looper.getMainLooper())
    private val probe = object : Runnable {
        override fun run() {
            if (pageReady && applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                web.evaluateJavascript("""JSON.stringify((()=>{const v=document.querySelector('video');return {position:v?v.currentTime:0,playing:v?!v.paused:false};})())""") { value ->
                    try {
                        val decoded = org.json.JSONTokener(value).nextValue() as? String ?: "{}"
                        val state = JSONObject(decoded)
                        position = state.optDouble("position", 0.0)
                        playing = state.optBoolean("playing", false)
                    } catch (_: Exception) {}
                }
            }
            probeHandler.postDelayed(this, 1000)
        }
    }
    private lateinit var loadingBar: ProgressBar
    private lateinit var root: FrameLayout
    private lateinit var web: WebView
    private lateinit var adSkip: QuangTubeAdSkipController
    private var fullscreenView: View? = null
    private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS or WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION)
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        window.statusBarColor = Color.WHITE
        window.navigationBarColor = Color.BLACK
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        if (Build.VERSION.SDK_INT >= 30) window.setDecorFitsSystemWindows(true)
        root = FrameLayout(this)
        // One owner for insets: Android decor fits content below system bars.
        // Never add IME/status-bar padding to the WebView container.
        root.fitsSystemWindows = false
        current = WeakReference(this)
        web = WebView(this)
        val toolbarHeight = (48 * resources.displayMetrics.density).toInt()
        root.addView(web, FrameLayout.LayoutParams(-1, -1).apply { topMargin = toolbarHeight })
        val toolbar = LinearLayout(this).apply { setBackgroundColor(Color.WHITE); gravity = Gravity.CENTER_VERTICAL }
        toolbar.addView(Button(this).apply { text = "‹"; setOnClickListener { onBackPressed() } }, LinearLayout.LayoutParams(toolbarHeight, -1))
        toolbar.addView(TextView(this).apply { text = "QuangTube"; textSize = 18f; gravity = Gravity.CENTER_VERTICAL; setTextColor(Color.BLACK) }, LinearLayout.LayoutParams(0, -1, 1f))
        toolbar.addView(Button(this).apply { text = "↻"; setOnClickListener { web.reload() } }, LinearLayout.LayoutParams(toolbarHeight, -1))
        root.addView(toolbar, FrameLayout.LayoutParams(-1, toolbarHeight))
        loadingBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal)
        root.addView(loadingBar, FrameLayout.LayoutParams(-1, (3 * resources.displayMetrics.density).toInt()).apply { topMargin = toolbarHeight })
        setContentView(root)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)
        web.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                pageReady = false
                pageError = ""
                adSkip.stop()
                android.util.Log.i("QuangTube", "page started: $url")
            }
            override fun onPageFinished(view: WebView?, url: String?) {
                pageReady = true
                adSkip.start()
                android.util.Log.i("QuangTube", "page finished: $url")
                if (url?.contains("/watch") == true) {
                    web.evaluateJavascript("""(()=>{const b=document.querySelector('.ytp-large-play-button');if(b)b.click();const v=document.querySelector('video');if(v)v.play().catch(()=>{});})()""", null)
                }
            }
            override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                if (request?.isForMainFrame == true) pageError = error?.description?.toString() ?: "Không tải được YouTube"
            }
            override fun shouldOverrideUrlLoading(view: WebView?, request: android.webkit.WebResourceRequest?): Boolean {
                val url = request?.url ?: return true
                val host = url.host?.lowercase() ?: return true
                return !(host == "youtube.com" || host.endsWith(".youtube.com") ||
                    host == "youtu.be" || host == "accounts.google.com" || host == "consent.google.com" || host == "youtube-nocookie.com" || host.endsWith(".youtube-nocookie.com"))
            }
        }
        adSkip = QuangTubeAdSkipController(web)
        web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                pageProgress = newProgress
                loadingBar.apply {
                    progress = newProgress
                    visibility = if (newProgress == 100) View.GONE else View.VISIBLE
                }
            }
            override fun onShowCustomView(view: View?, callback: CustomViewCallback?) {
                if (view == null || fullscreenView != null) { callback?.onCustomViewHidden(); return }
                window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
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
        if (savedInstanceState == null) web.loadUrl(intent.getStringExtra("url") ?: "https://m.youtube.com/") else web.restoreState(savedInstanceState)
    }

    private fun exitFullscreen() {
        fullscreenView?.let { root.removeView(it) }
        fullscreenView = null
        fullscreenCallback?.onCustomViewHidden()
        fullscreenCallback = null
        web.visibility = View.VISIBLE
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
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
        if (pageReady) adSkip.start()
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
