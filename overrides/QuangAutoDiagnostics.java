package app.tvviewer.player;

import android.content.Context;
import android.util.Log;

/** Small local startup trail. No URLs, cookies, channel lists or remote upload. */
public final class QuangAutoDiagnostics {
    public static synchronized void record(Context context, String stage, Throwable error) {
        String entry = new java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.ROOT)
                .format(new java.util.Date()) + " " + stage;
        if (error != null) entry += "\n" + Log.getStackTraceString(error);
        Log.i("QuangAuto", entry);
        try {
            android.content.SharedPreferences prefs = context.getApplicationContext()
                    .getSharedPreferences("quangtv_auto_diagnostics", 0);
            String prior = prefs.getString("trail", "");
            String trail = prior + "\n" + entry;
            if (trail.length() > 28000) trail = trail.substring(trail.length() - 28000);
            // Persist before the process can terminate; startup events only.
            prefs.edit().putString("trail", trail).commit();
        } catch (RuntimeException ignored) { Log.e("QuangAuto", "Could not save startup trail", ignored); }
    }
    private QuangAutoDiagnostics() {}
}
