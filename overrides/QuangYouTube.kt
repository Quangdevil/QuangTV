package app.tvviewer.player

import android.app.Activity
import android.app.AlertDialog
import android.content.ContentValues
import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.webkit.WebSettings
import android.widget.Toast
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.MediaFormat as NPFormat
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Public YouTube extraction + Android MP4 muxing. No account cookies or extraction server. */
object QuangYouTube {
    data class Choice(val title: String, val video: String, val audio: String?, val quality: String)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cancelled = AtomicBoolean(false)
    @Volatile var running = false; private set
    @Volatile var status = ""; private set
    fun cancel() { cancelled.set(true) }
    private fun prefs(c: Context) = c.getSharedPreferences("quangtv_browser", Context.MODE_PRIVATE)
    fun completed(c: Context): List<Uri> = prefs(c).getStringSet("local_videos", emptySet())!!.map { Uri.parse(it) }
    private fun canonical(url: String): String {
        val uri = Uri.parse(url); val host = uri.host?.lowercase() ?: ""
        val id = when {
            host == "youtu.be" -> uri.pathSegments.firstOrNull()
            host == "youtube.com" || host.endsWith(".youtube.com") -> uri.getQueryParameter("v") ?: uri.pathSegments.takeIf { it.firstOrNull() in listOf("shorts", "embed", "live") }?.getOrNull(1)
            else -> null
        }
        require(id != null && id.matches(Regex("[A-Za-z0-9_-]{11}"))) { "Mở một video YouTube trước khi tải" }
        return "https://www.youtube.com/watch?v=$id"
    }
    fun extract(c: Context, url: String, done: (List<Choice>?, String?) -> Unit) {
        val page = try { canonical(url) } catch (e: Exception) { done(null, e.message); return }
        val ua = WebSettings.getDefaultUserAgent(c).replace("; wv", "").replace(" Version/4.0", "")
        worker.execute {
            try {
                QuangProxy.ensure(c)
                NewPipe.init(object : Downloader() {
                    override fun execute(request: Request): Response {
                        val conn = URL(request.url()).openConnection() as HttpURLConnection
                        conn.connectTimeout = 12000; conn.readTimeout = 12000; conn.requestMethod = request.httpMethod()
                        conn.setRequestProperty("User-Agent", ua); conn.setRequestProperty("Accept-Encoding", "identity")
                        for ((name, values) in request.headers()) conn.setRequestProperty(name, values.joinToString(", "))
                        try {
                            request.dataToSend()?.let { conn.doOutput = true; conn.setFixedLengthStreamingMode(it.size); conn.outputStream.use { out -> out.write(it) } }
                            val code = conn.responseCode
                            val input = if (code >= 400) conn.errorStream else conn.inputStream
                            val body = input?.bufferedReader()?.use { reader ->
                                val b = StringBuilder(); val buffer = CharArray(8192); var n = reader.read(buffer)
                                while (n >= 0) { if (b.length + n > 16 * 1024 * 1024) throw java.io.IOException("Response too large"); b.append(buffer, 0, n); n = reader.read(buffer) }; b.toString()
                            } ?: ""
                            return Response(code, conn.responseMessage ?: "", conn.headerFields, body, conn.url.toString())
                        } finally { conn.disconnect() }
                    }
                })
                val info = StreamInfo.getInfo(ServiceList.YouTube, page)
                require(info.ageLimit == 0) { "Chỉ hỗ trợ video công khai không giới hạn độ tuổi" }
                val audio = info.audioStreams.firstOrNull { it.isUrl && it.format == NPFormat.M4A && it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP }?.content
                val result = info.videoStreams.filter { it.isUrl && !it.isVideoOnly && it.format == NPFormat.MPEG_4 && it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP }.map { Choice(info.name, it.content, null, it.resolution) }.toMutableList()
                if (audio != null) result.addAll(info.videoOnlyStreams.filter { it.isUrl && it.format == NPFormat.MPEG_4 && it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP && it.codec?.startsWith("avc") == true }.map { Choice(info.name, it.content, audio, it.resolution) })
                val choices = result.distinctBy { it.quality }.sortedByDescending { Regex("[0-9]+").find(it.quality)?.value?.toIntOrNull() ?: 0 }
                if (choices.isEmpty()) throw IllegalStateException("Không có nguồn MP4/AAC tương thích để tải")
                main.post { done(choices, null) }
            } catch (_: Exception) { main.post { done(null, "Chưa lấy được nguồn YouTube. Video có thể bị hạn chế, yêu cầu xác minh hoặc bộ trích xuất cần cập nhật.") } }
        }
    }
    fun showChoices(activity: Activity, url: String) {
        val wait = AlertDialog.Builder(activity).setMessage("Đang lấy chất lượng video YouTube…").setNegativeButton("Ẩn", null).show()
        extract(activity.applicationContext, url) { choices, error ->
            if (activity.isFinishing || activity.isDestroyed) return@extract
            wait.dismiss()
            if (choices == null) { Toast.makeText(activity, error, Toast.LENGTH_LONG).show(); return@extract }
            AlertDialog.Builder(activity).setTitle("Chất lượng tải MP4").setItems(choices.map { "${it.quality} · Có âm thanh" }.toTypedArray()) { _, index -> start(activity.applicationContext, choices[index]) }.setNegativeButton("Hủy", null).show()
        }
    }
    @Synchronized fun start(c: Context, choice: Choice) {
        if (running) { Toast.makeText(c, "Đang xử lý một video. Xem trong Đã tải.", Toast.LENGTH_LONG).show(); return }
        if (Build.VERSION.SDK_INT < 29) { Toast.makeText(c, "Tải và ghép YouTube cần Android 10 trở lên", Toast.LENGTH_LONG).show(); return }
        running = true; cancelled.set(false); status = "Đang chuẩn bị ${choice.quality}"
        Toast.makeText(c, "Đang tải YouTube. Giữ QuangTV mở; xem tiến trình trong Đã tải.", Toast.LENGTH_LONG).show()
        worker.execute {
            val file = File.createTempFile("quangtube-", ".mp4", c.cacheDir)
            val sources = ArrayList<MediaExtractor>(); var muxer: MediaMuxer? = null; var started = false; var saved: Uri? = null
            try {
                QuangProxy.ensure(c)
                val headers = mapOf("User-Agent" to "Mozilla/5.0", "Referer" to "https://www.youtube.com/")
                val tracks = ArrayList<Map<Int, Int>>(); var duration = 1L; var capacity = 1024 * 1024
                muxer = MediaMuxer(file.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                for ((index, url) in listOfNotNull(choice.video, choice.audio).withIndex()) {
                    val extractor = MediaExtractor(); sources.add(extractor)
                    extractor.setDataSource(QuangProxy.downloadUrl(c, url), headers)
                    val mapping = LinkedHashMap<Int, Int>()
                    for (track in 0 until extractor.trackCount) {
                        val format = extractor.getTrackFormat(track); val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                        val wanted = if (choice.audio == null) mime in listOf("video/avc", "audio/mp4a-latm") else if (index == 0) mime == "video/avc" else mime == "audio/mp4a-latm"
                        if (wanted) { extractor.selectTrack(track); mapping[track] = muxer.addTrack(format); if (format.containsKey(MediaFormat.KEY_DURATION)) duration = maxOf(duration, format.getLong(MediaFormat.KEY_DURATION)); if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) capacity = maxOf(capacity, format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)) }
                    }
                    check(mapping.isNotEmpty()) { "Unsupported track" }; tracks.add(mapping)
                }
                muxer.start(); started = true
                val buffer = ByteBuffer.allocateDirect(capacity.coerceAtMost(16 * 1024 * 1024)); val info = MediaCodec.BufferInfo()
                while (true) {
                    check(!cancelled.get()) { "Cancelled" }
                    val source = sources.indices.filter { sources[it].sampleTime >= 0 }.minByOrNull { sources[it].sampleTime } ?: break
                    val extractor = sources[source]; buffer.clear(); val size = extractor.readSampleData(buffer, 0); if (size < 0) break
                    check(extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_ENCRYPTED == 0) { "Encrypted media" }
                    info.set(0, size, extractor.sampleTime, extractor.sampleFlags)
                    muxer.writeSampleData(tracks[source].getValue(extractor.sampleTrackIndex), buffer, info)
                    status = "${choice.quality} · Đang tải/ghép ${((extractor.sampleTime * 100) / duration).coerceIn(0, 99)}% · ${"%.1f".format(file.length() / 1000000.0)} MB"
                    extractor.advance()
                }
                muxer.stop(); started = false; muxer.release(); muxer = null
                check(!cancelled.get())
                val name = choice.title.replace(Regex("[^\\p{L}\\p{N} _.-]"), "_").take(90) + "-${System.currentTimeMillis()}.mp4"
                val values = ContentValues().apply { put(MediaStore.MediaColumns.DISPLAY_NAME, name); put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4"); put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/QuangTV"); put(MediaStore.MediaColumns.IS_PENDING, 1) }
                saved = c.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: error("Storage unavailable")
                c.contentResolver.openOutputStream(saved)!!.use { out -> file.inputStream().use { input -> val b = ByteArray(65536); var n = input.read(b); while (n >= 0) { check(!cancelled.get()); out.write(b, 0, n); n = input.read(b) } } }
                c.contentResolver.update(saved, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
                val completed = prefs(c).getStringSet("local_videos", emptySet())!!.toMutableSet(); completed.add(saved.toString()); prefs(c).edit().putStringSet("local_videos", completed).apply()
                status = "Hoàn tất ${choice.quality} · ${"%.1f".format(file.length() / 1000000.0)} MB"
            } catch (_: Exception) { saved?.let { c.contentResolver.delete(it, null, null) }; status = if (cancelled.get()) "Đã hủy YouTube" else "Tải YouTube chưa hoàn tất. Kiểm tra nguồn, mạng và dung lượng trống." }
            finally { sources.forEach { it.release() }; if (started) try { muxer?.stop() } catch (_: Exception) {}; muxer?.release(); file.delete(); running = false }
        }
    }
}
