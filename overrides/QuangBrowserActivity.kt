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
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import java.io.ByteArrayInputStream
import java.lang.ref.WeakReference
import java.util.Locale
import org.json.JSONArray

/** System WebView, direct media discovery and Android-managed downloads. No proxy or extraction backend. */
class QuangBrowserActivity : Activity() {
    data class Media(val url: String, val kind: String)
    companion object {
        private var current: WeakReference<QuangBrowserActivity>? = null
        fun inspect(): Map<String, Any> = current?.get()?.let {
            val point = IntArray(2); it.root.getLocationOnScreen(point)
            val insets = ViewCompat.getRootWindowInsets(it.root)
            mapOf("count" to it.media.size, "top" to point[1] + it.root.paddingTop,
                "statusBar" to (insets?.getInsets(WindowInsetsCompat.Type.statusBars())?.top ?: 0),
                "downloaded" to it.downloadedBytes(), "height" to it.web.height, "ime" to (insets?.isVisible(WindowInsetsCompat.Type.ime()) ?: false))
        } ?: emptyMap()
        fun testAction(action: String) {
            current?.get()?.let {
                when (action) {
                    "focus" -> { it.address.requestFocus(); (it.getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).showSoftInput(it.address, InputMethodManager.SHOW_IMPLICIT) }
                    "select" -> it.media.values.firstOrNull()?.let { candidate -> it.choose(candidate) }
                    "download" -> it.media.values.firstOrNull()?.let { candidate -> it.startDownload(candidate) }
                    "clearDownloads" -> {
                        for (id in it.settings.getStringSet("downloads", emptySet())!!) it.downloads.remove(id.toLong())
                        it.settings.edit().remove("downloads").apply()
                    }
                    "close" -> it.finish()
                }
            }
        }
    }
    private lateinit var root: LinearLayout
    private lateinit var web: WebView
    private lateinit var address: EditText
    private lateinit var found: Button
    private lateinit var progress: ProgressBar
    private val media = LinkedHashMap<String, Media>()
    private val handler = Handler(Looper.getMainLooper())
    private val downloads by lazy { getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager }
    private val settings by lazy { getSharedPreferences("quangtv_browser", MODE_PRIVATE) }
    @Volatile private var blockAds = true
    private var pendingDownload: Media? = null
    private var fullscreen: View? = null
    private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null
    private val adHosts = setOf("doubleclick.net", "googlesyndication.com", "googleadservices.com", "adnxs.com")
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun httpUrl(value: String): Boolean = Uri.parse(value).let { it.scheme in listOf("http", "https") && !it.host.isNullOrEmpty() }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        blockAds = settings.getBoolean("blockAds", true)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.WHITE) }
        WindowCompat.getInsetsController(window, root).apply { isAppearanceLightStatusBars = true; isAppearanceLightNavigationBars = true }
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
            view.setPadding(bars.left, bars.top, bars.right, maxOf(bars.bottom, ime.bottom))
            WindowInsetsCompat.CONSUMED
        }
        val bar = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(6), 0, dp(6), 0) }
        address = EditText(this).apply {
            textSize = 14f; setSingleLine(true); hint = "Địa chỉ web hoặc từ khóa"
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_URI
            imeOptions = EditorInfo.IME_ACTION_GO
            setOnEditorActionListener { _, action, _ ->
                if (action == EditorInfo.IME_ACTION_GO) { navigate(text.toString()); true } else false
            }
        }
        bar.addView(address, LinearLayout.LayoutParams(0, dp(52), 1f))
        bar.addView(button("↻", "Tải lại") { web.reload() }, LinearLayout.LayoutParams(dp(48), dp(48)))
        root.addView(bar)
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal)
        root.addView(progress, LinearLayout.LayoutParams(-1, dp(3)))
        web = WebView(this)
        root.addView(web, LinearLayout.LayoutParams(-1, 0, 1f))
        val tools = LinearLayout(this).apply { gravity = Gravity.CENTER; setBackgroundColor(Color.WHITE) }
        tools.addView(button("‹", "Quay lại") { if (web.canGoBack()) web.goBack() else finish() }, LinearLayout.LayoutParams(dp(48), dp(48)))
        tools.addView(button("›", "Tiến tới") { if (web.canGoForward()) web.goForward() }, LinearLayout.LayoutParams(dp(48), dp(48)))
        found = button("Video (0)", "Video tìm thấy") { showMedia() }
        tools.addView(found, LinearLayout.LayoutParams(0, dp(48), 1f))
        tools.addView(button("Tải", "Quản lý tải xuống") { showDownloads() }, LinearLayout.LayoutParams(dp(52), dp(48)))
        tools.addView(button("⋮", "Tùy chọn") { showOptions() }, LinearLayout.LayoutParams(dp(48), dp(48)))
        root.addView(tools)
        setContentView(root)
        ViewCompat.requestApplyInsets(root)
        web.settings.apply {
            javaScriptEnabled = true; domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            setSupportMultipleWindows(false)
        }
        web.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                media.clear(); found.text = "Video (0)"; address.setText(url?.takeIf { httpUrl(it) } ?: "")
            }
            override fun onPageFinished(view: WebView, url: String?) { scanMedia() }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = !httpUrl(request.url.toString())
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                val uri = request.url
                if (blockAds && !request.isForMainFrame && adHosts.any { uri.host == it || uri.host?.endsWith(".$it") == true }) {
                    return WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(ByteArray(0)))
                }
                if (request.method == "GET") detect(uri.toString())
                return null
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, value: Int) { progress.progress = value; progress.visibility = if (value == 100) View.GONE else View.VISIBLE }
            override fun onShowCustomView(view: View?, callback: CustomViewCallback?) {
                if (view == null || fullscreen != null) { callback?.onCustomViewHidden(); return }
                fullscreen = view; fullscreenCallback = callback
                (window.decorView as android.view.ViewGroup).addView(view, android.view.ViewGroup.LayoutParams(-1, -1))
            }
            override fun onHideCustomView() { exitFullscreen() }
        }
        web.setDownloadListener { url, _, _, mime, _ ->
            if (mime?.startsWith("video/") == true || mime == "application/octet-stream") {
                detect(url, true); showMedia()
            } else Toast.makeText(this, "Chỉ hỗ trợ tải tệp video trực tiếp", Toast.LENGTH_SHORT).show()
        }
        current = WeakReference(this)
        val initial = intent.getStringExtra("url") ?: ""
        if (state != null) web.restoreState(state)
        else if (httpUrl(initial)) web.loadUrl(initial)
        else web.loadData("<meta name='viewport' content='width=device-width'><h2>QuangTV · Trình duyệt</h2><p>Nhập địa chỉ hoặc từ khóa ở trên. Nhấn Video để xem nguồn phát tìm thấy rồi chọn xem hoặc tải.</p><p>Hỗ trợ nguồn MP4/WebM và HLS trực tiếp. Không giải mã DRM, không gỡ watermark. Chỉ tải nội dung bạn có quyền lưu.</p>", "text/html", "UTF-8")
    }
    private fun button(label: String, description: String, action: () -> Unit) = Button(this).apply {
        text = label; textSize = 12f; contentDescription = description
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
        web.loadUrl(url)
    }
    private fun detect(url: String, direct: Boolean = false) {
        if (!httpUrl(url)) return
        val path = Uri.parse(url).path?.lowercase(Locale.ROOT) ?: ""
        val kind = when {
            path.endsWith(".m3u8") -> "HLS"
            listOf(".mp4", ".webm", ".m4v", ".mov").any { path.endsWith(it) } || direct -> "Video"
            else -> return
        }
        handler.post {
            if (!isFinishing && media.size < 40 && !media.containsKey(url)) {
                media[url] = Media(url, kind); found.text = "Video (${media.size})"
            }
        }
    }
    private fun scanMedia(after: () -> Unit = {}) {
        web.evaluateJavascript("""JSON.stringify(Array.from(document.querySelectorAll('video,video source')).filter(v=>!v.mediaKeys).map(v=>v.currentSrc||v.src).filter(Boolean))""") { value ->
            try {
                val decoded = org.json.JSONTokener(value).nextValue() as? String ?: "[]"
                val list = JSONArray(decoded)
                for (i in 0 until list.length()) detect(list.getString(i), true)
            } catch (_: Exception) { }
            handler.post { after() }
        }
    }
    private fun headers(url: String) = mutableMapOf("User-Agent" to web.settings.userAgentString).apply {
        web.url?.takeIf { httpUrl(it) }?.let { put("Referer", it) }
        CookieManager.getInstance().getCookie(url)?.takeIf { it.isNotEmpty() }?.let { put("Cookie", it) }
    }
    private fun showMedia() { scanMedia { if (!isFinishing) showMediaDialog() } }
    private fun showMediaDialog() {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(8), dp(16), dp(8)) }
        val dialog = AlertDialog.Builder(this).setTitle("Video tìm thấy").setView(ScrollView(this).apply { addView(box) }).setNegativeButton("Đóng", null).create()
        if (media.isEmpty()) box.addView(TextView(this).apply { text = "Chưa thấy nguồn video trực tiếp. Hãy phát video trên trang rồi thử lại. Video blob/DRM hoặc nguồn bị hạn chế có thể không hỗ trợ." })
        for (item in media.values.toList()) {
            val uri = Uri.parse(item.url)
            box.addView(TextView(this).apply { text = "${item.kind} · ${uri.host}\n${uri.lastPathSegment ?: "Video"}"; setPadding(0, dp(12), 0, 0) })
            val row = LinearLayout(this)
            row.addView(button("Xem", "Xem bằng player") { dialog.dismiss(); choose(item) }, LinearLayout.LayoutParams(0, dp(48), 1f))
            row.addView(button(if (item.kind == "HLS") "HLS: chỉ xem" else "Tải", "Tải video") { startDownload(item) }.apply { isEnabled = item.kind != "HLS" }, LinearLayout.LayoutParams(0, dp(48), 1f))
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
            val request = DownloadManager.Request(Uri.parse(item.url)).setTitle(filename)
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
        val text = TextView(this).apply { setPadding(dp(20), dp(12), dp(20), dp(12)); setTextIsSelectable(true) }
        val dialog = AlertDialog.Builder(this).setTitle("Tải xuống").setView(ScrollView(this).apply { addView(text) })
            .setNeutralButton("Hủy tải đang chạy") { _, _ ->
                for (id in settings.getStringSet("downloads", emptySet())!!) {
                    downloads.query(DownloadManager.Query().setFilterById(id.toLong())).use { cursor ->
                        if (cursor.moveToFirst() && cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)) in listOf(DownloadManager.STATUS_PENDING, DownloadManager.STATUS_RUNNING, DownloadManager.STATUS_PAUSED)) downloads.remove(id.toLong())
                    }
                }
            }.setNegativeButton("Đóng", null).create()
        val refresh = object : Runnable {
            override fun run() {
                if (!dialog.isShowing) return
                val lines = ArrayList<String>()
                for (id in settings.getStringSet("downloads", emptySet())!!.sortedBy { it.toLong() }.takeLast(20).reversed()) {
                    downloads.query(DownloadManager.Query().setFilterById(id.toLong())).use { cursor ->
                        if (cursor.moveToFirst()) {
                            val bytes = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                            val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                            val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                            val label = when (status) { DownloadManager.STATUS_SUCCESSFUL -> "Hoàn tất"; DownloadManager.STATUS_FAILED -> "Lỗi tải"; DownloadManager.STATUS_PAUSED -> "Tạm chờ mạng"; else -> "Đang tải" }
                            lines.add("${cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TITLE))}\n$label · ${"%.1f".format(bytes / 1000000.0)} / ${if (total > 0) "%.1f MB · %d%%".format(total / 1000000.0, bytes * 100 / total) else "? MB"}")
                        }
                    }
                }
                text.text = if (lines.isEmpty()) "Chưa có lượt tải. Tệp đã tải nằm trong thư mục Downloads của Android." else lines.joinToString("\n\n")
                handler.postDelayed(this, 800)
            }
        }
        dialog.setOnDismissListener { handler.removeCallbacks(refresh) }
        dialog.show(); refresh.run()
    }
    private fun showOptions() {
        AlertDialog.Builder(this).setTitle("Trình duyệt")
            .setMultiChoiceItems(arrayOf("Chặn quảng cáo phổ biến"), booleanArrayOf(blockAds)) { _, _, checked ->
                blockAds = checked; settings.edit().putBoolean("blockAds", checked).apply()
            }
            .setPositiveButton("Đóng", null).show()
    }
    private fun exitFullscreen() {
        fullscreen?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }; fullscreen = null
        fullscreenCallback?.onCustomViewHidden(); fullscreenCallback = null
    }
    override fun onBackPressed() { if (fullscreen != null) exitFullscreen() else if (web.canGoBack()) web.goBack() else super.onBackPressed() }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        if (code == 3102 && results.firstOrNull() == PackageManager.PERMISSION_GRANTED) pendingDownload?.let { startDownload(it) }
        pendingDownload = null
    }
    override fun onSaveInstanceState(out: Bundle) { web.saveState(out); super.onSaveInstanceState(out) }
    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null); exitFullscreen(); current = null
        root.removeView(web); web.destroy(); super.onDestroy()
    }
}
