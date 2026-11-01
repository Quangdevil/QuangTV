package app.tvviewer.player;

import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.VideoView;
import com.google.android.apps.auto.sdk.CarActivity;
import com.google.android.apps.auto.sdk.SearchCallback;
import com.google.android.apps.auto.sdk.SearchItem;
import org.json.JSONArray;
import org.json.JSONObject;

/** Native projection UI. Does not start phone Activities from the car display. */
public final class QuangAutoActivity extends CarActivity {
    private static final String YOUTUBE = "https://m.youtube.com/";
    private LinearLayout root;
    private FrameLayout content;
    private TextView status;
    private WebView web;
    private VideoView video;
    private View fullScreen;
    private WebChromeClient.CustomViewCallback fullScreenCallback;
    private boolean stopped;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        setIgnoreConfigChanges(0xFFFFFFFF);
        getCarUiController().getStatusBarController().hideAppHeader();
        getCarUiController().getMenuController().hideMenuButton();
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.BLACK);
        LinearLayout toolbar = new LinearLayout(this);
        addButton(toolbar, "‹", this::back);
        addButton(toolbar, "YouTube", () -> openWeb(YOUTUBE));
        addButton(toolbar, "TV", this::showChannels);
        addButton(toolbar, "Tìm", () -> getCarUiController().getSearchController().startSearch(""));
        addButton(toolbar, "−10s", () -> seek(-10000));
        addButton(toolbar, "▶/Ⅱ", this::togglePlayback);
        addButton(toolbar, "+10s", () -> seek(10000));
        root.addView(toolbar, new LinearLayout.LayoutParams(-1, -2));
        status = new TextView(this);
        status.setTextColor(Color.WHITE);
        status.setPadding(12, 4, 12, 4);
        root.addView(status);
        content = new FrameLayout(this);
        root.addView(content, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root);
        getCarUiController().getSearchController().setSearchHint("Tìm YouTube hoặc nhập URL HTTPS");
        getCarUiController().getSearchController().setSearchCallback(new SearchCallback() {
            @Override public void onSearchItemSelected(SearchItem item) {}
            @Override public void onSearchTextChanged(String text) {}
            @Override public boolean onSearchSubmitted(String text) {
                String query = text.trim();
                getCarUiController().getSearchController().stopSearch();
                Uri uri = Uri.parse(query);
                if ("https".equalsIgnoreCase(uri.getScheme()) || "http".equalsIgnoreCase(uri.getScheme())) {
                    String path = uri.getPath();
                    if (path != null && path.matches("(?i).*\\.(m3u8|mp4|webm|mp3|aac)$")) play(query, query);
                    else openWeb(query);
                } else openWeb(YOUTUBE + "results?search_query=" + Uri.encode(query));
                return true;
            }
        });
        openWeb(state == null ? YOUTUBE : state.getString("quangtv.auto.url", YOUTUBE));
    }

    private void addButton(LinearLayout row, String label, Runnable action) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextSize(16);
        button.setMinWidth(0);
        button.setMinimumWidth(0);
        button.setOnClickListener(v -> action.run());
        row.addView(button, new LinearLayout.LayoutParams(0, -2, 1));
    }

    private void openWeb(String url) {
        clearContent();
        web = new WebView(this);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                String scheme = request.getUrl().getScheme();
                return !("https".equalsIgnoreCase(scheme) || "http".equalsIgnoreCase(scheme));
            }
            @Override public void onPageFinished(WebView view, String loaded) {
                status.setText("QuangTV Auto · " + Uri.parse(loaded).getHost());
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override public void onShowCustomView(View view, CustomViewCallback callback) {
                if (fullScreen != null) { callback.onCustomViewHidden(); return; }
                fullScreen = view;
                fullScreenCallback = callback;
                web.setVisibility(View.GONE);
                content.addView(view, new FrameLayout.LayoutParams(-1, -1));
            }
            @Override public void onHideCustomView() { leaveFullScreen(); }
        });
        content.addView(web, new FrameLayout.LayoutParams(-1, -1));
        status.setText("QuangTV Auto · Đang tải…");
        web.loadUrl(url);
    }

    private void showChannels() {
        clearContent();
        status.setText("Các kênh IPTV đã lưu trong QuangTV trên điện thoại");
        ScrollView scroll = new ScrollView(this);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(list);
        content.addView(scroll);
        // shared_preferences Android backend prefixes Dart keys with flutter.
        String cached = getSharedPreferences("FlutterSharedPreferences", 0)
                .getString("flutter.quangtv_auto_channels", "[]");
        int count = 0;
        try {
            JSONArray channels = new JSONArray(cached);
            for (int i = 0; i < channels.length(); i++) {
                JSONObject channel = channels.getJSONObject(i);
                String name = channel.optString("name");
                String url = channel.optString("url");
                if (url.isEmpty()) continue;
                Button button = new Button(this);
                button.setText(name);
                button.setOnClickListener(v -> play(name, url));
                list.addView(button, new LinearLayout.LayoutParams(-1, -2));
                count++;
            }
        } catch (Exception e) {
            status.setText("Không đọc được danh sách kênh. Hãy tải lại danh sách trên điện thoại.");
        }
        if (count == 0) {
            TextView empty = new TextView(this);
            empty.setTextColor(Color.WHITE);
            empty.setText("Mở QuangTV trên điện thoại và tải danh sách IPTV trước. Hoặc bấm Tìm để nhập URL phát trực tiếp.");
            empty.setPadding(24, 24, 24, 24);
            list.addView(empty);
        }
    }

    private void play(String name, String url) {
        clearContent();
        status.setText("Đang tải · " + name);
        VideoView current = new VideoView(this);
        video = current;
        content.addView(current, new FrameLayout.LayoutParams(-1, -1));
        current.setOnPreparedListener(player -> {
            if (video != current) return;
            status.setText(name);
            if (!stopped) current.start();
        });
        current.setOnErrorListener((player, what, extra) -> {
            if (video != current) return true;
            status.setText("Không phát được nguồn · " + name + " (" + what + "/" + extra + ")");
            return true;
        });
        current.setVideoURI(Uri.parse(url));
    }

    private void togglePlayback() {
        if (video != null) { if (video.isPlaying()) video.pause(); else video.start(); }
        if (web != null) web.evaluateJavascript("(()=>{const v=document.querySelector('video');if(v){if(v.paused)v.play().catch(()=>{});else v.pause();}})()", null);
    }

    private void seek(int millis) {
        if (video != null) video.seekTo(Math.max(0, video.getCurrentPosition() + millis));
        if (web != null) web.evaluateJavascript("(()=>{const v=document.querySelector('video');if(v)v.currentTime=Math.max(0,v.currentTime+" + millis / 1000 + ");})()", null);
    }

    private void leaveFullScreen() {
        if (fullScreen == null) return;
        content.removeView(fullScreen);
        fullScreen = null;
        WebChromeClient.CustomViewCallback callback = fullScreenCallback;
        fullScreenCallback = null;
        if (web != null) web.setVisibility(View.VISIBLE);
        if (callback != null) callback.onCustomViewHidden();
    }

    private void back() {
        if (fullScreen != null) leaveFullScreen();
        else if (web != null && web.canGoBack()) web.goBack();
        else showChannels();
    }

    private void clearContent() {
        leaveFullScreen();
        if (video != null) { video.stopPlayback(); video = null; }
        if (web != null) {
            web.onPause();
            web.stopLoading();
            ((ViewGroup) web.getParent()).removeView(web);
            web.destroy();
            web = null;
        }
        content.removeAllViews();
    }

    @Override public void onBackPressed() { back(); }
    @Override public void onSaveInstanceState(Bundle state) {
        super.onSaveInstanceState(state);
        if (web != null) state.putString("quangtv.auto.url", web.getUrl());
    }
    @Override public void onResume() {
        super.onResume();
        stopped = false;
        if (web != null) web.onResume();
    }
    @Override public void onStop() {
        stopped = true;
        if (video != null) video.pause();
        if (web != null) {
            web.evaluateJavascript("document.querySelectorAll('video,audio').forEach(v=>v.pause())", null);
            web.onPause();
        }
        super.onStop();
    }
    @Override public void onDestroy() {
        clearContent();
        super.onDestroy();
    }
}
