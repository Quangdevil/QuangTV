package app.quangtv.autoprobe;

import android.app.Instrumentation;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.media.browse.MediaBrowser;
import android.media.session.MediaController;
import android.media.session.PlaybackState;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Independent UID: exercises the same public media IPC used by Android Auto.
 * It is deliberately not a replacement for Google's projection host. */
public final class AutoProbe extends Instrumentation {
    private Bundle args;
    private final CountDownLatch done = new CountDownLatch(1);
    private final Handler main = new Handler(Looper.getMainLooper());
    private String result = "TIMEOUT";
    private MediaBrowser browser;
    private MediaController controller;
    private ServiceConnection projection;
    private boolean projectionBound;
    private int phase;
    private boolean finished;
    @Override public void onCreate(Bundle args) { this.args = args; start(); }
    @Override public void onStart() {
        main.post(this::connect);
        try { done.await(65, TimeUnit.SECONDS); }
        catch (InterruptedException e) { result = e.toString(); }
        main.post(() -> {
            if (browser != null) browser.disconnect();
            if (projectionBound) getContext().unbindService(projection);
        });
        Bundle output = new Bundle();
        output.putString("stream", "\nQUANGTV_AUTO_PROBE " + result + "\n");
        output.putBoolean("passed", result.startsWith("PASS"));
        finish(result.startsWith("PASS") ? -1 : 0, output);
    }
    private void complete(String text) {
        if (finished) return;
        finished = true; result = text; done.countDown();
    }
    private boolean rejectedExpected() { return "rejected".equals(args.getString("expect")); }
    private void connect() {
        try {
            browser = new MediaBrowser(getContext(), new ComponentName(
                "com.quangduren.quangtv.autopreview2", "com.ryanheise.audioservice.AudioService"),
                new MediaBrowser.ConnectionCallback() {
                    @Override public void onConnectionFailed() {
                        complete(rejectedExpected() ? "PASS expected-private-service-rejection" : "FAIL media-connection-rejected");
                    }
                    @Override public void onConnected() {
                        if (rejectedExpected()) { complete("FAIL private-service-unexpectedly-connected"); return; }
                        try {
                            controller = new MediaController(getContext(), browser.getSessionToken());
                            controller.registerCallback(new MediaController.Callback() {
                                @Override public void onPlaybackStateChanged(PlaybackState state) {
                                    if (state == null) return;
                                    if (state.getState() == PlaybackState.STATE_ERROR) { complete("FAIL playback-error " + state.getErrorMessage()); return; }
                                    if (phase == 1 && state.getState() == PlaybackState.STATE_PLAYING) {
                                        phase = 2;
                                        main.postDelayed(() -> controller.getTransportControls().pause(), 2000);
                                    } else if (phase == 2 && state.getState() == PlaybackState.STATE_PAUSED) {
                                        phase = 3; controller.getTransportControls().stop();
                                    } else if (phase == 3 && (state.getState() == PlaybackState.STATE_NONE || state.getState() == PlaybackState.STATE_STOPPED)) {
                                        testProjectionBinding();
                                    }
                                }
                            }, main);
                            browser.subscribe(browser.getRoot(), new MediaBrowser.SubscriptionCallback() {
                                @Override public void onChildrenLoaded(String id, List<MediaBrowser.MediaItem> children) {
                                    if (phase != 0) return;
                                    for (MediaBrowser.MediaItem item : children) {
                                        if ("QA tone".contentEquals(item.getDescription().getTitle())) {
                                            phase = 1;
                                            controller.getTransportControls().playFromMediaId(item.getMediaId(), null);
                                            return;
                                        }
                                    }
                                    complete("FAIL public-fixture-channel-missing count=" + children.size());
                                }
                                @Override public void onError(String id) { complete("FAIL browse-error"); }
                            });
                        } catch (Exception e) { complete("FAIL connected-exception " + e); }
                    }
                }, null);
            browser.connect();
        } catch (SecurityException e) {
            complete(rejectedExpected() ? "PASS expected-permission-denial" : "FAIL permission-denial " + e);
        } catch (Exception e) { complete("FAIL connect-exception " + e); }
    }
    private void testProjectionBinding() {
        projection = new ServiceConnection() {
            @Override public void onServiceConnected(ComponentName name, IBinder service) {
                complete("PASS media-connected public-catalog play-pause-stop projection-service-bound; GOOGLE_HOST_UI_NOT_TESTED");
            }
            @Override public void onServiceDisconnected(ComponentName name) {}
            @Override public void onNullBinding(ComponentName name) { complete("FAIL projection-null-binding; media-controls-passed"); }
        };
        try {
            Intent intent = new Intent(Intent.ACTION_MAIN).setComponent(new ComponentName(
                "com.quangduren.quangtv.autopreview2", "app.tvviewer.player.QuangAutoService"));
            projectionBound = getContext().bindService(intent, projection, Context.BIND_AUTO_CREATE);
            if (!projectionBound) complete("FAIL projection-bind-false; media-controls-passed");
        } catch (Exception e) { complete("FAIL projection-bind-exception " + e); }
    }
}
