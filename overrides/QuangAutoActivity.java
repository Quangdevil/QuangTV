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
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import com.google.android.apps.auto.sdk.CarActivity;
import com.google.android.apps.auto.sdk.SearchCallback;
import com.google.android.apps.auto.sdk.SearchItem;
import org.json.JSONObject;

/** Native projection UI. Does not start phone Activities from the car display. */
public final class QuangAutoActivity extends CarActivity {
    private static final String MAY = "https://may-viet-web-proxy.daquang.workers.dev/";
    private static final String YOUTUBE = MAY + "tube";
    private LinearLayout root;
    private FrameLayout content;
    private TextView status;
    private WebView web;
    private View fullScreen;
    private WebChromeClient.CustomViewCallback fullScreenCallback;
    private boolean stopped;

    @Override public void onCreate(Bundle state) {
        QuangAutoDiagnostics.record(this, "activity.onCreate", null);
        try { initialize(state); }
        catch (RuntimeException | LinkageError error) {
            QuangAutoDiagnostics.record(this, "activity.startup.failed", error);
            throw error;
        }
    }

    private void initialize(Bundle state) {
        super.onCreate(state);
        QuangAutoDiagnostics.record(this, "activity.super.ready", null);
        setIgnoreConfigChanges(0xFFFFFFFF);
        // Optional host chrome must not prevent the main screen from opening.
        try {
            getCarUiController().getStatusBarController().hideAppHeader();
            getCarUiController().getMenuController().hideMenuButton();
        } catch (RuntimeException error) { QuangAutoDiagnostics.record(this, "host.chrome.failed", error); }
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.BLACK);
        status = new TextView(this);
        status.setTextColor(Color.WHITE);
        status.setPadding(12, 4, 12, 4);
        status.setVisibility(View.GONE);
        root.addView(status);
        content = new FrameLayout(this);
        root.addView(content, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root);
        QuangAutoDiagnostics.record(this, "activity.view.attached", null);
        try {
        getCarUiController().getSearchController().setSearchHint("Tìm trong QuangTube của Mây");
        getCarUiController().getSearchController().setSearchCallback(new SearchCallback() {
            @Override public void onSearchItemSelected(SearchItem item) {}
            @Override public void onSearchTextChanged(String text) {}
            @Override public boolean onSearchSubmitted(String text) {
                String query = text.trim();
                getCarUiController().getSearchController().stopSearch();
                Uri uri = Uri.parse(query);
                if ("https".equalsIgnoreCase(uri.getScheme()) || "http".equalsIgnoreCase(uri.getScheme())) {
                    String path = uri.getPath();
                    openWeb(query);
                } else {
                    if (web != null && web.getUrl() != null && Uri.parse(web.getUrl()).getPath().startsWith("/tube")) {
                        web.evaluateJavascript("(()=>{const q=document.getElementById('tube-query');const f=document.getElementById('tube-search');if(q&&f){q.value=" + JSONObject.quote(query) + ";q.dispatchEvent(new Event('input',{bubbles:true}));f.requestSubmit();}})()", null);
                    } else openWeb(YOUTUBE);
                }
                return true;
            }
        });
        } catch (RuntimeException error) { QuangAutoDiagnostics.record(this, "host.search.failed", error); }
        String initial = state == null ? null : state.getString("quangtv.auto.url");
        openWeb(initial == null ? MAY : initial);
        QuangAutoDiagnostics.record(this, "activity.native.ready", null);
    }

    private void openWeb(String url) {
        QuangAutoDiagnostics.record(this, "webview.open", null);
        try { createWeb(url); }
        catch (RuntimeException | LinkageError error) {
            QuangAutoDiagnostics.record(this, "webview.failed", error);
            if (status != null) { status.setText("Không mở được Mây. Mở QuangTV Auto – Chẩn đoán trên điện thoại."); status.setVisibility(View.VISIBLE); }
        }
    }

    private void createWeb(String url) {
        clearContent();
        web = new WebView(new android.view.ContextThemeWrapper(
                this, android.R.style.Theme_Material_NoActionBar));
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
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
                status.setVisibility(View.GONE);
                QuangAutoDiagnostics.record(QuangAutoActivity.this, "webview.page.ready", null);
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
        status.setVisibility(View.GONE);
        web.loadUrl(url);
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
        else if (web != null && !MAY.equals(web.getUrl())) openWeb(MAY);
        else super.onBackPressed();
    }

    private void clearContent() {
        leaveFullScreen();
        if (web != null) {
            web.onPause();
            web.stopLoading();
            if (web.getParent() instanceof ViewGroup) ((ViewGroup) web.getParent()).removeView(web);
            web.destroy();
            web = null;
        }
        if (content != null) content.removeAllViews();
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
