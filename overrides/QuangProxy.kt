package app.tvviewer.player

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import java.net.*
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

/** Private device configuration; no credentials in Dart preferences, logs or APK defaults. */
object QuangProxy {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var relay: QuangProxyRelay? = null
    private var applied: String? = null
    var onChanged: ((Map<String, Any>) -> Unit)? = null
    private val originalSelector = ProxySelector.getDefault()
    private fun prefs(c: Context) = c.getSharedPreferences("quangtv_proxy", Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("quangtv_proxy_v1", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("quangtv_proxy_v1", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    @Synchronized private fun config(c: Context): JSONObject {
        val saved = prefs(c).getString("encrypted", null) ?: return JSONObject().put("enabled", false).put("type", "http")
        val parts = saved.split(':')
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
        return JSONObject(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
    }
    @Synchronized fun state(c: Context): Map<String, Any> {
        val value = config(c)
        ensure(c)
        return mapOf("enabled" to value.optBoolean("enabled"), "host" to value.optString("host"), "port" to value.optInt("port", 0),
            "type" to value.optString("type", "http"), "user" to value.optString("user"), "hasPassword" to value.optString("password").isNotEmpty(), "localPort" to (relay?.port() ?: 0))
    }
    @Synchronized fun ensure(c: Context) {
        val value = try { config(c) } catch (e: Exception) {
            if (prefs(c).getBoolean("enabled", false)) {
                ProxySelector.setDefault(object : ProxySelector() {
                    override fun select(uri: URI) = listOf(Proxy(Proxy.Type.HTTP, InetSocketAddress("127.0.0.1", 9)))
                    override fun connectFailed(uri: URI?, sa: SocketAddress?, ioe: java.io.IOException?) {}
                })
            }
            throw e
        }
        val stamp = value.toString()
        if (stamp == applied) return
        relay?.close(); relay = null; applied = null
        if (value.optBoolean("enabled")) {
            val next = QuangProxyRelay(value.getString("type"), value.getString("host"), value.getInt("port"), value.optString("user"), value.optString("password"))
            relay = next
            ProxySelector.setDefault(object : ProxySelector() {
                override fun select(uri: URI): List<Proxy> {
                    val local = uri.scheme !in listOf("http", "https") || uri.host in listOf("127.0.0.1", "localhost", "::1", "[::1]")
                    return if (local) listOf(Proxy.NO_PROXY) else listOf(next.javaProxy())
                }
                override fun connectFailed(uri: URI?, sa: SocketAddress?, ioe: java.io.IOException?) { /* Do not fall back to the direct connection. */ }
            })
        } else {
            ProxySelector.setDefault(originalSelector)
        }
        applied = stamp
    }
    @Synchronized fun save(c: Context, args: Map<*, *>) {
        val previous = try { config(c) } catch (_: Exception) { JSONObject() }
        val enabled = args["enabled"] == true
        val host = (args["host"] as? String ?: "").trim()
        val port = (args["port"] as? Number)?.toInt() ?: 0
        val type = args["type"] as? String ?: "http"
        val user = (args["user"] as? String ?: "").trim()
        var password = args["password"] as? String ?: ""
        if (password.isEmpty() && user.isNotEmpty() && host == previous.optString("host") && port == previous.optInt("port") && user == previous.optString("user")) password = previous.optString("password")
        if (enabled && (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE) || host.isEmpty() || host.contains('/') || host.contains(':') || host.any { it.isWhitespace() } || port !in 1..65535 || type !in listOf("http", "https", "socks5"))) throw IllegalArgumentException("Cấu hình không hợp lệ hoặc WebView cần cập nhật")
        val value = JSONObject().put("enabled", enabled).put("host", host).put("port", port).put("type", type).put("user", user).put("password", password)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key())
        val body = cipher.doFinal(value.toString().toByteArray(Charsets.UTF_8))
        check(prefs(c).edit().putString("encrypted", Base64.encodeToString(cipher.iv, Base64.NO_WRAP)+":"+Base64.encodeToString(body, Base64.NO_WRAP)).putBoolean("enabled", enabled).commit())
        ensure(c)
        main.post { onChanged?.invoke(state(c)) }
    }
    fun toggle(c: Context, enabled: Boolean) {
        val v = config(c)
        save(c, mapOf("enabled" to enabled, "type" to v.optString("type", "http"), "host" to v.optString("host"), "port" to v.optInt("port"), "user" to v.optString("user"), "password" to v.optString("password")))
    }
    fun applyWeb(c: Context, done: () -> Unit, failed: () -> Unit) {
        try {
            ensure(c)
            if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) { if (prefs(c).getBoolean("enabled", false)) failed() else done(); return }
            val active = relay
            val executor = java.util.concurrent.Executor { main.post(it) }
            if (active == null) ProxyController.getInstance().clearProxyOverride(executor) { done() }
            else ProxyController.getInstance().setProxyOverride(ProxyConfig.Builder().addProxyRule("http://127.0.0.1:${active.port()}").removeImplicitRules().build(), executor) { done() }
        } catch (_: Exception) { failed() }
    }
    @Synchronized fun downloadUrl(c: Context, url: String): String { ensure(c); return relay?.downloadUrl(url) ?: url }
    fun checkNetwork(c: Context, raw: String, viaProxy: Boolean, done: (Map<String, Any>) -> Unit) {
        worker.execute {
            val start = System.nanoTime()
            val result = try {
                val uri = URI(raw)
                require(uri.scheme in listOf("http", "https") && uri.host != null && uri.userInfo == null) { "URL không hợp lệ" }
                val proxy = if (viaProxy) { ensure(c); relay?.javaProxy() ?: throw IllegalStateException("Bật VPN ứng dụng ở màn hình IPTV trước khi kiểm tra qua proxy") } else Proxy.NO_PROXY
                val connection = URL(raw).openConnection(proxy) as HttpURLConnection
                connection.connectTimeout = 8000; connection.readTimeout = 8000; connection.instanceFollowRedirects = false
                connection.setRequestProperty("Range", "bytes=0-0")
                connection.setRequestProperty("User-Agent", "Mozilla/5.0 QuangTV-NetworkCheck")
                try {
                    val code = connection.responseCode
                    mapOf<String, Any>("ok" to (code in 200..399), "stage" to "HTTP", "code" to code,
                        "detail" to when { code == 403 -> "Đã kết nối, nhưng trang từ chối HTTP 403"; code == 429 -> "Trang giới hạn yêu cầu HTTP 429"; else -> "HTTP $code" })
                } finally { connection.disconnect() }
            } catch (e: Exception) {
                val stage = when(e) { is UnknownHostException -> "DNS"; is javax.net.ssl.SSLException -> "TLS"; is SocketTimeoutException -> "TIMEOUT"; is ConnectException -> "TCP"; else -> "NETWORK" }
                val detail = when(stage) { "DNS" -> "Không phân giải được DNS"; "TLS" -> "Lỗi chứng chỉ hoặc bắt tay TLS"; "TIMEOUT" -> "Kết nối hết thời gian chờ"; "TCP" -> "Không kết nối được máy chủ/cổng"; else -> if(e is IllegalArgumentException || e is IllegalStateException) e.message ?: "Lỗi kết nối" else "Lỗi đường truyền" }
                mapOf<String, Any>("ok" to false, "stage" to stage, "detail" to detail)
            }.toMutableMap()
            result["ms"] = (System.nanoTime()-start)/1000000
            main.post { done(result) }
        }
    }
    fun test(c: Context, done: (Map<String, Any>?) -> Unit) {
        worker.execute {
            val result = try {
                ensure(c)
                val active = relay ?: throw IllegalStateException("Proxy đang tắt")
                val start = System.nanoTime()
                val connection = URL("https://api.ipify.org?format=json").openConnection(active.javaProxy()) as HttpURLConnection
                connection.connectTimeout = 15000; connection.readTimeout = 15000
                try {
                    if (connection.responseCode != 200) throw java.io.IOException()
                    val ip = connection.inputStream.bufferedReader().use { JSONObject(it.readText()).getString("ip") }
                    mapOf<String, Any>("ip" to ip, "ms" to ((System.nanoTime()-start)/1000000))
                } finally { connection.disconnect() }
            } catch (_: Exception) { null }
            main.post { done(result) }
        }
    }
}
