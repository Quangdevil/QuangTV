package app.tvviewer.player;
import android.graphics.Color;
import android.os.Bundle;
import android.view.*;
import android.widget.*;
import com.google.android.apps.auto.sdk.CarActivity;
import com.google.android.apps.auto.sdk.SearchCallback;
import com.google.android.apps.auto.sdk.SearchItem;
import app.quangtv.car.LegacyParkedSensors;
import app.quangtv.car.ParkedSensorMonitor;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

/** Native task rail, bundled Gecko content, and a fail-closed parked-state gate. */
public final class QuangAutoActivity extends CarActivity {
 private static final String MAY="https://may-viet-web-proxy.daquang.workers.dev/";
 private LinearLayout root,rail;
 private FrameLayout content;
 private TextView blocked;
 private QuangGeckoBrowser browser;
 private LegacyParkedSensors sensors;
 private final Handler handler=new Handler(Looper.getMainLooper());
 private String lastGate="";
 private final Runnable poll=new Runnable(){public void run(){if(sensors!=null)sensors.monitor.tick(SystemClock.uptimeMillis());handler.postDelayed(this,1000);}};
 @Override public void onCreate(Bundle saved){
  super.onCreate(saved);QuangAutoDiagnostics.record(this,"activity.onCreate.nativeGecko",null);setIgnoreConfigChanges(0xffffffff);
  try{getCarUiController().getStatusBarController().hideAppHeader();getCarUiController().getMenuController().hideMenuButton();}catch(RuntimeException ignored){}
  root=new LinearLayout(this);root.setBackgroundColor(0xff0b111a);root.setOrientation(LinearLayout.HORIZONTAL);
  rail=new LinearLayout(this);rail.setOrientation(LinearLayout.VERTICAL);rail.setPadding(dp(8),dp(12),dp(8),dp(12));
  TextView title=new TextView(this);title.setText("☁ Mây");title.setTextColor(0xff8ae4d1);title.setTextSize(24);title.setPadding(dp(12),0,0,dp(12));rail.addView(title);
  task("QuangTV",MAY);task("QuangTube",MAY+"tube");task("Podcast",MAY+"iptv?tab=podcast");task("Radio",MAY+"iptv?tab=radio");task("Private",MAY+"iptv?tab=private");task("Trình duyệt",null);
  ScrollView scroll=new ScrollView(this);scroll.addView(rail);root.addView(scroll,new LinearLayout.LayoutParams(dp(150),-1));
  Button search=new Button(this);search.setText("Tìm / URL");search.setAllCaps(false);search.setTextColor(0xff8ae4d1);search.setBackgroundTintList(android.content.res.ColorStateList.valueOf(0xff14232d));search.setOnClickListener(v->{if(allowed())getCarUiController().getSearchController().startSearch("");});rail.addView(search,new LinearLayout.LayoutParams(-1,dp(52)));
  Button expand=new Button(this);expand.setText("Toàn màn ứng dụng");expand.setAllCaps(false);expand.setTextSize(13);expand.setTextColor(0xff8ae4d1);expand.setBackgroundTintList(android.content.res.ColorStateList.valueOf(0xff14232d));expand.setOnClickListener(v->{if(allowed()&&browser!=null)browser.enterFullscreen();});rail.addView(expand,new LinearLayout.LayoutParams(-1,dp(52)));
  content=new FrameLayout(this);root.addView(content,new LinearLayout.LayoutParams(0,-1,1));
  blocked=new TextView(this);blocked.setBackgroundColor(0xff0b111a);blocked.setTextColor(Color.WHITE);blocked.setTextSize(20);blocked.setGravity(Gravity.CENTER);blocked.setText("Chỉ mở nội dung khi xe đã đỗ.\nĐang chờ trạng thái từ Android Auto…");content.addView(blocked,new FrameLayout.LayoutParams(-1,-1));
  setContentView(root);
  getCarUiController().getSearchController().setSearchCallback(new SearchCallback(){public void onSearchItemSelected(SearchItem item){}public void onSearchTextChanged(String text){}public boolean onSearchSubmitted(String text){getCarUiController().getSearchController().stopSearch();if(allowed()&&browser!=null)browser.submitSearch(text);return true;}});
  sensors=new LegacyParkedSensors(this,new ParkedSensorMonitor.Listener(){
   public void changed(){updateGate();}
   public void trace(String key,String value){QuangAutoDiagnostics.record(QuangAutoActivity.this,key+"="+value,null);}
  });
  updateGate();
 }
 private int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
 private void task(String title,String url){Button b=new Button(this);b.setText(title);b.setAllCaps(false);b.setTextSize(15);b.setTextColor(0xff8ae4d1);b.setBackgroundTintList(android.content.res.ColorStateList.valueOf(0xff14232d));b.setOnClickListener(v->open(url));rail.addView(b,new LinearLayout.LayoutParams(-1,dp(52)));}
 private boolean allowed(){return sensors!=null&&sensors.monitor.allowed();}
 private void open(String url){if(!allowed()){updateGate();return;}if(browser!=null){browser.close();content.removeView(browser);}browser=new QuangGeckoBrowser(this,url!=null,new QuangGeckoBrowser.Listener(){public void fullscreen(boolean full){if(rail.getParent() instanceof View)((View)rail.getParent()).setVisibility(full?View.GONE:View.VISIBLE);}public void searchRequested(){if(allowed())getCarUiController().getSearchController().startSearch("");}});content.addView(browser,0,new FrameLayout.LayoutParams(-1,-1));if(url!=null)browser.navigate(url);updateGate();}
 private void updateGate(){
  if(blocked==null)return;
  boolean allow=allowed();String gate=sensors==null?"connecting":sensors.monitor.reason();
  if(!gate.equals(lastGate)){lastGate=gate;QuangAutoDiagnostics.record(this,"gate="+gate,null);}
  blocked.setText("waiting-for-status".equals(gate)||"connecting".equals(gate)?"Đang kết nối lại tín hiệu đỗ từ Android Auto…\nCác mục Mây ở cột bên trái.\nXem Chẩn đoán Android Auto trên điện thoại nếu xe không cấp tín hiệu.":"Chỉ mở video và trình duyệt khi xe đã đỗ.");
  blocked.setVisibility(allow?View.GONE:View.VISIBLE);
  if(browser!=null){browser.setActive(allow);browser.setVisibility(allow?View.VISIBLE:View.INVISIBLE);}
  if(allow&&browser==null&&content!=null)open(MAY);
 }
 @Override public void onResume(){super.onResume();handler.removeCallbacks(poll);if(sensors!=null)sensors.monitor.resume();handler.post(poll);}
 @Override public void onStop(){handler.removeCallbacks(poll);if(sensors!=null)sensors.monitor.stop();super.onStop();}
 @Override public void onBackPressed(){if(browser!=null&&browser.back())return;super.onBackPressed();}
 @Override public void onDestroy(){handler.removeCallbacks(poll);if(sensors!=null)sensors.monitor.stop();if(browser!=null)browser.close();super.onDestroy();}
}
