package app.tvviewer.player

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.*
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import androidx.webkit.ProxyController
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import java.io.ByteArrayInputStream
import java.lang.ref.WeakReference
import java.util.Locale
import org.json.JSONArray

/** System WebView, direct media discovery and Android-managed downloads. Native proxy transport and public video extraction. */
class QuangBrowserActivity : Activity() {
    data class Media(val url: String, val kind: String)
    companion object {
        const val MAY_HOME = "https://may-viet-web-proxy.daquang.workers.dev/"
        private var current: WeakReference<QuangBrowserActivity>? = null
        private var lastRotation: Map<String, Any> = emptyMap()
        fun inspect(): Map<String, Any> = current?.get()?.let {
            val point = IntArray(2); it.root.getLocationOnScreen(point)
            val insets = ViewCompat.getRootWindowInsets(it.root)
            mapOf("mayMode" to it.mayMode, "pageUrl" to (it.web.url ?: ""), "rotationPassed" to it.rotationPassed, "blockedAds" to it.blockedAds.get(), "selectedUrl" to (it.activeUrls.firstOrNull() ?: ""), "proxyOn" to (QuangProxy.state(it)["enabled"] == true), "tabs" to it.tabs.size, "selected" to it.activeUrls.size, "fullscreen" to it.orientationFullscreen, "previewPlaying" to (it.previewPlayer?.isPlaying == true), "count" to it.media.size, "top" to point[1] + it.root.paddingTop,
                "statusBar" to (insets?.getInsets(WindowInsetsCompat.Type.statusBars())?.top ?: 0),
                "downloaded" to it.downloadedBytes(), "height" to it.web.height, "ime" to (insets?.isVisible(WindowInsetsCompat.Type.ime()) ?: false))
        } ?: lastRotation
        fun mayTest(command: String, value: Double, done: (Map<String, Any>) -> Unit) {
            current?.get()?.let { QuangBrowserTestHooks.run(it.web, it.window.decorView, command, value, done) } ?: done(mapOf("error" to "browser closed"))
        }
        fun testAction(action: String) {
            current?.get()?.let {
                android.util.Log.i("QuangBrowserTest", "action=$action begin")
                when (action) {
                    "mayExample" -> it.openMayTarget("https://example.org/")
                    "mayDemo" -> { it.mayMode = true; it.applyBrowserTransport({it.web.loadUrl(MAY_HOME + "demo")}, {}) }
                    "focus" -> { it.address.requestFocus(); (it.getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).showSoftInput(it.address, InputMethodManager.SHOW_IMPLICIT) }
                    "select" -> it.media.values.firstOrNull()?.let { candidate -> it.choose(candidate) }
                    "download" -> it.found.performClick()
                    "confirmDownload" -> it.downloadButton?.performClick()
                    "toggleProxy" -> it.proxyButton.performClick()
                    "showTabs" -> it.tabsButton.performClick()
                    "newTab" -> it.tabsDialog?.getButton(AlertDialog.BUTTON_POSITIVE)?.performClick()
                    "firstTab" -> it.switchTab(it.tabs.first())
                    "openDownloads" -> it.downloadsButton.performClick()
                    "openCompleted" -> it.openCompletedButton?.performClick()
                    "closePreview" -> it.previewDialog?.dismiss()
                    "playPage" -> it.web.evaluateJavascript("(()=>{const v=document.querySelector('video');v.muted=true;v.play().catch(console.error)})()", null)
                    "previewAndRotate" -> {
                        it.previewPassed = false
                        it.downloadsButton.performClick()
                        it.handler.postDelayed({
                            it.openCompletedButton?.performClick()
                            var checks = 0
                            val verify = object : Runnable {
                                override fun run() {
                                    val video = it.previewPlayer
                                    if (video != null && video.isPlaying && video.currentPosition >= 1000) {
                                        it.previewPassed = true
                                        android.util.Log.i("QuangBrowserTest", "previewFramesAdvanced=true")
                                        it.previewDialog?.dismiss()
                                        it.handler.postDelayed({ testAction("rotatePlayback") }, 1000)
                                    } else if (++checks < 80) it.handler.postDelayed(this, 250)
                                    else {
                                        lastRotation = mapOf("previewPassed" to false, "rotationPassed" to false, "fullscreen" to false)
                                        it.previewDialog?.dismiss()
                                        it.media.values.firstOrNull()?.let { candidate -> it.choose(candidate) }
                                    }
                                }
                            }
                            it.handler.postDelayed(verify, 250)
                        }, 400)
                    }
                    "rotatePlayback" -> {
                        // Drive both OS rotations natively: the hidden Flutter test surface
                        // cannot deliver a frame while the native activity is landscape.
                        it.rotationPassed = false
                        it.address.clearFocus(); it.root.requestFocus()
                        (it.getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(it.root.windowToken, 0)
                        it.web.evaluateJavascript("(()=>{const v=document.querySelector('video');v.muted=true;v.play().catch(console.error)})()", null)
                        val returnToPlayer = {
                            lastRotation = mapOf("previewPassed" to it.previewPassed, "rotationPassed" to it.rotationPassed, "fullscreen" to it.orientationFullscreen)
                            for (id in it.settings.getStringSet("downloads", emptySet())!!) it.downloads.remove(id.toLong())
                            it.settings.edit().remove("downloads").apply()
                            it.media.values.firstOrNull()?.let { candidate -> it.choose(candidate) }
                            Unit
                        }
                        var checks = 0
                        val ready = object : Runnable {
                            override fun run() {
                                it.web.evaluateJavascript("(()=>{const v=document.querySelector('video');return !!v&&!v.paused&&v.readyState>=3&&v.currentTime>=1})()") { playing ->
                                    if (playing == "true") {
                                        android.util.Log.i("QuangBrowserTest", "videoFramesAdvanced=true")
                                        it.requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                                        it.handler.postDelayed({
                                            it.rotationPassed = it.orientationFullscreen && it.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
                                            android.util.Log.i("QuangBrowserTest", "landscapeFullscreen=${it.rotationPassed}")
                                            it.requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                                        }, 6500)
                                        it.handler.postDelayed({ returnToPlayer() }, 8500)
                                    } else if (++checks < 60) it.handler.postDelayed(this, 250)
                                    else returnToPlayer()
                                }
                            }
                        }
                        it.handler.postDelayed(ready, 250)
                    }
                    "landscape" -> it.requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                    "portrait" -> it.requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    "clearDownloads" -> {
                        for (id in it.settings.getStringSet("downloads", emptySet())!!) it.downloads.remove(id.toLong())
                        it.settings.edit().remove("downloads").apply()
                    }
                    "close" -> it.finish()
                }
                android.util.Log.i("QuangBrowserTest", "action=$action end")
            }
        }
    }
    private lateinit var root: LinearLayout
    private var mayMode = false
    private var pendingMayTarget: String? = null
    private fun isMayUrl(url: String?) = try { Uri.parse(url ?: "").host == Uri.parse(MAY_HOME).host } catch (_: Exception) { false }
    private lateinit var web: WebView
    private lateinit var address: EditText
    private lateinit var found: Button
    private var downloadButton: Button? = null
    private lateinit var progress: ProgressBar
    private val tabs = ArrayList<WebView>()
    private val tabMedia = LinkedHashMap<WebView, LinkedHashMap<String, Media>>()
    private val media: LinkedHashMap<String, Media> get() = tabMedia.getOrPut(web) { LinkedHashMap() }
    private lateinit var tabsButton: Button
    private lateinit var downloadsButton: Button
    private var tabsDialog: AlertDialog? = null
    private var previewDialog: AlertDialog? = null
    private var previewPlayer: VideoView? = null
    private var openCompletedButton: Button? = null
    private val handler = Handler(Looper.getMainLooper())
    private val downloads by lazy { getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager }
    private val settings by lazy { getSharedPreferences("quangtv_browser", MODE_PRIVATE) }
    @Volatile private var blockAds = true
    private var pendingDownload: Media? = null
    private var downloadsDialog: AlertDialog? = null
    private val blockedAds = java.util.concurrent.atomic.AtomicInteger()
    private var orientationFullscreen = false
    private var rotationPassed = false
    private var previewPassed = false
    private var activeUrls = emptySet<String>()
    private lateinit var addressBar: LinearLayout
    private lateinit var toolbar: LinearLayout
    private lateinit var proxyButton: Button
    private var fullscreen: View? = null
    private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null
    private val adHosts = setOf("doubleclick.net", "googlesyndication.com", "googleadservices.com", "adnxs.com", "adsrvr.org", "advertising.com", "adform.net", "criteo.com", "criteo.net", "taboola.com", "outbrain.com", "mgid.com", "popads.net", "popcash.net", "propellerads.com", "adsterra.com", "onclicka.com", "highperformanceformat.com", "highperformancegate.com", "topcreativeformat.com", "effectivegatecpm.com", "effectivecpmrate.com", "trafficjunky.net", "exoclick.com", "juicyads.com", "tsyndicate.com", "hilltopads.net", "ad-maven.com", "monetag.com", "bidvertiser.com", "pubmatic.com", "rubiconproject.com", "casalemedia.com", "openx.net", "smartadserver.com", "bidswitch.net", "lijit.com")
    private fun adHost(host: String?): Boolean {
        var value = host?.lowercase(Locale.ROOT) ?: return false
        while (value.isNotEmpty()) { if (value in adHosts) return true; val dot = value.indexOf('.'); if (dot < 0) break; value = value.substring(dot + 1) }
        return false
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun httpUrl(value: String): Boolean = Uri.parse(value).let { it.scheme in listOf("http", "https") && !it.host.isNullOrEmpty() }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        blockAds = settings.getBoolean("blockAds", true)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or WindowManager.LayoutParams.SOFT_INPUT_STATE_HIDDEN)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.WHITE); isFocusableInTouchMode = true }
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
            if (orientationFullscreen || fullscreen != null) view.setPadding(bars.left, 0, bars.right, 0)
            else view.setPadding(bars.left, bars.top, bars.right, maxOf(bars.bottom, ime.bottom))
            WindowInsetsCompat.CONSUMED
        }
        val bar = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(6), 0, dp(6), 0) }
        address = EditText(this).apply {
            textSize = 14f; setSingleLine(true); hint = "Địa chỉ web hoặc từ khóa"
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_URI
            imeOptions = EditorInfo.IME_ACTION_GO or EditorInfo.IME_FLAG_NO_EXTRACT_UI
            setOnEditorActionListener { _, action, _ ->
                if (action == EditorInfo.IME_ACTION_GO) { navigate(text.toString()); true } else false
            }
        }
        bar.addView(address, LinearLayout.LayoutParams(0, dp(52), 1f))
        bar.addView(button("↻", "Tải lại") { web.reload() }, LinearLayout.LayoutParams(dp(44), dp(48)))
        tabsButton = button("1", "Các tab") { showTabs() }
        bar.addView(tabsButton, LinearLayout.LayoutParams(dp(44), dp(48)))
        address.background = android.graphics.drawable.GradientDrawable().apply { setColor(Color.rgb(241, 243, 244)); cornerRadius = dp(24).toFloat() }
        address.setPadding(dp(14), 0, dp(8), 0)
        addressBar = bar
        root.addView(bar)
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal)
        root.addView(progress, LinearLayout.LayoutParams(-1, dp(3)))
        web = WebView(this)
        tabs.add(web); tabMedia[web] = LinkedHashMap()
        root.addView(web, LinearLayout.LayoutParams(-1, 0, 1f))
        val tools = LinearLayout(this).apply { gravity = Gravity.CENTER; setBackgroundColor(Color.WHITE) }
        tools.addView(button("‹", "Quay lại") { if (web.canGoBack()) web.goBack() else finish() }, LinearLayout.LayoutParams(dp(48), dp(48)))
        tools.addView(button("›", "Tiến tới") { if (web.canGoForward()) web.goForward() }, LinearLayout.LayoutParams(dp(48), dp(48)))
        found = button("Tải video", "Chọn video đang phát để tải hoặc xem") { showMedia() }
        tools.addView(found, LinearLayout.LayoutParams(0, dp(48), 1f))
        downloadsButton = button("Đã tải", "Quản lý tải xuống") { showDownloads() }
        tools.addView(downloadsButton, LinearLayout.LayoutParams(dp(52), dp(48)))
        tools.addView(button("⋮", "Tùy chọn") { showOptions() }, LinearLayout.LayoutParams(dp(48), dp(48)))
        proxyButton = button("P", "Bật/tắt proxy") { toggleProxy() }
        tools.addView(proxyButton, LinearLayout.LayoutParams(dp(40), dp(48)))
        toolbar = tools
        root.addView(tools)
        updateProxyButton()
        setContentView(root)
        WindowCompat.getInsetsController(window, root).apply { isAppearanceLightStatusBars = true; isAppearanceLightNavigationBars = true }
        root.requestFocus()
        ViewCompat.requestApplyInsets(root)
        configureWeb(web)
        current = WeakReference(this)
        val initial = intent.getStringExtra("url") ?: ""
        mayMode = isMayUrl(initial)
        applyBrowserTransport({
        if (state != null) web.restoreState(state)
        else if (httpUrl(initial)) web.loadUrl(initial)
        else web.loadData("<meta name='viewport' content='width=device-width'><h2>QuangTV · Trình duyệt</h2><p><a href='https://m.facebook.com/'>Facebook</a> · <a href='https://web.telegram.org/k/'>Telegram Web</a> · <a href='https://m.youtube.com/'>YouTube</a></p><p>Nhập địa chỉ hoặc từ khóa ở trên. Nhấn Tải video để chọn nguồn rồi nhấn Tải xuống. Đã tải mở tiến trình và tệp đã tải.</p><p>Hỗ trợ nguồn MP4/WebM và HLS trực tiếp. Không giải mã DRM, không gỡ watermark. Chỉ tải nội dung bạn có quyền lưu.</p>", "text/html", "UTF-8")
        }, { Toast.makeText(this, "Không áp dụng được proxy. Hãy kiểm tra Cài đặt hoặc cập nhật Android System WebView.", Toast.LENGTH_LONG).show(); finish() })
    }
    private fun applyBrowserTransport(done: () -> Unit, failed: () -> Unit) {
        if (!mayMode) { QuangProxy.applyWeb(this, done, failed); return }
        if (WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            val executor = java.util.concurrent.Executor { handler.post(it) }
            ProxyController.getInstance().clearProxyOverride(executor) { updateProxyButton(); done() }
        } else { updateProxyButton(); done() }
    }
    private fun openMayTarget(target: String? = null) {
        mayMode = true
        pendingMayTarget = target?.takeIf { httpUrl(it) && !isMayUrl(it) }
        applyBrowserTransport({ web.loadUrl(MAY_HOME) }, { Toast.makeText(this, "Không mở được Mây", Toast.LENGTH_LONG).show() })
    }
    private fun openPendingMayPage(view: WebView) {
        if (!mayMode || view !== web || !isMayUrl(view.url)) return
        val target = pendingMayTarget ?: return
        pendingMayTarget = null
        val quoted = org.json.JSONObject.quote(target)
        view.evaluateJavascript("(()=>{const input=document.querySelector('#target'),form=document.querySelector('#visit');if(!input||!form)return false;input.value=$quoted;form.requestSubmit();return true})()", null)
    }
    private fun configureWeb(view: WebView) {
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            val script = assets.open("quang_may_gestures.js").bufferedReader().use { it.readText() }
            WebViewCompat.addDocumentStartJavaScript(view, script, setOf("*"))
        }
        view.settings.apply {
            javaScriptEnabled = true; domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = true
            userAgentString = userAgentString.replace("; wv", "").replace(" Version/4.0", "")
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(true)
        }
        view.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                tabMedia[view]?.clear()
                if (view === web) { found.text = "Tải video"; activeUrls = emptySet(); address.setText(url?.takeIf { httpUrl(it) } ?: "") }
            }
            override fun onPageCommitVisible(view: WebView, url: String?) { installMediaMute(view); applyAdStyle(view); installAdGuard(view) }
            override fun onPageFinished(view: WebView, url: String?) { applyAdStyle(view); installAdGuard(view); installMediaMute(view); if (view === web) scanMedia(); openPendingMayPage(view) }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val uri = request.url
                if (mayMode && request.isForMainFrame && httpUrl(uri.toString()) && !isMayUrl(uri.toString())) { openMayTarget(uri.toString()); return true }
                if (uri.scheme == "intent") {
                    val fallback = try { Intent.parseUri(uri.toString(), Intent.URI_INTENT_SCHEME).getStringExtra("browser_fallback_url") } catch (_: Exception) { null }
                    if (fallback != null && httpUrl(fallback) && !(blockAds && adHost(Uri.parse(fallback).host))) view.loadUrl(fallback)
                    return true
                }
                if (uri.scheme == "tg") { view.loadUrl("https://web.telegram.org/k/"); return true }
                if (uri.scheme == "fb") { view.loadUrl("https://m.facebook.com/"); return true }
                return !httpUrl(uri.toString()) || (blockAds && adHost(uri.host))
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: android.webkit.WebResourceError) {
                if (view === web && request.isForMainFrame) Toast.makeText(this@QuangBrowserActivity, "Không mở được trang: ${error.description}. Kiểm tra mạng/proxy và cập nhật Android System WebView.", Toast.LENGTH_LONG).show()
            }
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                val uri = request.url
                if (blockAds && !request.isForMainFrame && adHost(uri.host)) {
                    blockedAds.incrementAndGet()
                    return WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(ByteArray(0)))
                }
                if (request.method == "GET") detect(uri.toString(), request.requestHeaders.entries.any { it.key.equals("Sec-Fetch-Dest", true) && it.value == "video" }, view)
                return null
            }
        }
        view.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(view: WebView?, isDialog: Boolean, isUserGesture: Boolean, resultMsg: android.os.Message?): Boolean {
                if (blockAds || !isUserGesture || resultMsg == null || tabs.size >= 8) { if (blockAds) blockedAds.incrementAndGet(); return false }
                newTab("about:blank")
                val transport = resultMsg.obj as? WebView.WebViewTransport ?: return false
                transport.webView = web; resultMsg.sendToTarget(); return true
            }
            override fun onProgressChanged(view: WebView, value: Int) {
                if (value == 25 || value == 50 || value == 75) { installMediaMute(view); installAdGuard(view) }
                if (view !== web) return
                progress.progress = value
                progress.visibility = if (value == 100) View.GONE else View.VISIBLE
            }
            override fun onShowCustomView(view: View?, callback: CustomViewCallback?) {
                if (view == null || fullscreen != null) { callback?.onCustomViewHidden(); return }
                fullscreen = view; fullscreenCallback = callback
                WindowCompat.getInsetsController(window, root).hide(WindowInsetsCompat.Type.systemBars())
                (window.decorView as android.view.ViewGroup).addView(view, android.view.ViewGroup.LayoutParams(-1, -1))
            }
            override fun onHideCustomView() { exitFullscreen() }
        }
        view.setDownloadListener { url, _, _, mime, _ ->
            if (mime?.startsWith("video/") == true || mime == "application/octet-stream") {
                detect(url, true, view); if (view === web) showMedia()
            } else Toast.makeText(this, "Chỉ hỗ trợ tải tệp video trực tiếp", Toast.LENGTH_SHORT).show()
        }
    }
    private fun newTab(url: String = "about:blank") {
        if (tabs.size >= 8) { Toast.makeText(this, "Đóng bớt tab trước khi mở thêm (tối đa 8)", Toast.LENGTH_SHORT).show(); return }
        val view = WebView(this); tabs.add(view); tabMedia[view] = LinkedHashMap(); configureWeb(view)
        switchTab(view); view.loadUrl(url)
    }
    private fun switchTab(view: WebView) {
        if (view === web) return
        exitFullscreen(); if (orientationFullscreen) exitOrientationFullscreen()
        web.evaluateJavascript("document.querySelectorAll('video,audio').forEach(v=>v.pause())", null)
        web.onPause(); root.removeView(web); web = view
        root.addView(web, 2, LinearLayout.LayoutParams(-1, 0, 1f)); web.onResume()
        activeUrls = emptySet(); address.setText(web.url ?: ""); tabsButton.text = tabs.size.toString(); scanMedia()
    }
    private fun closeTab(view: WebView) {
        if (tabs.size == 1) { view.loadUrl("about:blank"); view.clearHistory(); tabMedia[view]?.clear(); return }
        if (view === web) switchTab(tabs.first { it !== view })
        tabs.remove(view); tabMedia.remove(view); view.destroy(); tabsButton.text = tabs.size.toString()
    }
    private fun showTabs() {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val dialog = AlertDialog.Builder(this).setTitle("Tab (${tabs.size}/8)").setView(ScrollView(this).apply { addView(box) }).setPositiveButton("+ Tab mới") { _, _ -> newTab() }.setNegativeButton("Đóng", null).create()
        for (view in tabs.toList()) {
            val row = LinearLayout(this)
            row.addView(button((if (view === web) "● " else "") + (view.title ?: view.url ?: "Tab mới").take(60), "Chuyển tab") { dialog.dismiss(); switchTab(view) }, LinearLayout.LayoutParams(0, dp(56), 1f))
            row.addView(button("×", "Đóng tab") { dialog.dismiss(); closeTab(view); showTabs() }, LinearLayout.LayoutParams(dp(48), dp(56)))
            box.addView(row)
        }
        tabsDialog = dialog
        dialog.setOnDismissListener { tabsDialog = null }
        dialog.show()
    }
    private fun button(label: String, description: String, action: () -> Unit) = Button(this).apply {
        text = label; textSize = 12f; contentDescription = description; setAllCaps(false); elevation = 0f; backgroundTintList = android.content.res.ColorStateList.valueOf(Color.TRANSPARENT)
        setPadding(0, 0, 0, 0); minWidth = 0; setOnClickListener { action() }
    }
    private fun navigate(value: String) {
        val text = value.trim()
        if (text.isEmpty()) return
        val url = when {
            httpUrl(text) -> text
            !text.contains(' ') && text.contains('.') && !text.contains("://") -> "https://$text"
            else -> "https://duckduckgo.com/?q=${Uri.encode(text)}"
        }
        address.clearFocus()
        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(address.windowToken, 0)
        if (mayMode && !isMayUrl(url)) openMayTarget(url) else web.loadUrl(url)
    }
    private fun detect(url: String, direct: Boolean = false, owner: WebView = web) {
        if (!httpUrl(url)) return
        val parsed = Uri.parse(url)
        if (adHost(parsed.host)) return
        val path = parsed.path?.lowercase(Locale.ROOT) ?: ""
        val mime = parsed.getQueryParameter("mime_type") ?: parsed.getQueryParameter("mime") ?: ""
        val kind = when {
            path.endsWith(".m3u8") -> "HLS"
            listOf(".mp4", ".webm", ".m4v", ".mov").any { path.endsWith(it) } || mime.startsWith("video/") || mime.startsWith("video_") || (direct && (path.endsWith(".mp4") || path.endsWith(".webm") || path.endsWith(".m4v") || path.endsWith(".mov"))) -> "Video"
            else -> return
        }
        handler.post {
            val target = tabMedia[owner] ?: return@post
            if (!isFinishing && target.size < 40 && !target.containsKey(url)) { target[url] = Media(url, kind); if (owner === web) found.text = "Tải video" }
        }
    }
    private fun scanMedia(after: () -> Unit = {}) {
        val owner = web
        owner.evaluateJavascript("""(()=>{
          const candidates=Array.from(document.querySelectorAll('video')).filter(v=>!v.mediaKeys&&v.getBoundingClientRect().width>0&&v.getBoundingClientRect().height>0).sort((a,b)=>(Number(!b.paused&&!b.ended)-Number(!a.paused&&!a.ended))||(b.getBoundingClientRect().width*b.getBoundingClientRect().height-a.getBoundingClientRect().width*a.getBoundingClientRect().height));
          const active=candidates[0];
          const current=active?(active.currentSrc||active.src||''):'';
          const urls=Array.from(document.querySelectorAll('video,video source')).filter(v=>!v.mediaKeys).map(v=>v.currentSrc||v.src);
          document.querySelectorAll('meta[property="og:video"],meta[property="og:video:url"],meta[property="og:video:secure_url"],meta[itemprop="contentUrl"]').forEach(m=>urls.push(m.content));
          performance.getEntriesByType('resource').filter(r=>r.initiatorType==='video').forEach(r=>urls.push(r.name));
          const keys=new Set(['contentUrl','playAddr','downloadAddr','playable_url','playable_url_quality_hd','browser_native_sd_url','browser_native_hd_url']);
          let visited=0;
          const walk=(v,depth)=>{
            if(!v||typeof v!=='object'||depth>24||++visited>30000)return;
            Object.entries(v).forEach(([k,x])=>{
              if(keys.has(k)&&typeof x==='string'&&/^https?:\/\//.test(x))urls.push(x);
              if(x&&typeof x==='object')walk(x,depth+1);
            });
          };
          document.querySelectorAll('script[type="application/json"],script[type="application/ld+json"]').forEach(s=>{if(s.textContent.length<2000000){try{walk(JSON.parse(s.textContent),0)}catch(e){}}});
          return JSON.stringify({current,urls:Array.from(new Set(urls.filter(Boolean))).slice(0,80)});
        })()""") { value ->
            if (owner !== web) return@evaluateJavascript
            try {
                val decoded = org.json.JSONTokener(value).nextValue() as? String ?: "[]"
                val result = org.json.JSONObject(decoded)
                val selected = result.optString("current")
                activeUrls = if (httpUrl(selected)) setOf(selected) else emptySet()
                if (activeUrls.isNotEmpty()) detect(selected, true)
                val list = result.optJSONArray("urls") ?: JSONArray()
                for (i in 0 until list.length()) detect(list.getString(i), true)
            } catch (_: Exception) { }
            handler.post { after() }
        }
    }
    private fun headers(url: String) = mutableMapOf("User-Agent" to web.settings.userAgentString).apply {
        web.url?.takeIf { httpUrl(it) }?.let { put("Referer", it) }
        CookieManager.getInstance().getCookie(url)?.takeIf { it.isNotEmpty() }?.let { put("Cookie", it) }
    }
    private fun showMedia() {
        val host = Uri.parse(web.url ?: "").host ?: ""
        if (host == "youtube.com" || host.endsWith(".youtube.com") || host == "youtu.be") { QuangYouTube.showChoices(this, web.url ?: ""); return }
        scanMedia { if (!isFinishing) showMediaDialog() } }
    private fun showMediaDialog(allSources: Boolean = false) {
        downloadButton = null
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(8), dp(16), dp(8)) }
        val builder = AlertDialog.Builder(this).setTitle(if (allSources) "Mọi nguồn trên trang" else "Video đang xem").setView(ScrollView(this).apply { addView(box) }).setNegativeButton("Đóng", null)
        if (!allSources) builder.setNeutralButton("Nguồn khác (${media.size})") { _, _ -> showMediaDialog(true) }
        val dialog = builder.create()
        val selected = media.values.filter { allSources || it.url in activeUrls }
        if (selected.isEmpty()) box.addView(TextView(this).apply { text = "Chưa xác định được link trực tiếp của video đang xem. Hãy phát video rồi thử lại. Nguồn blob/DRM không được tự gán thành video khác." })
        for (item in selected) {
            val uri = Uri.parse(item.url)
            box.addView(TextView(this).apply { text = "${item.kind} · ${uri.host}\n${uri.lastPathSegment ?: "Video"}"; setPadding(0, dp(12), 0, 0) })
            val row = LinearLayout(this)
            row.addView(button("Xem", "Xem bằng player") { dialog.dismiss(); choose(item) }, LinearLayout.LayoutParams(0, dp(48), 1f))
            val download = button(if (item.kind == "HLS") "HLS: chỉ xem" else "Tải xuống", "Tải video này") { dialog.dismiss(); startDownload(item); showDownloads() }.apply { isEnabled = item.kind != "HLS" }
            if (downloadButton == null && download.isEnabled) downloadButton = download
            row.addView(download, LinearLayout.LayoutParams(0, dp(48), 1f))
            box.addView(row)
        }
        dialog.show()
    }
    private fun choose(item: Media) {
        val data = Intent().putExtra("url", item.url).putExtra("title", web.title ?: "Video trình duyệt")
            .putExtra("page", web.url ?: "").putExtra("headers", org.json.JSONObject(headers(item.url)).toString())
        setResult(RESULT_OK, data); finish()
    }
    private fun startDownload(item: Media) {
        if (item.kind != "Video") return
        if (Build.VERSION.SDK_INT < 29 && checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            pendingDownload = item; requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 3102); return
        }
        try {
            val extension = if (Uri.parse(item.url).path?.endsWith(".webm") == true) "webm" else "mp4"
            val filename = "QuangTV-${System.currentTimeMillis()}.$extension"
            val request = DownloadManager.Request(Uri.parse(QuangProxy.downloadUrl(this, item.url))).setTitle(filename)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, filename)
            for ((key, value) in headers(item.url)) request.addRequestHeader(key, value)
            val id = downloads.enqueue(request)
            val ids = settings.getStringSet("downloads", emptySet())!!.toMutableSet(); ids.add(id.toString())
            settings.edit().putStringSet("downloads", ids).apply()
            Toast.makeText(this, "Đang tải vào Downloads", Toast.LENGTH_SHORT).show()
        } catch (_: Exception) { Toast.makeText(this, "Không bắt đầu được lượt tải", Toast.LENGTH_LONG).show() }
    }
    private fun downloadedBytes(): Long {
        var bytes = 0L
        for (id in settings.getStringSet("downloads", emptySet())!!) {
            downloads.query(DownloadManager.Query().setFilterById(id.toLong())).use { cursor ->
                if (cursor.moveToFirst() && cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)) == DownloadManager.STATUS_SUCCESSFUL) bytes += cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            }
        }
        return bytes
    }
    private fun showDownloads() {
        if (downloadsDialog?.isShowing == true) return
        val rows = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(12), dp(20), dp(12)) }
        val dialog = AlertDialog.Builder(this).setTitle("Tải xuống").setView(ScrollView(this).apply { addView(rows) })
            .setNeutralButton("Hủy tải đang chạy") { _, _ ->
                QuangYouTube.cancel()
                for (id in settings.getStringSet("downloads", emptySet())!!) {
                    downloads.query(DownloadManager.Query().setFilterById(id.toLong())).use { cursor ->
                        if (cursor.moveToFirst() && cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)) in listOf(DownloadManager.STATUS_PENDING, DownloadManager.STATUS_RUNNING, DownloadManager.STATUS_PAUSED)) downloads.remove(id.toLong())
                    }
                }
            }.setNegativeButton("Đóng", null).create()
        val refresh = object : Runnable {
            override fun run() {
                if (!dialog.isShowing) return
                rows.removeAllViews()
                openCompletedButton = null
                if (QuangYouTube.status.isNotEmpty()) rows.addView(TextView(this@QuangBrowserActivity).apply { text = QuangYouTube.status })
                for (uri in QuangYouTube.completed(this@QuangBrowserActivity)) {
                    try { contentResolver.query(uri, arrayOf(android.provider.MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { cursor -> if (cursor.moveToFirst()) rows.addView(button("Mở xem · ${cursor.getString(0)}", "Mở YouTube đã tải") { dialog.dismiss(); openLocalVideo(uri) }) } } catch (_: Exception) { }
                }
                var count = 0
                for (id in settings.getStringSet("downloads", emptySet())!!.sortedBy { it.toLong() }.takeLast(20).reversed()) {
                    downloads.query(DownloadManager.Query().setFilterById(id.toLong())).use { cursor ->
                        if (cursor.moveToFirst()) {
                            val bytes = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                            val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                            val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                            val label = when (status) { DownloadManager.STATUS_SUCCESSFUL -> "Hoàn tất"; DownloadManager.STATUS_FAILED -> "Lỗi tải"; DownloadManager.STATUS_PAUSED -> "Tạm chờ mạng"; else -> "Đang tải" }
                            count++
                            rows.addView(TextView(this@QuangBrowserActivity).apply { text = "${cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TITLE))}\n$label · ${"%.1f".format(bytes / 1000000.0)} / ${if (total > 0) "%.1f MB · %d%%".format(total / 1000000.0, bytes * 100 / total) else "? MB"}" })
                            if (status == DownloadManager.STATUS_SUCCESSFUL) {
                                val open = button("Mở xem", "Mở video đã tải") { dialog.dismiss(); openDownloaded(id.toLong()) }
                                if (openCompletedButton == null) openCompletedButton = open
                                rows.addView(open)
                            }
                        }
                    }
                }
                if (count == 0) rows.addView(TextView(this@QuangBrowserActivity).apply { text = "Chưa có lượt tải. Tệp đã tải nằm trong Downloads của Android." })
                handler.postDelayed(this, 800)
            }
        }
        downloadsDialog = dialog
        dialog.setOnDismissListener { handler.removeCallbacks(refresh); downloadsDialog = null }
        dialog.show(); refresh.run()
    }
    private fun installMediaMute(view: WebView) {
        // A persistent DOM observer covers SPA navigation and dynamically inserted players.
        // WebView cannot mute cross-origin iframes; those require native audio policy.
        view.evaluateJavascript("""(()=>{
          if(window.__quangMuteInstalled)return;
          window.__quangMuteInstalled=true;
          const mute=()=>{
            document.querySelectorAll('video,audio').forEach(m=>{
              if(m.__quangUserAudio)return;
              if(!m.muted)m.muted=true;
              if(m.volume!==0)m.volume=0;
              m.setAttribute('muted','');
              m.defaultMuted=true;
            });
          };
          document.addEventListener('play',mute,true);
          document.addEventListener('playing',mute,true);
          new MutationObserver(mute).observe(document.documentElement,{childList:true,subtree:true});
          setInterval(mute,150);
          mute();
        })()""", null)
    }
    private fun installAdGuard(view: WebView) {
        if (!blockAds) return
        view.evaluateJavascript("""(()=>{
          if(window.__quangAdGuard)return;
          window.__quangAdGuard=true;
          const blocked=['doubleclick.net','googlesyndication.com','exoclick.com','trafficjunky.net','popads.net','popcash.net','adsterra.com','propellerads.com','juicyads.com','tsyndicate.com'];
          const adUrl=value=>{try{const h=new URL(value,location.href).hostname;return blocked.some(d=>h===d||h.endsWith('.'+d))}catch{return false}};
          window.open=()=>null;
          document.addEventListener('click',e=>{
            const a=e.target?.closest?.('a[href]');
            if(a&&(adUrl(a.href)||a.target==='_blank')){e.preventDefault();e.stopImmediatePropagation();}
          },true);
        })()""", null)
    }
    private fun applyAdStyle(view: WebView) {
        if (!blockAds) { view.evaluateJavascript("document.getElementById('quang-ad-style')?.remove()", null); return }
        view.evaluateJavascript("""(()=>{if(document.getElementById('quang-ad-style'))return;const s=document.createElement('style');s.id='quang-ad-style';s.textContent='.adsbygoogle,.advertisement,.ad-container,[data-ad-slot],iframe[src*="doubleclick.net"],iframe[src*="exoclick.com"],iframe[src*="juicyads.com"],iframe[src*="popads.net"]{display:none!important}';(document.head||document.documentElement).appendChild(s)})()""", null)
    }
    private fun updateProxyButton() {
        proxyButton.text = if (mayMode) "Mây" else "P"
        proxyButton.contentDescription = if (mayMode) "Đang duyệt riêng qua Mây" else "Bật/tắt proxy"
        if (mayMode) { proxyButton.setTextColor(Color.rgb(0, 140, 140)); return }
        try { proxyButton.setTextColor(if (QuangProxy.state(this)["enabled"] == true) Color.rgb(0, 140, 70) else Color.DKGRAY) } catch (_: Exception) { proxyButton.setTextColor(Color.RED) }
    }
    private fun toggleProxy() {
        if (mayMode) { showOptions(); return }
        try {
            val enabled = QuangProxy.state(this)["enabled"] == true
            QuangProxy.toggle(this, !enabled)
            QuangProxy.applyWeb(this, { updateProxyButton(); web.reload() }, { Toast.makeText(this, "Không áp dụng được proxy", Toast.LENGTH_LONG).show() })
        } catch (_: Exception) { Toast.makeText(this, "Hãy lưu cấu hình proxy trong Cài đặt trước", Toast.LENGTH_LONG).show() }
    }
    private fun openDownloaded(id: Long) {
        val uri = downloads.getUriForDownloadedFile(id) ?: return
        openLocalVideo(uri)
    }
    private fun openLocalVideo(uri: Uri) {
        web.evaluateJavascript("document.querySelectorAll('video').forEach(v=>v.pause())", null)
        val video = VideoView(this)
        val controller = MediaController(this).apply { setAnchorView(video) }
        video.setMediaController(controller)
        val dialog = AlertDialog.Builder(this).setTitle("Video đã tải").setView(video).setNegativeButton("Đóng", null).create()
        previewDialog = dialog; previewPlayer = video
        dialog.setOnDismissListener { video.stopPlayback(); previewDialog = null; previewPlayer = null }
        video.setOnErrorListener { _, _, _ -> Toast.makeText(this, "Không mở được tệp video đã tải", Toast.LENGTH_LONG).show(); dialog.dismiss(); true }
        dialog.show()
        dialog.window?.setLayout(-1, (resources.displayMetrics.heightPixels * 0.85).toInt())
        video.setOnPreparedListener { video.start() }; video.setVideoURI(uri)
    }
    override fun onConfigurationChanged(config: android.content.res.Configuration) {
        super.onConfigurationChanged(config)
        android.util.Log.i("QuangBrowserLayout", "orientation=${config.orientation}")
        address.clearFocus(); root.requestFocus()
        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(root.windowToken, 0)
        if (config.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE) {
            if (mayMode) {
                web.evaluateJavascript("(()=>!!document.querySelector('video')||document.querySelector('#browser')?.hidden===false)()") { result ->
                    if (result == "true") {
                        orientationFullscreen = true
                        addressBar.visibility = View.GONE; toolbar.visibility = View.GONE; progress.visibility = View.GONE
                        WindowCompat.getInsetsController(window, root).hide(WindowInsetsCompat.Type.systemBars())
                        ViewCompat.requestApplyInsets(root)
                    }
                }
                return
            }
            web.evaluateJavascript("""(()=>{const v=Array.from(document.querySelectorAll('video')).find(v=>!v.paused&&!v.ended&&!v.mediaKeys);if(!v)return false;const parents=[];for(let p=v.parentElement;p;p=p.parentElement){parents.push([p,p.getAttribute('style')]);p.style.setProperty('transform','none','important');p.style.setProperty('position','static','important');p.style.setProperty('overflow','visible','important');}window.__quangFull={v,s:v.getAttribute('style'),parents};v.style.cssText+=';position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;z-index:2147483645!important;background:black!important;object-fit:contain!important';return true})()""") { result ->
                if (result == "true") { installLandscapeControls(); address.clearFocus(); root.requestFocus(); (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(address.windowToken, 0); orientationFullscreen = true; addressBar.visibility = View.GONE; toolbar.visibility = View.GONE; progress.visibility = View.GONE; WindowCompat.getInsetsController(window, root).hide(WindowInsetsCompat.Type.systemBars()); ViewCompat.requestApplyInsets(root) }
            }
        } else exitOrientationFullscreen()
    }
    private fun installLandscapeControls() {
        web.evaluateJavascript("""(()=>{
          const v=window.__quangFull?.v;
          if(!v || document.getElementById('quang-landscape-controls'))return;
          const bar=document.createElement('div');
          bar.id='quang-landscape-controls';
          bar.style.cssText='position:fixed!important;bottom:0!important;left:0!important;right:0!important;z-index:2147483647!important;display:flex!important;flex-wrap:wrap!important;align-items:center!important;justify-content:center!important;gap:12px!important;padding:14px!important;background:rgba(0,0,0,.55)!important;color:white!important';
          const btn=(label,action)=>{const b=document.createElement('button');b.textContent=label;b.style.cssText='font-size:18px;padding:9px;color:white;background:#333;border:1px solid #888;border-radius:8px';b.onclick=e=>{e.preventDefault();e.stopPropagation();action()};bar.appendChild(b)};
          const seek=delta=>{if(Number.isFinite(v.duration)&&v.duration>0)v.currentTime=Math.max(0,Math.min(v.duration,v.currentTime+delta));};
          btn('−10s',()=>seek(-10));
          btn('▶ / ❚❚',()=>v.paused?v.play():v.pause());
          btn('+10s',()=>seek(10));
          btn('Âm thanh',()=>{v.__quangUserAudio=true;v.muted=!v.muted;v.volume=v.muted?0:1;});
          const volume=document.createElement('input');volume.type='range';volume.min='0';volume.max='1';volume.step='0.05';volume.value=String(v.muted?0:v.volume);
          volume.style.cssText='width:95px;max-width:20vw';volume.setAttribute('aria-label','Âm lượng');
          volume.oninput=()=>{v.__quangUserAudio=true;v.volume=Number(volume.value);v.muted=v.volume===0;};
          bar.appendChild(volume);
          const timeline=document.createElement('input');timeline.type='range';timeline.min='0';timeline.max='1000';timeline.value='0';timeline.setAttribute('aria-label','Tua video');timeline.style.cssText='width:90%;flex-basis:90%';
          timeline.oninput=()=>{if(Number.isFinite(v.duration)&&v.duration>0)v.currentTime=Number(timeline.value)/1000*v.duration;};
          const updateTime=()=>{timeline.disabled=!Number.isFinite(v.duration)||v.duration<=0;if(!timeline.disabled)timeline.value=String(v.currentTime/v.duration*1000);};
          v.addEventListener('timeupdate',updateTime);updateTime();bar.appendChild(timeline);
          const reveal=()=>{bar.style.opacity='1';bar.style.pointerEvents='auto';clearTimeout(window.__quangHideControls);window.__quangHideControls=setTimeout(()=>{bar.style.opacity='0';bar.style.pointerEvents='none'},4000)};
          v.addEventListener('click',reveal);
          let lastTap=null;
          v.addEventListener('pointerup',e=>{const now=performance.now(),side=e.clientX<innerWidth/2?-1:1;if(lastTap&&lastTap.side===side&&now-lastTap.time<350&&Math.hypot(e.clientX-lastTap.x,e.clientY-lastTap.y)<48){e.preventDefault();seek(side*10);lastTap=null;}else lastTap={side,time:now,x:e.clientX,y:e.clientY};reveal();},{passive:false});
          document.documentElement.appendChild(bar);reveal();
        })()""", null)
    }
    private fun exitOrientationFullscreen() {
        orientationFullscreen = false
        web.evaluateJavascript("document.getElementById('quang-landscape-controls')?.remove()", null)
        web.evaluateJavascript("""(()=>{const x=window.__quangFull;if(x){if(x.s===null)x.v.removeAttribute('style');else x.v.setAttribute('style',x.s);for(const [p,s]of x.parents||[]){if(s===null)p.removeAttribute('style');else p.setAttribute('style',s)}delete window.__quangFull}})()""", null)
        addressBar.visibility = View.VISIBLE; toolbar.visibility = View.VISIBLE
        WindowCompat.getInsetsController(window, root).show(WindowInsetsCompat.Type.systemBars()); ViewCompat.requestApplyInsets(root)
    }
    private fun showOptions() {
        AlertDialog.Builder(this).setTitle("Trình duyệt")
            .setMultiChoiceItems(arrayOf("Chặn quảng cáo phổ biến"), booleanArrayOf(blockAds)) { _, _, checked ->
                blockAds = checked; settings.edit().putBoolean("blockAds", checked).apply(); tabs.forEach { applyAdStyle(it) }
            }
            .setNegativeButton(if (mayMode) "Trình duyệt gốc" else "Mở qua Mây") { _, _ ->
                if (mayMode) {
                    mayMode = false; pendingMayTarget = null
                    applyBrowserTransport({ updateProxyButton(); web.loadUrl("about:blank") }, { Toast.makeText(this, "Không đổi được đường duyệt", Toast.LENGTH_LONG).show() })
                } else openMayTarget(web.url)
            }
            .setNeutralButton("Kiểm tra IP") { _, _ -> QuangProxy.test(this) { value -> Toast.makeText(this, if (value == null) "Proxy chưa kết nối được hoặc đang tắt" else "IP: ${value["ip"]} · ${value["ms"]} ms", Toast.LENGTH_LONG).show() } }
            .setPositiveButton("Đóng", null).show()
    }
    private fun exitFullscreen() {
        fullscreen?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }; fullscreen = null
        fullscreenCallback?.onCustomViewHidden(); fullscreenCallback = null
        if (!orientationFullscreen) WindowCompat.getInsetsController(window, root).show(WindowInsetsCompat.Type.systemBars())
    }
    override fun onBackPressed() { if (fullscreen != null) exitFullscreen() else if (orientationFullscreen) exitOrientationFullscreen() else if (web.canGoBack()) web.goBack() else if (tabs.size > 1) closeTab(web) else super.onBackPressed() }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        if (code == 3102 && results.firstOrNull() == PackageManager.PERMISSION_GRANTED) pendingDownload?.let { startDownload(it) }
        pendingDownload = null
    }
    override fun onSaveInstanceState(out: Bundle) { web.saveState(out); super.onSaveInstanceState(out) }
    override fun onResume() { super.onResume(); web.onResume() }
    override fun onPause() { downloadsDialog?.dismiss(); previewDialog?.dismiss(); tabsDialog?.dismiss(); android.webkit.CookieManager.getInstance().flush(); web.onPause(); super.onPause() }
    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null); exitFullscreen(); current = null
        if (mayMode) QuangProxy.applyWeb(this, {}, {})
        root.removeView(web); for (view in tabs) view.destroy(); tabs.clear(); tabMedia.clear(); super.onDestroy()
    }
}
