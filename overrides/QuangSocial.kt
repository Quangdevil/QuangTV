package app.tvviewer.player

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URI
import java.net.URL
import java.net.URLDecoder
import java.util.concurrent.Executors

/** Public share pages only. No cookies, login, challenge solving or third-party parsers. */
object QuangSocial {
    private const val MAX_HTML = 6 * 1024 * 1024
    private val worker = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private val pageDomains = listOf("facebook.com", "fb.com", "fb.watch", "tiktok.com", "douyin.com", "iesdouyin.com")
    private val mobileUa = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private fun isDomain(host: String, domain: String) = host == domain || host.endsWith(".$domain")

    /** Accept the entire copied share message, but never turn arbitrary text into a request. */
    fun shareUrl(text: String): String {
        require(text.length <= 16000) { "Đoạn chia sẻ quá dài" }
        for (match in Regex("https?://[^\\s<>\\\"'，。！？、]+", RegexOption.IGNORE_CASE).findAll(text)) {
            val value = match.value.trimEnd(')', ']', '}', '.', ',', ';', '!', '?', '）', '】', '》')
            val uri = try { URI(value) } catch (_: Exception) { continue }
            val host = uri.host?.lowercase() ?: continue
            if (uri.userInfo == null && uri.port in listOf(-1, 80, 443) && pageDomains.any { isDomain(host, it) }) return value
        }
        throw IllegalArgumentException("Dán link hoặc đoạn chia sẻ Facebook, TikTok hay Douyin")
    }

    fun platform(url: String): String {
        val host = URI(url).host?.lowercase() ?: ""
        return when {
            isDomain(host, "douyin.com") || isDomain(host, "iesdouyin.com") -> "Douyin"
            isDomain(host, "tiktok.com") -> "TikTok"
            else -> "Facebook"
        }
    }

    /** Call off the UI thread. Apply again before following each media redirect. */
    fun validatePublicUrl(value: String): URI {
        val uri = URI(value)
        require(uri.scheme?.lowercase() in listOf("https", "http") && uri.userInfo == null && uri.port in listOf(-1, 80, 443)) { "Địa chỉ video không hợp lệ" }
        val host = uri.host?.lowercase() ?: error("Không có máy chủ")
        require(host.contains('.') && !host.endsWith(".local") && !host.endsWith(".localhost") && !host.endsWith(".internal")) { "Không hỗ trợ địa chỉ mạng nội bộ" }
        val addresses = InetAddress.getAllByName(host)
        require(addresses.isNotEmpty() && addresses.all { address ->
            if (address.isAnyLocalAddress || address.isLoopbackAddress || address.isLinkLocalAddress || address.isSiteLocalAddress || address.isMulticastAddress) false
            else {
                val b = address.address.map { it.toInt() and 255 }
                if (b.size == 4) !(b[0] == 0 || b[0] == 127 || b[0] >= 224 || (b[0] == 100 && b[1] in 64..127) || (b[0] == 198 && b[1] in 18..19) || (b[0] == 192 && b[1] == 0 && b[2] in listOf(0, 2)) || (b[0] == 198 && b[1] == 51 && b[2] == 100) || (b[0] == 203 && b[1] == 0 && b[2] == 113))
                else b.size == 16 && (b[0] and 0xe0) == 0x20
            }
        }) { "Không hỗ trợ địa chỉ mạng nội bộ" }
        return uri
    }

