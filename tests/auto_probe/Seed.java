package app.quangtv.autoprobe;
import android.app.Instrumentation;
import android.content.Context;
import android.os.Bundle;
/** Signed with the preview test key; seeds only deterministic test preferences. */
public final class Seed extends Instrumentation {
    @Override public void onCreate(Bundle args) { start(); }
    @Override public void onStart() {
        Context c = getTargetContext();
        String channels = "[{\"name\":\"QA tone\",\"url\":\"http://10.0.2.2:8765/audio.wav\"}]";
        boolean ok = c.getSharedPreferences("FlutterSharedPreferences", 0).edit()
            .putString("flutter.quangtv_auto_channels", channels)
            .putString("flutter.quangtv_cached_channels", channels).commit();
        Bundle result = new Bundle();
        result.putString("stream", ok ? "QUANGTV_FIXTURE_SEEDED\n" : "SEED_FAILED\n");
        finish(ok ? -1 : 0, result);
    }
}
