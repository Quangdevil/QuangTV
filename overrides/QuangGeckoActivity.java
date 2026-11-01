package app.tvviewer.player;
import android.app.Activity;
import android.os.Bundle;
import android.view.*;
import androidx.core.view.*;
/** A browser Activity with native chrome and a bundled Gecko engine. */
public final class QuangGeckoActivity extends Activity {
 private QuangGeckoBrowser browser;
 @Override public void onCreate(Bundle saved){super.onCreate(saved);WindowCompat.setDecorFitsSystemWindows(getWindow(),false);browser=new QuangGeckoBrowser(this,false,full->{WindowInsetsControllerCompat c=WindowCompat.getInsetsController(getWindow(),getWindow().getDecorView());if(full)c.hide(WindowInsetsCompat.Type.systemBars());else c.show(WindowInsetsCompat.Type.systemBars());});ViewCompat.setOnApplyWindowInsetsListener(browser,(v,insets)->{androidx.core.graphics.Insets bars=insets.getInsets(WindowInsetsCompat.Type.systemBars()|WindowInsetsCompat.Type.displayCutout());androidx.core.graphics.Insets ime=insets.getInsets(WindowInsetsCompat.Type.ime());v.setPadding(bars.left,bars.top,bars.right,Math.max(bars.bottom,ime.bottom));return WindowInsetsCompat.CONSUMED;});setContentView(browser);String url=getIntent().getStringExtra("url");if(url!=null&&!url.isEmpty()&&!url.equals("https://may-viet-web-proxy.daquang.workers.dev/browser"))browser.navigate(url);}
 @Override public void onBackPressed(){if(browser==null||!browser.back())super.onBackPressed();}
 @Override public void onResume(){super.onResume();if(browser!=null)browser.setActive(true);}
 @Override public void onPause(){if(browser!=null)browser.setActive(false);super.onPause();}
 @Override public void onDestroy(){if(browser!=null)browser.close();super.onDestroy();}
}
