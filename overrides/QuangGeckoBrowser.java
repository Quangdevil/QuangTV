package app.tvviewer.player;

import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.*;
import java.lang.ref.WeakReference;
import java.util.*;
import org.json.*;
import org.mozilla.geckoview.*;

/** Native browser chrome and home; Gecko is bundled, Android WebView is not used. */
public final class QuangGeckoBrowser extends LinearLayout {
    public interface Listener { void fullscreen(boolean full); default void searchRequested() {} }
    private static final int BG=0xff0b111a, PANEL=0xff14232d, MINT=0xff8ae4d1, TEXT=0xffedf5f5;
    private static GeckoRuntime runtime;
    private static GeckoResult<WebExtension> extension;
    private static WebExtension installedExtension;
    private final Map<GeckoSession,WebExtension.Port> controls=new IdentityHashMap<>();
    private boolean showingHome;
    private static WeakReference<QuangGeckoBrowser> focused=new WeakReference<>(null);
    private final ArrayList<GeckoSession> tabs=new ArrayList<>();
    private final Map<GeckoSession,String> urls=new IdentityHashMap<>(), titles=new IdentityHashMap<>();
    private final LinkedHashMap<String,JSONObject> media=new LinkedHashMap<>();
    private final GeckoView view;
    private final FrameLayout page;
    private final LinearLayout header, tools;
    private final EditText address;
    private final TextView state;
    private final Button tabButton, exit;
    private final Listener listener;
    private final Map<GeckoSession,Boolean> canBack=new IdentityHashMap<>();
    private GeckoSession session;
    private boolean full, appPage, active=true, closed, ready;
    private String pending;

