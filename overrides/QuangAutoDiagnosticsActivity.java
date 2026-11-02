package app.tvviewer.player;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.widget.*;

/** Phone entry point for retrieving a failed car startup without ADB. */
public final class QuangAutoDiagnosticsActivity extends Activity {
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        TextView report = new TextView(this);
        String trail = getSharedPreferences("quangtv_auto_diagnostics", 0).getString("trail", "Chưa ghi nhận phần Mây · Video khởi chạy. Mở mục Âm thanh không tạo dấu vết này.");
        String installSource;
        try {
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                android.content.pm.InstallSourceInfo info = getPackageManager().getInstallSourceInfo(getPackageName());
                installSource = "Initiating installer: " + info.getInitiatingPackageName()
                        + "\nRecorded installer: " + info.getInstallingPackageName();
            } else installSource = "Installer: " + getPackageManager().getInstallerPackageName(getPackageName());
        } catch (Exception error) { installSource = "Không đọc được nguồn cài: " + error.getClass().getSimpleName(); }
        String version;
        try { android.content.pm.PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0); version = info.versionName + " (" + (android.os.Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode) + ")"; }
        catch (Exception ignored) { version = "?"; }
        String text = "QuangTV Auto – Chẩn đoán\n" + getPackageName() + " · " + version
                + "\n" + installSource + "\nAndroid " + android.os.Build.VERSION.RELEASE
                + " · " + android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL + "\n\n" + trail;
        report.setText(text);
        report.setTextIsSelectable(true);
        report.setPadding(20, 20, 20, 20);
        Button share = new Button(this);
        share.setText("Chia sẻ lỗi");
        share.setOnClickListener(v -> startActivity(Intent.createChooser(
                new Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), "Gửi chẩn đoán")));
        layout.addView(share);
        ScrollView scroll = new ScrollView(this);
        scroll.addView(report);
        layout.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(layout);
    }
}