    private data class Page(val url: String, val html: String)
    private fun contentId(value: String): String? {
        val uri = try { URI(value) } catch (_: Exception) { return null }
        Regex("/(?:share/)?video/(\\d{10,})").find(uri.path ?: "")?.let { return it.groupValues[1] }
        Regex("(?:^|&)(?:aweme_id|modal_id|v)=(\\d{10,})(?:&|$)").find(uri.rawQuery ?: "")?.let { return it.groupValues[1] }
        return null
    }
    private fun fetch(raw: String): Page {
        var target = raw
        var expectedId = contentId(raw)
        repeat(6) {
            val uri = validatePublicUrl(target)
            require(pageDomains.any { isDomain(uri.host.lowercase(), it) }) { "Link chuyển tới trang không được hỗ trợ" }
            val redirectedId = contentId(target)
            if (expectedId != null && redirectedId != null) require(expectedId == redirectedId) { "Trang chuyển sang video khác; chưa thể tải đúng video gốc" }
            if (expectedId == null) expectedId = redirectedId
            val connection = URL(target).openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 12000
                connection.readTimeout = 15000
                connection.setRequestProperty("User-Agent", mobileUa)
                connection.setRequestProperty("Accept", "text/html,application/xhtml+xml")
                connection.setRequestProperty("Accept-Encoding", "identity")
                val code = connection.responseCode
                if (code in listOf(301, 302, 303, 307, 308)) {
                    target = uri.resolve(connection.getHeaderField("Location") ?: error("Link chuyển hướng thiếu địa chỉ")).toString()
                } else {
                    require(code in 200..299) { "${platform(raw)} chưa cho đọc nguồn video (HTTP $code). Thử mở video trong trình duyệt." }
                    val contentType = connection.contentType ?: ""
                    require(contentType.contains("html", true) || contentType.contains("json", true)) { "Không nhận được trang video" }
                    val out = java.io.ByteArrayOutputStream()
                    connection.inputStream.use { input ->
                        val buffer = ByteArray(16384)
                        while (true) {
                            val size = input.read(buffer)
                            if (size < 0) break
                            require(out.size() + size <= MAX_HTML) { "Trang video quá lớn" }
                            out.write(buffer, 0, size)
                        }
                    }
                    return Page(target, out.toString("UTF-8"))
                }
            } finally { connection.disconnect() }
        }
        error("Link chuyển hướng quá nhiều lần")
    }

    fun resolvePage(text:String,done:(String?,String?)->Unit) {
        worker.execute {
            try {
                val input=shareUrl(text)
                val target=if(contentId(input)!=null)input else fetch(input).url
                main.post{done(target,null)}
            }catch(e:Exception){main.post{done(null,e.message ?: "Không mở được link chia sẻ")}}
        }
    }

    @Suppress("UNUSED_PARAMETER")
    fun resolve(context: Context, text: String, done: (Map<String, Any>?, String?) -> Unit) {
        worker.execute {
            try {
                val input = shareUrl(text)
                val page = fetch(input)
                val result = parse(page.url, page.html)
                val choices = (result["choices"] as? List<*>)?.filterIsInstance<Map<String, Any>>() ?: emptyList()
                val valid = choices.filter { choice -> try { validatePublicUrl(choice["url"] as String); true } catch (_: Exception) { false } }
                if (valid.isEmpty()) {
                    val label = platform(input)
                    val reason = when {
                        Regex("captcha|verify you are human|验证|访问频繁", RegexOption.IGNORE_CASE).containsMatchIn(page.html) -> "$label yêu cầu xác minh. Mở video trong trình duyệt để kiểm tra."
                        else -> "Chưa lấy được nguồn $label công khai. Video có thể cần đăng nhập, bị giới hạn hoặc cấu trúc trang đã đổi. Thử mở video trong trình duyệt và phát để bắt nguồn."
                    }
                    main.post { done(null, reason) }
                } else main.post { done(result + ("choices" to valid), null) }
            } catch (e: Exception) {
                val message = e.message?.take(250) ?: "Không đọc được link video. Kiểm tra mạng rồi thử lại."
                main.post { done(null, message) }
            }
        }
    }

    /** Pure bounded parser, also used by deterministic Android integration fixtures. */
    fun parse(page: String, html: String): Map<String, Any> {
        require(html.length <= MAX_HTML) { "Trang video quá lớn" }
        val label = platform(page)
        val expectedId = contentId(page)
        val sources = linkedMapOf<String, Map<String, Any>>()
        var title = "Video $label"
        var budget = 60000
        fun decoded(value: String): String = value.replace("&amp;", "&").replace("&#38;", "&").replace("&#x26;", "&").replace("\\/", "/")
        fun add(raw: String, quality: String, source: String) {
            val url = decoded(raw)
            val uri = try { URI(url) } catch (_: Exception) { return }
            if (uri.scheme !in listOf("https", "http") || uri.host.isNullOrEmpty() || uri.userInfo != null || uri.port !in listOf(-1, 80, 443) || url.length > 12000 || sources.size >= 24) return
            sources.putIfAbsent(url, mapOf("url" to url, "quality" to quality, "watermark" to "unknown", "source" to source))
        }
        fun address(value: Any?, quality: String, source: String) {
            when (value) {
                is String -> add(value, quality, source)
                is JSONObject -> {
                    val list = value.optJSONArray("url_list") ?: value.optJSONArray("urlList")
                    if (list != null) for (i in 0 until minOf(list.length(), 8)) add(list.optString(i), quality, source)
                    for (key in listOf("UrlList", "url", "src")) {
                        val item = value.opt(key)
                        if (item is String) add(item, quality, source)
                        if (item is JSONArray) for (i in 0 until minOf(item.length(), 8)) add(item.optString(i), quality, source)
                    }
                }
                is JSONArray -> for (i in 0 until minOf(value.length(), 8)) if (value.opt(i) is String) add(value.optString(i), quality, source)
            }
        }
        fun walk(value: Any?, depth: Int) {
            if (depth > 40 || budget-- <= 0 || sources.size >= 24) return
            when (value) {
                is JSONObject -> {
                    if (value.has("video") && value.opt("video") is JSONObject) {
                        val itemId = value.optString("aweme_id").ifBlank { value.optString("id") }
                        if (expectedId != null && itemId.matches(Regex("\\d{10,}")) && itemId != expectedId) return
                        for (key in listOf("desc", "title")) value.optString(key).takeIf { it.isNotBlank() }?.let { title = it.take(300) }
                    }
                    // Playback addresses precede download addresses, which can include a platform logo.
                    for (key in listOf("play_addr", "playAddr", "play_addr_h264", "playAddrH264")) address(value.opt(key), "Nguồn phát", "play")
                    for (key in listOf("browser_native_hd_url", "playable_url_quality_hd")) address(value.opt(key), "HD", "play")
                    for (key in listOf("browser_native_sd_url", "playable_url")) address(value.opt(key), "SD", "play")
                    val rates = value.optJSONArray("bit_rate") ?: value.optJSONArray("bitRate")
                    if (rates != null) for (i in 0 until minOf(rates.length(), 12)) {
                        val rate = rates.optJSONObject(i) ?: continue
                        val description = rate.optString("gear_name").ifBlank { rate.optString("gearName").ifBlank { "Nguồn phát" } }
                        address(rate.opt("play_addr") ?: rate.opt("playAddr"), description, "play")
                    }
                    for (key in listOf("download_addr", "downloadAddr")) address(value.opt(key), "Nguồn tải · Chưa xác định watermark", "download")
                    val keys = value.keys()
                    while (keys.hasNext()) walk(value.opt(keys.next()), depth + 1)
                }
                is JSONArray -> for (i in 0 until minOf(value.length(), 3000)) walk(value.opt(i), depth + 1)
            }
        }
        val lowerHtml = html.lowercase()
        // Scan tags linearly: repeated unclosed script tags must not cause regex backtracking.
        var cursor = 0
        var scriptCount = 0
        while (cursor < html.length && scriptCount++ < 300) {
            val start = lowerHtml.indexOf("<script", cursor)
            if (start < 0) break
            val openEnd = lowerHtml.indexOf('>', start + 7)
            if (openEnd < 0) break
            val end = lowerHtml.indexOf("</script", openEnd + 1)
            if (end < 0) break
            cursor = end + 8
            val attrs = html.substring(start + 7, openEnd)
            val body = html.substring(openEnd + 1, end).trim()
            if (body.isEmpty()) continue
            try {
                when {
                    Regex("(?:__UNIVERSAL_DATA_FOR_REHYDRATION__|SIGI_STATE)").containsMatchIn(attrs) -> walk(JSONObject(body), 0)
                    attrs.contains("RENDER_DATA") -> walk(JSONObject(URLDecoder.decode(body, "UTF-8")), 0)
                    body.contains("_ROUTER_DATA") -> {
                        val start = body.indexOf('{', body.indexOf("_ROUTER_DATA"))
                        if (start >= 0) walk(JSONObject(body.substring(start).trimEnd(';')), 0)
                    }
                    attrs.contains("application/json") && (body.contains("browser_native_") || body.contains("playable_url")) -> walk(JSONObject(body), 0)
                }
            } catch (_: Exception) { /* An unrelated page script must not break other sources. */ }
        }
        // Facebook commonly wraps its stream fields inside inline JS rather than an entire JSON script.
        for (key in listOf("browser_native_hd_url", "playable_url_quality_hd", "browser_native_sd_url", "playable_url")) {
            val pattern = Regex("\\\"$key\\\"\\s*:\\s*(\\\"(?:\\\\.|[^\\\"\\\\])*\\\")")
            for (match in pattern.findAll(html).take(12)) try {
                val url = JSONObject("{\"value\":" + match.groupValues[1] + "}").getString("value")
                add(url, if (key.contains("hd")) "HD" else "SD", "play")
            } catch (_: Exception) { }
        }
        cursor = 0
        var metaCount = 0
        while (cursor < html.length && metaCount++ < 500) {
            val start = lowerHtml.indexOf("<meta", cursor)
            if (start < 0) break
            val end = lowerHtml.indexOf('>', start + 5)
            if (end < 0) break
            cursor = end + 1
            if (end - start > 20000) continue
            val attributes = Regex("([\\w:-]+)\\s*=\\s*([\\\"'])(.*?)\\2", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
                .findAll(html.substring(start, end + 1)).associate { it.groupValues[1].lowercase() to it.groupValues[3] }
            val name = attributes["property"] ?: attributes["name"] ?: ""
            val content = attributes["content"] ?: continue
            if (name in listOf("og:video", "og:video:url", "og:video:secure_url")) add(content, "Nguồn trang", "metadata")
            if (name == "og:title" && title == "Video $label") title = decoded(content).take(300)
        }
        return mapOf("page" to page, "platform" to label, "title" to title,
            "choices" to sources.values.sortedBy { if (it["source"] == "download") 1 else 0 },
            "status" to if (sources.isEmpty()) "no_public_source" else "resolved")
    }
}