    public QuangGeckoBrowser(Context context, boolean applicationPage, Listener listener) {
        super(context);this.listener=listener;appPage=applicationPage;
        setOrientation(VERTICAL);setBackgroundColor(BG);setFocusableInTouchMode(true);requestFocus();
        header=new LinearLayout(context);header.setGravity(Gravity.CENTER_VERTICAL);header.setPadding(dp(8),dp(6),dp(8),dp(6));
        Button home=button("☁", "Trang đầu Mây", this::home);header.addView(home,new LayoutParams(dp(48),dp(48)));
        address=new EditText(context);address.setTextColor(TEXT);address.setHintTextColor(0xff93a7b3);address.setTextSize(15);
        address.setSingleLine(true);address.setHint("Tìm kiếm hoặc nhập địa chỉ");address.setBackground(shape(PANEL));address.setPadding(dp(14),0,dp(8),0);
        address.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_VARIATION_URI);
        address.setImeOptions(EditorInfo.IME_ACTION_GO|EditorInfo.IME_FLAG_NO_EXTRACT_UI);
        address.setOnEditorActionListener((v,action,event)->{if(action==EditorInfo.IME_ACTION_GO){navigate(address.getText().toString());return true;}return false;});
        address.setOnClickListener(v->{if(listener!=null)listener.searchRequested();});
        header.addView(address,new LayoutParams(0,dp(48),1));
        header.addView(button("→","Truy cập",()->navigate(address.getText().toString())),new LayoutParams(dp(48),dp(48)));
        tabButton=button("1","Các tab",this::showTabs);header.addView(tabButton,new LayoutParams(dp(48),dp(48)));
        addView(header,new LayoutParams(-1,-2));
        state=new TextView(context);state.setTextColor(MINT);state.setTextSize(12);state.setPadding(dp(12),0,dp(12),dp(4));addView(state);
        page=new FrameLayout(context);addView(page,new LayoutParams(-1,0,1));
        view=new GeckoView(new android.view.ContextThemeWrapper(context,android.R.style.Theme_Material_NoActionBar));
        // TextureView composes into Android Auto's projected view hierarchy.
        view.setViewBackend(GeckoView.BACKEND_TEXTURE_VIEW);view.coverUntilFirstPaint(BG);
        page.addView(view,new FrameLayout.LayoutParams(-1,-1));
        exit=button("×","Thoát toàn màn hình",()->{if(session!=null)session.exitFullScreen();setFull(false);});
        FrameLayout.LayoutParams ep=new FrameLayout.LayoutParams(dp(48),dp(48),Gravity.TOP|Gravity.END);page.addView(exit,ep);exit.setVisibility(GONE);
        tools=new LinearLayout(context);tools.setGravity(Gravity.CENTER);tools.setBackgroundColor(PANEL);
        tools.addView(button("‹","Quay lại",this::back),new LayoutParams(0,dp(48),1));
        tools.addView(button("›","Tiến tới",()->{if(session!=null)session.goForward();}),new LayoutParams(0,dp(48),1));
        tools.addView(button("↻","Tải lại",()->{if(session!=null)session.reload();}),new LayoutParams(0,dp(48),1));
        tools.addView(button("Tải video","Video trong trang",this::showMedia),new LayoutParams(0,dp(48),2));
        tools.addView(button("⋮","Tùy chọn",this::options),new LayoutParams(0,dp(48),1));addView(tools,new LayoutParams(-1,-2));
        if(applicationPage){header.setVisibility(GONE);tools.setVisibility(GONE);}
        focused=new WeakReference<>(this);state.setText("Đang khởi động Mây…");
        try {
            if(runtime==null)runtime=GeckoRuntime.create(context.getApplicationContext(),new GeckoRuntimeSettings.Builder().remoteDebuggingEnabled(false).build());
            if(extension==null)extension=runtime.getWebExtensionController().ensureBuiltIn("resource://android/assets/may_gecko/","may-native@quangtv");
            extension.accept(ext->{
                installedExtension=ext;
                ext.setMessageDelegate(new WebExtension.MessageDelegate(){
                    @Override public GeckoResult<Object> onMessage(String app,Object raw,WebExtension.MessageSender sender){
                        if(!(raw instanceof JSONObject))return GeckoResult.fromValue(null);
                        JSONObject data=(JSONObject)raw;QuangGeckoBrowser browser=focused.get();
                        if("config".equals(data.optString("op"))){
                            JSONObject config=new JSONObject();
                            try {Map<String,Object> proxy=QuangProxy.INSTANCE.state(context.getApplicationContext());config.put("enabled",Boolean.TRUE.equals(proxy.get("enabled")));config.put("port",proxy.get("localPort"));}
                            catch(Exception error){try{config.put("enabled",true).put("port",9);}catch(JSONException ignored){}}
                            return GeckoResult.fromValue(config.toString());
                        }
                        if(browser!=null&&!browser.closed&&"media".equals(data.optString("op")))browser.receiveMedia(data);
                        return GeckoResult.fromValue(null);
                    }
                },"may");
                if(closed)return;ready=true;newTab(false);if(pending!=null){String target=pending;pending=null;navigate(target);}else if(!appPage)home();
            },error->{if(!closed)state.setText("Không khởi động được trình duyệt. Đóng và mở lại Mây.");});
        }catch(RuntimeException error){state.setText("Không khởi động được trình duyệt.");}
    }
    private int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
    private GradientDrawable shape(int color){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(12));return d;}
    private Button button(String text,String hint,Runnable action){Button b=new Button(getContext());b.setText(text);b.setTextColor(MINT);b.setTextSize(14);b.setAllCaps(false);b.setMinWidth(0);b.setMinimumWidth(0);b.setPadding(dp(6),0,dp(6),0);b.setBackground(shape(PANEL));b.setContentDescription(hint);b.setOnClickListener(v->{focused=new WeakReference<>(this);action.run();});return b;}
    private void newTab(boolean privateMode){
        if(tabs.size()>=16){state.setText("Đóng bớt tab trước khi mở thêm.");return;}
        GeckoSession next=new GeckoSession(new GeckoSessionSettings.Builder().usePrivateMode(privateMode).useTrackingProtection(true).suspendMediaWhenInactive(true).fullAccessibilityTree(true).build());
        next.setContentDelegate(new GeckoSession.ContentDelegate(){
            @Override public void onTitleChange(GeckoSession s,String title){titles.put(s,title);}
            @Override public void onFullScreen(GeckoSession s,boolean value){if(s==session)setFull(value);}
            @Override public void onCrash(GeckoSession s){state.setText("Trang đã dừng. Bấm tải lại để thử lại.");}
            @Override public void onExternalResponse(GeckoSession s,WebResponse response){
                if(response.uri==null||!http(response.uri))return;
                try{JSONObject item=new JSONObject().put("url",response.uri).put("page",urls.get(s)).put("title",titles.get(s));receiveMedia(item);if(s==session)showMedia();}catch(JSONException ignored){}
            }
        });
        next.setNavigationDelegate(new GeckoSession.NavigationDelegate(){
            @Override public void onCanGoBack(GeckoSession s,boolean value){canBack.put(s,value);}
            @Override public void onLocationChange(GeckoSession s,String url,List<GeckoSession.PermissionDelegate.ContentPermission> permissions,Boolean gesture){urls.put(s,url);if(s==session&&!address.hasFocus())address.setText(url);}
            @Override public GeckoResult<AllowOrDeny> onLoadRequest(GeckoSession s,LoadRequest request){return GeckoResult.fromValue(http(request.uri)||"about:blank".equals(request.uri)?AllowOrDeny.ALLOW:AllowOrDeny.DENY);}
            @Override public GeckoResult<GeckoSession> onNewSession(GeckoSession s,String uri){return null;}
            @Override public GeckoResult<String> onLoadError(GeckoSession s,String uri,WebRequestError error){if(s==session)state.setText("Không tải được trang. Kiểm tra mạng/proxy hoặc tải lại.");return null;}
        });
        next.setProgressDelegate(new GeckoSession.ProgressDelegate(){
            @Override public void onPageStart(GeckoSession s,String url){if(s==session)state.setText("Đang tải…");}
            @Override public void onPageStop(GeckoSession s,boolean success){if(s==session)state.setText(success?"": "Trang chưa tải xong. Kiểm tra mạng hoặc tải lại.");}
        });
        if(installedExtension!=null)next.getWebExtensionController().setMessageDelegate(installedExtension,new WebExtension.MessageDelegate(){
            @Override public void onConnect(WebExtension.Port port){controls.put(next,port);port.setDelegate(new WebExtension.PortDelegate(){@Override public void onDisconnect(WebExtension.Port gone){controls.remove(next);}});}
        },"mayControl");
        next.open(runtime);tabs.add(next);switchTab(next);
    }
    private void switchTab(GeckoSession next){if(session!=null)session.setActive(false);view.releaseSession();session=next;view.setSession(next);next.setActive(active);address.setText(urls.get(next));tabButton.setText(String.valueOf(tabs.size()));media.clear();}
    public static boolean http(String raw){if(raw==null)return false;try{Uri u=Uri.parse(raw);return ("https".equalsIgnoreCase(u.getScheme())||"http".equalsIgnoreCase(u.getScheme()))&&u.getHost()!=null&&u.getUserInfo()==null;}catch(RuntimeException e){return false;}}
    public void navigate(String raw){
        String target=raw==null?"":raw.trim();if(target.isEmpty()){home();return;}
        if(!http(target)){if(!target.contains(" ")&&target.contains(".")&&!target.contains("://"))target="https://"+target;else target="https://duckduckgo.com/?q="+Uri.encode(target);}
        if(!ready){pending=target;return;}if(!http(target))return;
        focused=new WeakReference<>(this);pageHome(false);media.clear();address.setText(target);address.clearFocus();
        InputMethodManager ime=(InputMethodManager)getContext().getSystemService(Context.INPUT_METHOD_SERVICE);if(ime!=null)ime.hideSoftInputFromWindow(address.getWindowToken(),0);
        session.setActive(active);session.loadUri(target);view.requestFocus();
    }
    private View homeView;
    private void pageHome(boolean home){showingHome=home;if(homeView!=null)homeView.setVisibility(home?VISIBLE:GONE);view.setVisibility(home?INVISIBLE:VISIBLE);}
    public void home(){
        if(!ready)return;setFull(false);session.setActive(false);
        if(homeView==null){
            ScrollView scroll=new ScrollView(getContext());LinearLayout list=new LinearLayout(getContext());list.setPadding(dp(24),dp(24),dp(24),dp(24));list.setOrientation(VERTICAL);scroll.addView(list);
            TextView title=new TextView(getContext());title.setText("☁  Mây");title.setTextSize(32);title.setTextColor(TEXT);list.addView(title);
            TextView caption=new TextView(getContext());caption.setText("Một không gian · Nhiều cảm hứng\nTìm kiếm hoặc nhập địa chỉ phía trên.");caption.setTextColor(0xff93a7b3);caption.setPadding(0,dp(12),0,dp(22));list.addView(caption);
            list.addView(button("Tab riêng tư","Mở tab riêng tư",()->{newTab(true);pageHome(false);session.loadUri("about:blank");address.requestFocus();}));
            list.addView(button("Dấu trang","Dấu trang",this::bookmarks));list.addView(button("Đã tải","Đã tải",this::downloads));
            homeView=scroll;page.addView(scroll,new FrameLayout.LayoutParams(-1,-1));exit.bringToFront();
        }pageHome(true);address.setText("");state.setText("");
    }
    public void submitSearch(String text){
        WebExtension.Port port=controls.get(session);String current=urls.get(session);
        if(appPage&&current!=null&&Uri.parse(current).getPath().startsWith("/tube")&&port!=null){
            try{port.postMessage(new JSONObject().put("op","search").put("query",text));}catch(JSONException ignored){}
        }else navigate(text);
    }
    public boolean back(){if(menuView!=null){page.removeView(menuView);menuView=null;return true;}if(full){session.exitFullScreen();setFull(false);return true;}if(homeView!=null&&homeView.getVisibility()==VISIBLE)return false;if(session!=null&&Boolean.TRUE.equals(canBack.get(session)))session.goBack();else home();return true;}
    public void setActive(boolean value){active=value;if(session!=null)session.setActive(value&&!showingHome);}
    public void enterFullscreen(){setFull(true);}
    private void setFull(boolean value){full=value;header.setVisibility(value||appPage?GONE:VISIBLE);tools.setVisibility(value||appPage?GONE:VISIBLE);state.setVisibility(value?GONE:VISIBLE);exit.setVisibility(value?VISIBLE:GONE);if(listener!=null)listener.fullscreen(value);}
    private View menuView;
    private void choose(String title,String[] items,java.util.function.IntConsumer action){
        if(menuView!=null)page.removeView(menuView);
        ScrollView scroll=new ScrollView(getContext());scroll.setBackgroundColor(BG);LinearLayout list=new LinearLayout(getContext());list.setOrientation(VERTICAL);list.setPadding(dp(16),dp(16),dp(16),dp(16));scroll.addView(list);
        list.addView(button("×  "+title,"Đóng "+title,()->{page.removeView(scroll);menuView=null;}));
        for(int i=0;i<items.length;i++){final int n=i;Button row=button(items[i],items[i],()->{page.removeView(scroll);menuView=null;action.accept(n);});LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,dp(56));lp.topMargin=dp(8);list.addView(row,lp);}
        menuView=scroll;page.addView(scroll,new FrameLayout.LayoutParams(-1,-1));
    }
    private void showTabs(){String[] names=new String[tabs.size()+2];for(int i=0;i<tabs.size();i++)names[i]=(tabs.get(i)==session?"● ":"")+titles.getOrDefault(tabs.get(i),"Tab "+(i+1));names[tabs.size()]="+ Tab mới";names[tabs.size()+1]="Đóng tab hiện tại";choose("Các tab",names,n->{if(n<tabs.size()){switchTab(tabs.get(n));pageHome(false);}else if(n==tabs.size()){newTab(false);home();}else closeTab();});}
    private void closeTab(){if(tabs.size()==1){home();return;}GeckoSession old=session;view.releaseSession();tabs.remove(old);urls.remove(old);titles.remove(old);old.close();session=null;switchTab(tabs.get(tabs.size()-1));pageHome(false);}
    private void options(){choose("Mây",new String[]{"Trang đầu","Thêm dấu trang","Dấu trang","Đã tải","Tab riêng tư","Về trình duyệt"},n->{switch(n){case 0:home();break;case 1:saveBookmark();break;case 2:bookmarks();break;case 3:downloads();break;case 4:newTab(true);home();break;default:choose("Mây · Gecko 159 · MPL 2.0",new String[]{"Giao diện native · Bộ máy Firefox/Gecko"},i->{});}});}
    private android.content.SharedPreferences prefs(){return getContext().getSharedPreferences("may_native_browser",Context.MODE_PRIVATE);}
    private void saveBookmark(){String url=urls.get(session);if(!http(url))return;try{JSONObject saved=new JSONObject(prefs().getString("bookmarks","{}"));saved.put(url,titles.getOrDefault(session,url));prefs().edit().putString("bookmarks",saved.toString()).apply();state.setText("Đã thêm dấu trang");}catch(JSONException ignored){}}
    private void bookmarks(){try{JSONObject saved=new JSONObject(prefs().getString("bookmarks","{}"));ArrayList<String> keys=new ArrayList<>(),labels=new ArrayList<>();Iterator<String> it=saved.keys();while(it.hasNext()){String k=it.next();keys.add(k);labels.add(saved.optString(k,k));}choose("Dấu trang",labels.toArray(new String[0]),n->navigate(keys.get(n)));}catch(JSONException ignored){}}
    private void downloads(){try{getContext().startActivity(new Intent(getContext(),QuangDownloadsActivity.class));}catch(RuntimeException error){state.setText("Mở Đã tải trong ứng dụng trên điện thoại.");}}
    private void receiveMedia(JSONObject item){String url=item.optString("url");if(!http(url))return;String owner=item.optString("page");if(!owner.isEmpty()&&!Objects.equals(owner,urls.get(session)))return;if(media.size()<100)media.put(url,item);}
    private void showMedia(){if(media.isEmpty()){state.setText("Chưa tìm thấy video có thể tải trong trang này.");return;}ArrayList<JSONObject> items=new ArrayList<>(media.values());String[] labels=new String[items.size()];for(int i=0;i<items.size();i++){Uri u=Uri.parse(items.get(i).optString("url"));labels[i]=(u.getLastPathSegment()==null?"Video":u.getLastPathSegment());}choose("Video trong trang",labels,n->{JSONObject item=items.get(n);choose("Video",new String[]{"Mở video","Tải về"},action->{if(action==0)navigate(item.optString("url"));else enqueue(item);});});}
    private void enqueue(JSONObject item){try{Map<String,String> headers=new HashMap<>();JSONObject h=item.optJSONObject("headers");if(h!=null)for(String k:new String[]{"User-Agent","Referer","Cookie","Authorization"}){String v=h.optString(k);if(!v.isEmpty()&&v.length()<16000)headers.put(k,v);}QuangDownloads.INSTANCE.enqueue(getContext(),item.getString("url"),headers,"May-video.mp4");state.setText("Đã thêm vào Đã tải");}catch(Exception error){state.setText("Không thêm được tải xuống. Hãy thử lại từ trang gốc.");}}
    public void close(){closed=true;view.releaseSession();for(GeckoSession s:tabs)s.close();tabs.clear();if(focused.get()==this)focused.clear();}
}
