package app.tvviewer.player

import android.app.*
import android.content.*
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import android.os.*
import android.view.*
import android.widget.*
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import java.lang.ref.WeakReference
import kotlin.math.abs

/** Folder-style library, independent of the browser that started each task. */
class QuangDownloadsActivity : Activity() {
    companion object {
        private var current: WeakReference<QuangDownloadsActivity>?=null
        fun ready()=current?.get()!=null
        fun inspect():Map<String,Any> = current?.get()?.let { a ->
            val entries=QuangDownloads.entries(a)
            mapOf("folder" to a.section,"files" to entries.count { it.complete },"active" to entries.count { it.active },
                "service" to QuangDownloadService.running,"bytes" to entries.sumOf { it.bytes.coerceAtLeast(0) },
                "previewPlaying" to (a.video?.isPlaying ?: false),"previewPosition" to (a.video?.currentPosition ?: 0),
                "deleteShown" to a.fileRows.values.any { it.revealed },"deletedFileExists" to QuangDownloads.exists(a,a.lastDeleted),
                "names" to entries.filter { it.complete }.map { it.name })
        } ?: mapOf("closed" to true,"service" to QuangDownloadService.running)
        fun testAction(action:String) { current?.get()?.let { a -> when(action) {
            "videos" -> a.openFolder("videos")
            "active" -> a.openFolder("active")
            "openFirst" -> a.fileRows.values.firstOrNull()?.content?.performClick()
            "swipeFirst" -> a.fileRows.values.firstOrNull()?.testSwipe()
            "deleteRevealed" -> a.fileRows.values.firstOrNull { it.revealed }?.delete?.performClick()
            "closePreview" -> a.preview?.dismiss()
            "close" -> a.finish()
        } } }
        fun previewFirstThenClose(done:(Boolean)->Unit) {
            val a=current?.get() ?: run { done(false);return }
            a.openFolder("videos")
            val entry=QuangDownloads.entries(a).firstOrNull { it.complete } ?: run { a.finish();done(false);return }
            a.openVideo(entry)
            var checks=0
            val verify=object:Runnable { override fun run() {
                val passed=a.video?.let { it.isPlaying && it.currentPosition>=1000 }==true
                if(!passed && ++checks<80) { a.handler.postDelayed(this,250);return }
                a.preview?.dismiss();a.finish();done(passed)
            } }
            a.handler.postDelayed(verify,250)
        }
    }
    private val handler=Handler(Looper.getMainLooper())
    private lateinit var rows:LinearLayout
    private lateinit var path:Button
    private lateinit var videosFolder:Button
    private lateinit var activeFolder:Button
    private var section="root"
    private var keys:List<String> = emptyList()
    private val fileRows=LinkedHashMap<String,FileRow>()
    private var preview:Dialog?=null
    private var video:VideoView?=null
    private var resumeVideo=false
    private var lastDeleted:Uri?=null
    private fun dp(n:Int)=(n*resources.displayMetrics.density).toInt()
    private fun button(label:String,action:()->Unit)=Button(this).apply { text=label;isAllCaps=false;setOnClickListener { action() } }
    override fun onCreate(state:Bundle?) {
        setTheme(android.R.style.Theme_Material_NoActionBar)
        super.onCreate(state)
        val root=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL;setBackgroundColor(Color.rgb(11,17,26)) }
        WindowCompat.setDecorFitsSystemWindows(window,false)
        ViewCompat.setOnApplyWindowInsetsListener(root) { view,insets ->
            val bars=insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            view.setPadding(bars.left,bars.top,bars.right,bars.bottom);insets
        }
        val bar=LinearLayout(this).apply { gravity=Gravity.CENTER_VERTICAL;setBackgroundColor(Color.rgb(17,30,41)) }
        bar.addView(button("‹") { onBackPressed() },LinearLayout.LayoutParams(dp(52),dp(52)))
        bar.addView(TextView(this).apply { text="Đã tải";textSize=22f;setTextColor(Color.rgb(237,245,245)) },LinearLayout.LayoutParams(0,dp(48),1f))
        bar.addView(button("Tệp Android") { try { startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS)) } catch (_:Exception) { Toast.makeText(this,"Không mở được ứng dụng Tệp",Toast.LENGTH_SHORT).show() } })
        root.addView(bar)
        path=button("📁 Downloads / QuangTV") { openFolder("root") };root.addView(path)
        rows=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL;setPadding(dp(8),dp(8),dp(8),dp(8)) }
        root.addView(ScrollView(this).apply { addView(rows) },LinearLayout.LayoutParams(-1,0,1f))
        videosFolder=button("") { openFolder("videos") };activeFolder=button("") { openFolder("active") }
        section=state?.getString("folder") ?: intent.getStringExtra("folder") ?: "root"
        setContentView(root);current=WeakReference(this);render()
        intent.getStringExtra("openKey")?.let { key -> handler.post { QuangDownloads.entries(this).firstOrNull{it.key==key && it.complete}?.let{openVideo(it)} } }
    }
    private fun openFolder(next:String) { section=next;keys=emptyList();rows.removeAllViews();fileRows.clear();render() }
    private val refresh=object:Runnable { override fun run() { if(!isFinishing){render();handler.postDelayed(this,1000)} } }
    private fun render() {
        val entries=QuangDownloads.entries(this)
        path.text="📁 Downloads / QuangTV"+when(section){"videos"->" / Video";"active"->" / Đang tải";else->""}
        if(section=="root") {
            videosFolder.text="📁 Video đã tải · ${entries.count { it.complete }}"
            activeFolder.text="📁 Đang tải / Lỗi · ${entries.count { !it.complete }}"
            if(keys!=listOf("root")) {
                rows.removeAllViews();fileRows.clear()
                (videosFolder.parent as? android.view.ViewGroup)?.removeView(videosFolder)
                (activeFolder.parent as? android.view.ViewGroup)?.removeView(activeFolder)
                rows.addView(videosFolder,LinearLayout.LayoutParams(-1,dp(72)));rows.addView(activeFolder,LinearLayout.LayoutParams(-1,dp(72)))
                rows.addView(TextView(this).apply { text="Mở thư mục để xem video. Gạt tệp sang trái để hiện nút Xóa.";setPadding(dp(12),dp(20),dp(12),dp(12)) })
                keys=listOf("root")
            }
            return
        }
        val selected=entries.filter { if(section=="videos")it.complete else !it.complete }
        val nextKeys=selected.map { it.key }
        if(nextKeys!=keys || rows.childCount==0) {
            rows.removeAllViews();fileRows.clear();keys=nextKeys
            for(entry in selected) {
                val row=FileRow(entry);fileRows[entry.key]=row;rows.addView(row,LinearLayout.LayoutParams(-1,-2).apply { bottomMargin=dp(6) })
            }
            if(selected.isEmpty())rows.addView(TextView(this).apply { text=if(section=="videos")"Chưa có video đã tải." else "Không có lượt tải đang chạy.";setPadding(dp(16),dp(24),dp(16),dp(24)) })
        } else selected.forEach { fileRows[it.key]?.update(it) }
    }
    private inner class FileRow(var entry:QuangDownloads.Entry):FrameLayout(this@QuangDownloadsActivity) {
        val delete=button(if(entry.active)"Hủy" else "Xóa") {
            val removed=entry.uri
            if(QuangDownloads.remove(this@QuangDownloadsActivity,entry)) {
                lastDeleted=removed;keys=emptyList();render()
            } else Toast.makeText(this@QuangDownloadsActivity,"Chưa xóa được tệp",Toast.LENGTH_SHORT).show()
        }
        val content=LinearLayout(this@QuangDownloadsActivity).apply { orientation=LinearLayout.HORIZONTAL;gravity=Gravity.CENTER_VERTICAL;minimumHeight=dp(86);setBackgroundColor(Color.rgb(17,30,41));setPadding(dp(12),dp(8),dp(12),dp(8));isClickable=true }
        private val name=TextView(this@QuangDownloadsActivity).apply { textSize=15f;setTextColor(Color.rgb(237,245,245));maxLines=2;ellipsize=android.text.TextUtils.TruncateAt.END }
        private val detail=TextView(this@QuangDownloadsActivity).apply { textSize=12f;setTextColor(Color.rgb(147,167,179));maxLines=2 }
        val revealed get()=content.translationX < -dp(30)
        init {
            delete.setBackgroundColor(Color.rgb(190,35,45));delete.setTextColor(Color.WHITE)
            addView(delete,FrameLayout.LayoutParams(dp(88),-1,Gravity.END))
            content.addView(TextView(this@QuangDownloadsActivity).apply { text=if(entry.complete)"▶" else "↓";textSize=25f;setTextColor(Color.rgb(42,103,192));gravity=Gravity.CENTER },LinearLayout.LayoutParams(dp(42),dp(56)))
            content.addView(LinearLayout(this@QuangDownloadsActivity).apply { orientation=LinearLayout.VERTICAL;gravity=Gravity.CENTER_VERTICAL;addView(name);addView(detail) },LinearLayout.LayoutParams(0,-2,1f))
            addView(content,FrameLayout.LayoutParams(-1,-2));update(entry)
            content.setOnClickListener { if(revealed)content.animate().translationX(0f).setDuration(120).start() else if(entry.complete)openVideo(entry) }
            var startX=0f;var startY=0f;var initial=0f;var horizontal=false
            val slop=ViewConfiguration.get(this@QuangDownloadsActivity).scaledTouchSlop
            content.setOnTouchListener { view,event ->
                when(event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> { startX=event.rawX;startY=event.rawY;initial=content.translationX;horizontal=false;content.animate().cancel() }
                    MotionEvent.ACTION_MOVE -> {
                        val dx=event.rawX-startX;val dy=event.rawY-startY
                        if(abs(dx)>slop && abs(dx)>abs(dy)){horizontal=true;parent?.requestDisallowInterceptTouchEvent(true)}
                        if(horizontal)content.translationX=(initial+dx).coerceIn(-dp(88).toFloat(),0f)
                    }
                    MotionEvent.ACTION_UP,MotionEvent.ACTION_CANCEL -> {
                        parent?.requestDisallowInterceptTouchEvent(false)
                        if(horizontal)content.animate().translationX(if(content.translationX < -dp(35)) -dp(88).toFloat() else 0f).setDuration(120).start()
                        else if(event.actionMasked==MotionEvent.ACTION_UP && abs(event.rawX-startX)<slop && abs(event.rawY-startY)<slop)view.performClick()
                    }
                }
                true
            }
        }
        fun update(value:QuangDownloads.Entry) { entry=value;name.text=value.name;detail.text=value.detail;delete.text=if(value.active)"Hủy" else "Xóa" }
        fun testSwipe() {
            val now=SystemClock.uptimeMillis();val x=content.width*.8f;val y=content.height*.5f
            for((action,delta,time) in listOf(Triple(MotionEvent.ACTION_DOWN,0f,0L),Triple(MotionEvent.ACTION_MOVE,dp(50).toFloat(),80L),Triple(MotionEvent.ACTION_MOVE,dp(110).toFloat(),160L),Triple(MotionEvent.ACTION_UP,dp(110).toFloat(),200L))) {
                val event=MotionEvent.obtain(now,now+time,action,x-delta,y,0);content.dispatchTouchEvent(event);event.recycle()
            }
        }
    }
    private fun openVideo(entry:QuangDownloads.Entry) {
        val uri=entry.uri ?: return
        if(!QuangDownloads.exists(this,uri)){Toast.makeText(this,"Tệp đã được chuyển hoặc xóa",Toast.LENGTH_SHORT).show();return}
        val dialog=Dialog(this,android.R.style.Theme_Material_NoActionBar_Fullscreen)
        val player=VideoView(this);video=player;preview=dialog
        val frame=FrameLayout(this).apply { setBackgroundColor(Color.BLACK);addView(player,FrameLayout.LayoutParams(-1,-1,Gravity.CENTER));addView(button("‹ Đã tải") { dialog.dismiss() }.apply { setTextColor(Color.WHITE);setBackgroundColor(0x66000000) },FrameLayout.LayoutParams(-2,dp(48),Gravity.TOP or Gravity.START)) }
        player.setMediaController(MediaController(this).apply { setAnchorView(player) })
        dialog.setContentView(frame);dialog.setOnDismissListener { player.stopPlayback();video=null;preview=null }
        player.setOnErrorListener { _,_,_ -> Toast.makeText(this,"Không mở được video này",Toast.LENGTH_SHORT).show();dialog.dismiss();true }
        dialog.show();dialog.window?.setLayout(-1,-1)
        player.setOnPreparedListener { player.start() };player.setVideoURI(uri)
    }
    override fun onBackPressed() { if(preview!=null)preview?.dismiss() else if(section!="root")openFolder("root") else super.onBackPressed() }
    override fun onNewIntent(intent:Intent) { super.onNewIntent(intent);setIntent(intent);preview?.dismiss();openFolder(intent.getStringExtra("folder") ?: "root") }
    override fun onSaveInstanceState(out:Bundle) { out.putString("folder",section);super.onSaveInstanceState(out) }
    override fun onPause() { handler.removeCallbacks(refresh);resumeVideo=video?.isPlaying==true;video?.pause();super.onPause() }
    override fun onResume() { super.onResume();handler.removeCallbacks(refresh);handler.post(refresh);if(resumeVideo)video?.start();resumeVideo=false }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null);preview?.dismiss();if(current?.get()===this)current=null;super.onDestroy() }
}
