package app.tvviewer.player

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors

/** One application-scoped download; screens and installer dialogs do not own it. */
object QuangUpdateManager {
    private val executor = Executors.newSingleThreadExecutor()
    private var active = false
    private var restored = false
    private fun prefs(c: Context) = c.getSharedPreferences("quangtv_ota", Context.MODE_PRIVATE)
    private fun folder(c: Context) = File(c.filesDir, "updates").apply { mkdirs() }
    private fun partial(c: Context) = File(folder(c), "quangtv-update.apk.part")
    private fun apk(c: Context) = File(folder(c), "quangtv-update.apk")

    @Synchronized fun status(context: Context): Map<String, Any> {
        val c = context.applicationContext
        val p = prefs(c)
        if (!restored) {
            restored = true
            if (p.getString("phase", "") == "downloading") {
                p.edit().putString("phase", "paused").putLong("downloaded", partial(c).length()).apply()
            }
        }
        return mapOf(
            "phase" to (p.getString("phase", "idle") ?: "idle"),
            "url" to (p.getString("url", "") ?: ""),
            "downloaded" to p.getLong("downloaded", 0),
            "total" to p.getLong("total", 0),
            "message" to (p.getString("message", "") ?: "")
        )
    }

    private fun allowed(c: Context, url: String): Boolean {
        val uri = Uri.parse(url)
        if (uri.scheme == "https" && uri.host == "github.com" &&
            uri.path?.startsWith("/Quangdevil/QuangTV/releases/download/") == true) {
            val parts = uri.pathSegments
            if (parts.size != 6) return false
            val preview = c.packageName == "com.quangduren.quangtv.autopreview2"
            val tag = parts[4]
            val asset = parts[5]
            return if (preview) tag.matches(Regex("auto-preview2-build[0-9]+")) &&
                asset.matches(Regex("QuangTV-Auto-Preview2-build[0-9]+-arm64\\.apk"))
            else tag.startsWith("quangtv-v") && asset.startsWith("QuangTV-v") && asset.endsWith("-arm64.apk")
        }
        // Deterministic emulator fixture is never permitted in a release APK.
        return c.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
            uri.scheme == "http" && uri.host == "10.0.2.2" && uri.port == 8765 &&
            uri.path == "/ota-fixture.apk"
    }

    @Synchronized fun start(context: Context, url: String, size: Long, digest: String): Map<String, Any> {
        val c = context.applicationContext
        status(c)
        require(allowed(c, url)) { "URL cập nhật không hợp lệ" }
        val p = prefs(c)
        if (active) return status(c)
        if (p.getString("url", "") == url && p.getString("phase", "") == "ready" && apk(c).isFile) {
            return status(c)
        }
        if (p.getString("url", "") != url) {
            partial(c).delete()
            apk(c).delete()
        }
        val effectiveDigest = if (digest.isNotEmpty()) digest else if (p.getString("url", "") == url) p.getString("digest", "") ?: "" else ""
        val effectiveSize = if (size > 0) size else if (p.getString("url", "") == url) p.getLong("total", 0) else 0
        p.edit().putString("url", url).putString("digest", effectiveDigest)
            .putString("phase", "downloading").putString("message", "")
            .putLong("total", effectiveSize).putLong("downloaded", partial(c).length()).apply()
        active = true
        executor.execute { download(c, url, effectiveSize, effectiveDigest) }
        return status(c)
    }

