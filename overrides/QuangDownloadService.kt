package app.tvviewer.player

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.*

/** Started by a download tap, independent of browser/activity lifecycle. */
class QuangDownloadService : Service() {
    companion object {
        @Volatile var running=false; private set
        private const val CHANNEL="quangtv_downloads"
        private const val NOTICE=3104
        fun keepAlive(context: Context) {
            if(context is Activity && Build.VERSION.SDK_INT>=33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED && !QuangDownloads.prefs(context).getBoolean("download_notification_asked",false)) {
                QuangDownloads.prefs(context).edit().putBoolean("download_notification_asked",true).apply()
                context.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),3104)
            }
            if(running)return
            val intent=Intent(context.applicationContext,QuangDownloadService::class.java)
            if(Build.VERSION.SDK_INT>=26)context.applicationContext.startForegroundService(intent) else context.applicationContext.startService(intent)
        }
    }
    private val handler=Handler(Looper.getMainLooper())
    private var began=0L
    private var wake:PowerManager.WakeLock?=null
    private fun notification(text: String, ongoing: Boolean): Notification {
        val open=PendingIntent.getActivity(this,3104,Intent(this,QuangDownloadsActivity::class.java).putExtra("folder",if(ongoing) "active" else "videos").addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder=if(Build.VERSION.SDK_INT>=26)Notification.Builder(this,CHANNEL) else Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.stat_sys_download).setContentTitle("QuangTV · Tải xuống")
            .setContentText(text).setContentIntent(open).setOngoing(ongoing).setOnlyAlertOnce(true).setAutoCancel(!ongoing).build()
    }
    override fun onCreate() {
        super.onCreate();running=true;began=SystemClock.elapsedRealtime()
        if(Build.VERSION.SDK_INT>=26)(getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(NotificationChannel(CHANNEL,"Tải video",NotificationManager.IMPORTANCE_LOW))
        val notice=notification("Đang chuẩn bị tải nền…",true)
        if(Build.VERSION.SDK_INT>=29)startForeground(NOTICE,notice,ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC) else startForeground(NOTICE,notice)
        wake=(getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"QuangTV:Downloads").apply { setReferenceCounted(false) }
        try { QuangProxy.ensure(this) } catch (_: Exception) { }
        QuangYouTube.resumePending(applicationContext)
        handler.post(poll)
    }
    private val poll=object:Runnable {
        override fun run() {
            // DownloadManager owns its network wake lock. Only the native mux
            // worker needs ours; don't hold the CPU while Android waits for Wi-Fi.
            if(QuangYouTube.running && wake?.isHeld==false)wake?.acquire(6*60*60*1000L)
            else if(!QuangYouTube.running && wake?.isHeld==true)wake?.release()
            val active=QuangDownloads.entries(this@QuangDownloadService,true).filter { it.active }
            if(active.isNotEmpty() || SystemClock.elapsedRealtime()-began<4000) {
                val text=if(QuangYouTube.running)QuangYouTube.status else if(active.isEmpty())"Đang chuẩn bị tải…" else "${active.size} video · ${active.first().detail}"
                (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(NOTICE,notification(text,true))
                handler.postDelayed(this,1500)
            } else {
                running=false
                (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(NOTICE,notification("Lượt tải đã kết thúc · Mở thư mục",false))
                if(Build.VERSION.SDK_INT>=24)stopForeground(STOP_FOREGROUND_DETACH) else stopForeground(false)
                stopSelf()
            }
        }
    }
    override fun onStartCommand(intent: Intent?,flags: Int,startId: Int):Int=START_STICKY
    override fun onBind(intent: Intent?):IBinder?=null
    override fun onTimeout(startId: Int,fgsType: Int) {
        running=false
        QuangYouTube.cancel()
        stopForeground(STOP_FOREGROUND_REMOVE);stopSelf()
    }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null);if(wake?.isHeld==true)wake?.release();running=false;super.onDestroy() }
}
