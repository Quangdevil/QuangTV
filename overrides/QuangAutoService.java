package app.tvviewer.player;

import com.google.android.apps.auto.sdk.CarActivity;
import com.google.android.apps.auto.sdk.CarActivityService;

/** Android Auto projection entry point, hosted by Android Auto on the phone. */
public final class QuangAutoService extends CarActivityService {
    @Override public void onCreate() {
        QuangAutoDiagnostics.record(this, "service.onCreate", null);
        Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread, error) -> {
            QuangAutoDiagnostics.record(this, "process.uncaught", error);
            if (previous != null) previous.uncaughtException(thread, error);
        });
        try { super.onCreate(); }
        catch (RuntimeException | LinkageError error) {
            QuangAutoDiagnostics.record(this, "service.startup.failed", error);
            throw error;
        }
    }
    @Override public Class<? extends CarActivity> getCarActivity() {
        QuangAutoDiagnostics.record(this, "service.getCarActivity", null);
        return QuangAutoActivity.class;
    }
}
