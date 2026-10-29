package app.tvviewer.player

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.webkit.WebView
import org.json.JSONObject
import org.json.JSONTokener

/** Called only by the debuggable Android integration-test channel. */
object QuangBrowserTestHooks {
    private val handler = Handler(Looper.getMainLooper())
    fun run(web: WebView, touchRoot: android.view.View, command: String, value: Double, done: (Map<String, Any>) -> Unit) {
        fun state() {
            web.evaluateJavascript("""JSON.stringify((()=>{const v=document.querySelector('video');const r=document.querySelector('#may-browser-controls')?.shadowRoot;const b=r?.querySelector('.player');return {pageUrl:location.href,title:document.title,shellReady:!!document.querySelector('#visit'),statusText:document.querySelector('#status')?.textContent??'',frameCount:document.querySelectorAll('#browser iframe').length,fixtureError:window.__quangFixtureError??'',videoError:v?.error?.message??'',videoErrorCode:v?.error?.code??0,networkState:v?.networkState??-1,readyState:v?.readyState??-1,videoSource:v?.currentSrc??v?.src??'',ready:!!v&&v.readyState>=2,frameReady:document.querySelector('#browser iframe')?.dataset.ready==='1',nativeFullscreen:!!document.fullscreenElement,hasControls:!!r,hasSeek:!!r?.querySelector('.seek'),paused:v?.paused??true,muted:v?.muted??true,volume:v?.volume??0,position:v?.currentTime??0,duration:Number.isFinite(v?.duration)?v.duration:0,hidden:b?.classList.contains('off')??true,stage:!!document.querySelector('#may-video-stage')};})())""") { raw ->
                try {
                    val decoded = JSONTokener(raw).nextValue() as? String ?: "{}"
                    val obj = JSONObject(decoded)
                    done(obj.keys().asSequence().associateWith { obj.get(it) })
                } catch (_: Exception) { done(mapOf("error" to "state unavailable")) }
            }
        }
        if (command == "state") { state(); return }
        val selector = when(command) {
            "play" -> "[data-action=play]"
            "volume" -> ".volume"
            "seek" -> ".seek"
            else -> ""
        }
        val point = if (selector.isNotEmpty()) {
            "${if(command=="seek") "const video=document.querySelector('video');if(video)video.loop=false;" else ""}const e=document.querySelector('#may-browser-controls')?.shadowRoot?.querySelector('$selector');if(!e)return null;const b=e.getBoundingClientRect();return {x:b.left+b.width*${value.coerceIn(0.0,1.0)},y:b.top+b.height/2,w:innerWidth};"
        } else {
            "const v=document.querySelector('video');if(!v)return null;${if(command=="back10"||command=="forward10")"v.loop=false;" else ""}const b=v.getBoundingClientRect();return {x:b.left+b.width*${if(command=="back10")0.25 else if(command=="forward10")0.75 else 0.5},y:b.top+b.height*.45,w:innerWidth};"
        }
        web.evaluateJavascript("JSON.stringify((()=>{$point})())") { raw ->
            try {
                val obj = JSONObject(JSONTokener(raw).nextValue() as String)
                val scale = web.width / obj.getDouble("w")
                val webPoint=IntArray(2);web.getLocationInWindow(webPoint)
                val rootPoint=IntArray(2);touchRoot.getLocationInWindow(rootPoint)
                val x = (obj.getDouble("x") * scale + webPoint[0] - rootPoint[0]).toFloat()
                val y = (obj.getDouble("y") * scale + webPoint[1] - rootPoint[1]).toFloat()
                fun tap() {
                    val now=SystemClock.uptimeMillis()
                    val down=MotionEvent.obtain(now,now,MotionEvent.ACTION_DOWN,x,y,0)
                    touchRoot.dispatchTouchEvent(down); down.recycle()
                    val up=MotionEvent.obtain(now,now+40,MotionEvent.ACTION_UP,x,y,0)
                    touchRoot.dispatchTouchEvent(up); up.recycle()
                }
                tap()
                if(command=="back10"||command=="forward10")handler.postDelayed({tap()},120)
                handler.postDelayed({state()},450)
            } catch (_: Exception) { done(mapOf("error" to "control unavailable")) }
        }
    }
}
