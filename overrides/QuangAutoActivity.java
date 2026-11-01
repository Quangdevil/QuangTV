package app.tvviewer.player;
import android.graphics.Color;
import android.os.Bundle;
import android.view.*;
import android.widget.*;
import com.google.android.apps.auto.sdk.CarActivity;
import com.google.android.gms.car.CarSensorManager;

/** Native task rail, bundled Gecko content, and a fail-closed parked-state gate. */
public final class QuangAutoActivity extends CarActivity {
 private static final String MAY="https://may-viet-web-proxy.daquang.workers.dev/";
 private LinearLayout root,rail;
 private FrameLayout content;
 private TextView blocked;
 private QuangGeckoBrowser browser;
 private CarSensorManager sensors;
 private boolean statusKnown,restricted=true,moving,stopped;
 private final CarSensorManager.CarSensorEventListener listener=(type,time,floats,bytes)->{
   if(type==11&&bytes!=null&&bytes.length>0){statusKnown=true;restricted=bytes[0]!=0;}
   if(type==2&&floats!=null&&floats.length>0)moving=Math.abs(floats[0])>.05f;
   updateGate();
 };
 @Override public void onCreate(Bundle saved){
  super.onCreate(saved);QuangAutoDiagnostics.record(this,"activity.onCreate.nativeGecko",null);setIgnoreConfigChanges(0xffffffff);
  try{getCarUiController().getStatusBarController().hideAppHeader();getCarUiController().getMenuController().hideMenuButton();}catch(RuntimeException ignored){}
  root=new LinearLayout(this);root.setBackgroundColor(0xff0b111a);root.setOrientation(LinearLayout.HORIZONTAL);
  rail=new LinearLayout(this);rail.setOrientation(LinearLayout.VERTICAL);rail.setPadding(dp(8),dp(12),dp(8),dp(12));
  TextView title=new TextView(this);title.setText("☁ Mây");title.setTextColor(0xff8ae4d1);title.setTextSize(24);title.setPadding(dp(12),0,0,dp(12));rail.addView(title);
  task("QuangTV",MAY);task("QuangTube",MAY+"tube");task("Podcast",MAY+"iptv?tab=podcast");task("Radio",MAY+"iptv?tab=radio");task("Private",MAY+"iptv?tab=private");task("Trình duyệt",null);
  ScrollView scroll=new ScrollView(this);scroll.addView(rail);root.addView(scroll,new LinearLayout.LayoutParams(dp(150),-1));
  content=new FrameLayout(this);root.addView(content,new LinearLayout.LayoutParams(0,-1,1));
  blocked=new TextView(this);blocked.setBackgroundColor(0xff0b111a);blocked.setTextColor(Color.WHITE);blocked.setTextSize(20);blocked.setGravity(Gravity.CENTER);blocked.setText("Chỉ mở nội dung khi xe đã đỗ.\nĐang chờ trạng thái từ Android Auto…");content.addView(blocked,new FrameLayout.LayoutParams(-1,-1));
  setContentView(root);
  try{sensors=(CarSensorManager)a("sensor");sensors.registerListener(listener,11,3);CarSensorManager.RawEventData initial=sensors.getLatestSensorEvent(11);if(initial!=null)listener.onSensorChanged(initial.sensorType,initial.timeStamp,initial.floatValues,initial.byteValues);if(sensors.isSensorSupported(2)){sensors.registerListener(listener,2,3);CarSensorManager.RawEventData speed=sensors.getLatestSensorEvent(2);if(speed!=null)listener.onSensorChanged(speed.sensorType,speed.timeStamp,speed.floatValues,speed.byteValues);}}
  catch(Exception error){QuangAutoDiagnostics.record(this,"parked.sensor.unavailable",error);}
  if(browser==null&&statusKnown&&!restricted&&!moving)open(MAY);
  updateGate();
 }
 private int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
 private void task(String title,String url){Button b=new Button(this);b.setText(title);b.setAllCaps(false);b.setTextSize(15);b.setTextColor(0xff8ae4d1);b.setBackgroundTintList(android.content.res.ColorStateList.valueOf(0xff14232d));b.setOnClickListener(v->open(url));rail.addView(b,new LinearLayout.LayoutParams(-1,dp(52)));}
 private boolean allowed(){return statusKnown&&!restricted&&!moving&&!stopped;}
 private void open(String url){if(!allowed()){updateGate();return;}if(browser!=null){browser.close();content.removeView(browser);}browser=new QuangGeckoBrowser(this,url!=null,full->{if(rail.getParent() instanceof View)((View)rail.getParent()).setVisibility(full?View.GONE:View.VISIBLE);});content.addView(browser,0,new FrameLayout.LayoutParams(-1,-1));if(url!=null)browser.navigate(url);updateGate();}
 private void updateGate(){if(blocked==null)return;boolean allow=allowed();blocked.setVisibility(allow?View.GONE:View.VISIBLE);if(browser!=null){browser.setActive(allow);browser.setVisibility(allow?View.VISIBLE:View.INVISIBLE);}if(!allow&&statusKnown)blocked.setText("Chỉ mở video và trình duyệt khi xe đã đỗ.");if(allow&&browser==null&&content!=null)open(MAY);}
 @Override public void onResume(){super.onResume();stopped=false;updateGate();}
 @Override public void onStop(){stopped=true;updateGate();super.onStop();}
 @Override public void onBackPressed(){if(browser!=null&&browser.back())return;super.onBackPressed();}
 @Override public void onDestroy(){if(sensors!=null)sensors.unregisterListener(listener);if(browser!=null)browser.close();super.onDestroy();}
}
