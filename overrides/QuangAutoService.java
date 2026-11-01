package app.tvviewer.player;

import com.google.android.apps.auto.sdk.CarActivity;
import com.google.android.apps.auto.sdk.CarActivityService;

/** Android Auto projection entry point, hosted by Android Auto on the phone. */
public final class QuangAutoService extends CarActivityService {
    @Override public Class<? extends CarActivity> getCarActivity() {
        return QuangAutoActivity.class;
    }
}