    private fun download(c: Context, url: String, expected: Long, digest: String) {
        var connection: HttpURLConnection? = null
        try {
            var offset = partial(c).length()
            if (expected > 0 && offset == expected) {
                finish(c, offset, expected, digest)
                return
            }
            if (expected > 0 && offset > expected) {
                partial(c).delete()
                offset = 0
            }
            var current = URL(url)
            for (redirect in 0..6) {
                val next = current.openConnection() as HttpURLConnection
                connection = next
                next.connectTimeout = 20000
                next.readTimeout = 30000
                next.instanceFollowRedirects = false
                if (offset > 0) next.setRequestProperty("Range", "bytes=$offset-")
                next.connect()
                if (next.responseCode !in 300..399) break
                check(redirect < 6) { "Quá nhiều chuyển hướng" }
                val target = URL(current, next.getHeaderField("Location") ?: error("Thiếu địa chỉ tải"))
                check(target.protocol == "https") { "Chuyển hướng không an toàn" }
                next.disconnect()
                current = target
            }
            val conn = connection ?: error("Không kết nối được")
            check(conn.responseCode == 200 || conn.responseCode == 206) { "HTTP ${conn.responseCode}" }
            if (conn.responseCode == 206) {
                val range = conn.getHeaderField("Content-Range") ?: error("Thiếu Content-Range")
                check(range.startsWith("bytes $offset-")) { "Vị trí tải tiếp không khớp" }
            } else if (offset > 0) {
                offset = 0 // Server does not support Range; safely replace instead of appending.
            }
            val length = conn.contentLengthLong
            val total = if (expected > 0) expected else if (length > 0) offset + length else 0L
            var downloaded = offset
            var lastReport = 0L
            RandomAccessFile(partial(c), "rw").use { file ->
                if (offset == 0L) file.setLength(0)
                file.seek(offset)
                conn.inputStream.use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        file.write(buffer, 0, count)
                        downloaded += count
                        val now = System.currentTimeMillis()
                        if (now - lastReport >= 200) {
                            prefs(c).edit().putLong("downloaded", downloaded).putLong("total", total).apply()
                            lastReport = now
                        }
                    }
                }
                file.fd.sync()
            }
            finish(c, downloaded, total, digest)
        } catch (e: Exception) {
            synchronized(this) {
                active = false
                prefs(c).edit().putString("phase", "error").putString("message", e.message ?: "Lỗi tải APK")
                    .putLong("downloaded", partial(c).length()).apply()
            }
        } finally {
            connection?.disconnect()
        }
    }

    private fun finish(c: Context, downloaded: Long, total: Long, digest: String) {
        check(downloaded >= 1000000 && (total == 0L || downloaded == total)) { "APK chưa tải đủ" }
        if (digest.startsWith("sha256:")) {
            val sha = MessageDigest.getInstance("SHA-256")
            partial(c).inputStream().use { input ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    sha.update(buffer, 0, count)
                }
            }
            val actual = sha.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
            if (!actual.equals(digest.removePrefix("sha256:"), ignoreCase = true)) {
                partial(c).delete()
                error("APK sai mã kiểm tra. Vui lòng tải lại")
            }
        }
        apk(c).delete()
        // Reject a wrong package, signer, or downgrade before opening Android's
        // installer. The emulator's synthetic byte fixture is the only bypass.
        val fixture = c.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
            prefs(c).getString("url", "") == "http://10.0.2.2:8765/ota-fixture.apk"
        if (!fixture) verifyArchive(c, partial(c))
        check(partial(c).renameTo(apk(c))) { "Không lưu được APK" }
        synchronized(this) {
            active = false
            prefs(c).edit().putString("phase", "ready").putString("message", "")
                .putLong("downloaded", downloaded).putLong("total", downloaded).apply()
        }
    }
    @Suppress("DEPRECATION")
    private fun verifyArchive(c: Context, file: File) {
        val pm = c.packageManager
        val candidate = pm.getPackageArchiveInfo(file.absolutePath, PackageManager.GET_SIGNATURES)
            ?: error("Tệp cập nhật không phải APK hợp lệ")
        check(candidate.packageName == c.packageName) { "APK không đúng ứng dụng đang dùng" }
        val installed = pm.getPackageInfo(c.packageName, PackageManager.GET_SIGNATURES)
        val oldSigners = installed.signatures?.toSet() ?: emptySet()
        val newSigners = candidate.signatures?.toSet() ?: emptySet()
        check(oldSigners.isNotEmpty() && oldSigners == newSigners) { "APK không cùng chữ ký cài đặt" }
        val oldVersion = if (android.os.Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        val newVersion = if (android.os.Build.VERSION.SDK_INT >= 28) candidate.longVersionCode else candidate.versionCode.toLong()
        check(newVersion > oldVersion) { "Bản cập nhật không mới hơn bản đang dùng" }
    }
    @Synchronized fun install(context: Context) {
        val c = context.applicationContext
        check(status(c)["phase"] == "ready" && apk(c).isFile) { "APK chưa sẵn sàng" }
        val uri = FileProvider.getUriForFile(c, "${c.packageName}.updateprovider", apk(c))
        c.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        })
        // Keep ready state and APK if Android's installer is dismissed or permission is requested.
    }
}
