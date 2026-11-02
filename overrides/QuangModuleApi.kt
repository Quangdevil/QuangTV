package app.tvviewer.player

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/** Shared app actions for native module screens. No website can call this channel. */
object QuangModuleApi {
    private const val ORIGIN="https://may-viet-web-proxy.daquang.workers.dev"
    private val workers=Executors.newFixedThreadPool(2)
    private val main=Handler(Looper.getMainLooper())
    private var fixture=false
    private var lastDeleted:Uri?=null
    private fun rows(c:Context,key:String):List<JSONObject> {
        val a=try{JSONArray(c.getSharedPreferences("quangtube_history",0).getString(key,"[]"))}catch(_:Exception){JSONArray()}
        return (0 until a.length()).mapNotNull{a.optJSONObject(it)}
    }
    private fun save(c:Context,key:String,items:List<JSONObject>){val a=JSONArray();items.take(100).forEach{a.put(it)};c.getSharedPreferences("quangtube_history",0).edit().putString(key,a.toString()).apply()}
    private fun record(c:Context,key:String,item:JSONObject,field:String){save(c,key,listOf(item)+rows(c,key).filter{it.optString(field)!=item.optString(field)})}
    fun handle(a:Activity,call:MethodCall,result:MethodChannel.Result){
        val debug=a.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
        if(call.method=="testFixture" && debug){fixture=call.argument<Boolean>("enabled")==true;result.success(null);return}
        if(call.method=="lastDeleteExists" && debug){result.success(QuangDownloads.exists(a,lastDeleted));return}
        if(fixture && debug){
            if(call.method=="catalog"){result.success(listOf(mapOf("url" to "https://www.youtube.com/watch?v=aqz-KE-bpKQ","title" to "Native Tube fixture","author" to "QuangTV QA","thumbnail" to "","duration" to 60)));return}
            if(call.method=="playback"){result.success(mapOf("url" to "http://10.0.2.2:8765/fixture.mp4","title" to "Native Tube fixture","page" to "https://www.youtube.com/watch?v=aqz-KE-bpKQ","choices" to listOf(mapOf("url" to "http://10.0.2.2:8765/fixture.mp4","quality" to "Fixture"))));return}
            if(call.method=="browse" && Uri.parse(call.argument<String>("url") ?: "").host=="quangtv.fixture"){result.success(mapOf("url" to "https://quangtv.fixture/","html" to "<html><body><h1>Native browser fixture</h1><video controls src='http://10.0.2.2:8765/fixture.mp4'></video></body></html>"));return}
        }
        when(call.method){
            "browse" -> {
                val target=call.argument<String>("url") ?: "";val uri=Uri.parse(target)
                if(uri.scheme !in listOf("http","https")||uri.host.isNullOrEmpty()){result.error("URL","Địa chỉ không hợp lệ",null);return}
                val fields=call.argument<List<List<String>>>("fields")
                workers.execute {
                    var connection:HttpURLConnection?=null
                    try{
                        connection=URL("$ORIGIN/browse").openConnection() as HttpURLConnection
                        connection.connectTimeout=20000;connection.readTimeout=20000;connection.requestMethod="POST";connection.doOutput=true
                        connection.setRequestProperty("Content-Type","application/json")
                        val body=JSONObject().put("url",target).put("method",if(call.argument<String>("method")=="POST")"POST" else "GET").put("fields",fields?.let{JSONArray(it)} ?: JSONObject.NULL).put("nativeHLS",true).toString().toByteArray(Charsets.UTF_8)
                        connection.setFixedLengthStreamingMode(body.size);connection.outputStream.use{it.write(body)}
                        check(connection.responseCode in 200..299){"Không tải được trang (${connection.responseCode})"}
                        val type=connection.contentType ?: "";val html=if(type.startsWith("video/")||type.contains("mpegurl")){
                            val src=android.text.TextUtils.htmlEncode("$ORIGIN/proxy?url=${Uri.encode(target)}")
                            "<meta name='viewport' content='width=device-width'><body style='margin:0;background:#0b111a'><video src='$src' controls autoplay muted playsinline style='width:100%;height:100vh'></video></body>"
                        }else{
                            check(type.contains("text/html")){"Địa chỉ này không phải trang HTML hoặc video"}
                            connection.inputStream.use{input->val out=java.io.ByteArrayOutputStream();val b=ByteArray(65536);while(true){val n=input.read(b);if(n<0)break;check(out.size()+n<=8*1024*1024){"Trang quá lớn"};out.write(b,0,n)};out.toString("UTF-8")}
                        }
                        main.post{result.success(mapOf("html" to html,"url" to target))}
                    }catch(e:Exception){main.post{result.error("BROWSE",e.message ?: "Không mở được trang",null)}}finally{connection?.disconnect()}
                }
            }
            "catalog" -> QuangYouTube.catalog(a.applicationContext,call.argument<String>("query") ?: ""){items,error->if(items!=null)result.success(items)else result.error("TUBE",error,null)}
            "playback" -> QuangYouTube.playback(a.applicationContext,call.argument<String>("url") ?: ""){item,error->if(item!=null)result.success(item)else result.error("TUBE",error,null)}
            "tubeExtract" -> QuangYouTube.extract(a.applicationContext,call.argument<String>("url") ?: ""){choices,error->if(choices!=null)result.success(choices.map{mapOf("title" to it.title,"video" to it.video,"audio" to it.audio,"quality" to it.quality)})else result.error("TUBE",error,null)}
            "tubeDownload" -> {QuangYouTube.start(a,QuangYouTube.Choice(call.argument<String>("title") ?: "Video",call.argument<String>("video") ?: "",call.argument<String>("audio"),call.argument<String>("quality") ?: "MP4"));result.success(null)}
            "history" -> {
                val p=a.getSharedPreferences("quangtube_history",0)
                if(!p.getBoolean("legacySearchImported",false)){
                    val old=rows(a,"searches");val known=old.map{it.optString("query")}.toSet()
                    save(a,"searches",old+(call.argument<List<String>>("legacy") ?: emptyList()).filter{it !in known}.map{JSONObject().put("query",it)})
                    p.edit().putBoolean("legacySearchImported",true).apply()
                }
                result.success(mapOf("searches" to rows(a,"searches").map{it.optString("query")},"videos" to rows(a,"videos").map{mapOf("id" to it.optString("id"),"title" to it.optString("title"),"thumbnail" to it.optString("thumbnail"))}))
            }
            "recordSearch" -> {val query=(call.argument<String>("query") ?: "").trim().take(300);if(query.isNotEmpty())record(a,"searches",JSONObject().put("query",query),"query");result.success(null)}
            "recordVideo" -> {val id=call.argument<String>("id") ?: "";if(id.matches(Regex("[A-Za-z0-9_-]{11}")))record(a,"videos",JSONObject().put("id",id).put("title",call.argument<String>("title") ?: "Video").put("thumbnail",call.argument<String>("thumbnail") ?: ""),"id");result.success(null)}
            "deleteHistory" -> {val key=if(call.argument<String>("kind")=="searches")"searches" else "videos";val field=if(key=="searches")"query" else "id";val value=call.argument<String>("value");save(a,key,if(value==null)emptyList()else rows(a,key).filter{it.optString(field)!=value});result.success(null)}
            "download" -> {var url=call.argument<String>("url") ?: "";if(fixture && debug){val inner=Uri.parse(url).getQueryParameter("url");if(inner!=null&&Uri.parse(inner).host=="10.0.2.2")url=QuangProxy.downloadUrl(a,inner)};if(Uri.parse(url).scheme !in listOf("http","https")){result.error("URL","URL tải không hợp lệ",null);return};val name=(call.argument<String>("name") ?: "Video.mp4").replace(Regex("[^\\p{L}\\p{N} _.-]"),"_").take(140);result.success(QuangDownloads.enqueue(a,url,mapOf("User-Agent" to android.webkit.WebSettings.getDefaultUserAgent(a)),name))}
            "downloads" -> result.success(QuangDownloads.entries(a).map{mapOf("key" to it.key,"name" to it.name,"state" to it.state,"bytes" to it.bytes,"total" to it.total,"complete" to it.complete,"active" to it.active,"detail" to it.detail)})
            "deleteDownload" -> {val entry=QuangDownloads.entries(a).firstOrNull{it.key==call.argument<String>("key")};lastDeleted=entry?.uri;result.success(entry!=null&&QuangDownloads.remove(a,entry))}
            "openDownload" -> {val key=call.argument<String>("key");if(QuangDownloads.entries(a).any{it.key==key&&it.complete})a.startActivity(Intent(a,QuangDownloadsActivity::class.java).putExtra("folder","videos").putExtra("openKey",key));result.success(null)}
            else -> result.notImplemented()
        }
    }
}
