package app.tvviewer.player

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.OpenableColumns

/** App-owned downloads only: no broad storage permission or scanning other apps. */
object QuangDownloads {
    data class Entry(val key: String, val name: String, val uri: Uri?, val bytes: Long,
        val total: Long, val state: Int, val id: Long? = null) {
        val complete get() = state == DownloadManager.STATUS_SUCCESSFUL
        val active get() = state in listOf(DownloadManager.STATUS_PENDING, DownloadManager.STATUS_RUNNING, DownloadManager.STATUS_PAUSED)
        val detail: String get() {
            if(key=="youtube:active")return QuangYouTube.status
            val label = when(state) { DownloadManager.STATUS_SUCCESSFUL -> "Hoàn tất"; DownloadManager.STATUS_FAILED -> "Lỗi tải"; DownloadManager.STATUS_PAUSED -> "Chờ mạng"; else -> "Đang tải" }
            val size = "%.1f MB".format(bytes.coerceAtLeast(0) / 1000000.0)
            return if(active && total > 0) "$label · $size / ${"%.1f MB".format(total / 1000000.0)} · ${(bytes.coerceAtLeast(0) * 100 / total).coerceIn(0,100)}%" else "$label · $size"
        }
    }
    fun prefs(c: Context) = c.getSharedPreferences("quangtv_browser", Context.MODE_PRIVATE)
    private fun manager(c: Context) = c.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    @Synchronized fun enqueue(c: Context, url: String, headers: Map<String,String>, filename: String): Long {
        // The service keeps the authenticated loopback relay alive when the UI closes.
        QuangDownloadService.keepAlive(c)
        val request = DownloadManager.Request(Uri.parse(url)).setTitle(filename)
            .setMimeType(if(filename.endsWith(".webm")) "video/webm" else "video/mp4")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "QuangTV/$filename")
        headers.forEach { (key,value) -> request.addRequestHeader(key,value) }
        val id=manager(c).enqueue(request)
        val ids=prefs(c).getStringSet("downloads",emptySet())!!.toMutableSet();ids.add(id.toString())
        prefs(c).edit().putStringSet("downloads",ids).apply()
        return id
    }
    fun entries(c: Context, activeOnly: Boolean=false): List<Entry> {
        val result=ArrayList<Entry>()
        val ids=prefs(c).getStringSet("downloads",emptySet())!!.toSet()
        for(raw in ids.sortedByDescending { it.toLongOrNull() ?: 0 }) {
            val id=raw.toLongOrNull() ?: continue
            try { manager(c).query(DownloadManager.Query().setFilterById(id))?.use { row ->
                if(row.moveToFirst()) {
                    val state=row.getInt(row.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                    if(!activeOnly || state in listOf(DownloadManager.STATUS_PENDING,DownloadManager.STATUS_RUNNING,DownloadManager.STATUS_PAUSED))result.add(Entry("download:$id",row.getString(row.getColumnIndexOrThrow(DownloadManager.COLUMN_TITLE)) ?: "Video",
                        if(state==DownloadManager.STATUS_SUCCESSFUL) manager(c).getUriForDownloadedFile(id) else null,
                        row.getLong(row.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                        row.getLong(row.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)),state,id))
                }
            } } catch (_: Exception) { }
        }
        for(uri in if(activeOnly) emptyList() else QuangYouTube.completed(c).reversed()) {
            try { c.contentResolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE),null,null,null)?.use { row ->
                if(row.moveToFirst()) result.add(Entry("youtube:$uri",row.getString(0) ?: "YouTube.mp4",uri,row.getLong(1),row.getLong(1),DownloadManager.STATUS_SUCCESSFUL))
            } } catch (_: Exception) { }
        }
        if(QuangYouTube.running) result.add(0,Entry("youtube:active","Video YouTube",null,0,0,DownloadManager.STATUS_RUNNING))
        return result
    }
    @Synchronized fun rememberYouTube(c: Context, uri: Uri) {
        val saved=prefs(c).getStringSet("local_videos",emptySet())!!.toMutableSet();saved.add(uri.toString())
        prefs(c).edit().putStringSet("local_videos",saved).apply()
    }
    @Synchronized fun remove(c: Context, entry: Entry): Boolean {
        if(entry.key=="youtube:active") { QuangYouTube.cancel();return true }
        return try {
            if(entry.id!=null) {
                manager(c).remove(entry.id)
                val ids=prefs(c).getStringSet("downloads",emptySet())!!.toMutableSet();ids.remove(entry.id.toString())
                prefs(c).edit().putStringSet("downloads",ids).apply()
            } else if(entry.uri!=null) {
                c.contentResolver.delete(entry.uri,null,null)
                val saved=prefs(c).getStringSet("local_videos",emptySet())!!.toMutableSet();saved.remove(entry.uri.toString())
                prefs(c).edit().putStringSet("local_videos",saved).apply()
            }
            true
        } catch (_: Exception) { false }
    }
    fun exists(c: Context, uri: Uri?): Boolean = if(uri==null) false else try {
        c.contentResolver.openFileDescriptor(uri,"r")?.use { true } ?: false
    } catch (_: Exception) { false }
}
