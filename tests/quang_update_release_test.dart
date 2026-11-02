import 'package:flutter_test/flutter_test.dart';
import 'package:tv_viewer/screens/quang_update_release.dart';

Map<String, dynamic> release(String tag, {bool preview = false, String? asset}) {
  final name = asset ?? (preview ? 'QuangTV-Auto-Preview2-build8-arm64.apk' : 'QuangTV-v1.3.0-build999-arm64.apk');
  return {'tag_name': tag, 'prerelease': preview, 'assets': [
    {'name': name, 'browser_download_url': 'https://github.com/Quangdevil/QuangTV/releases/download/$tag/$name'}
  ]};
}

void main() {
  test('Preview 2 selects its own newest build among mixed releases', () {
    final data = [release('quangtv-v1.3.0-build999'), release('auto-preview2-build7', preview: true), release('auto-preview2-build8', preview: true), release('auto-preview-build90', preview: true)];
    final chosen = selectUpdateRelease(data, autoPreview2Package);
    expect(releaseBuild(chosen), 8);
    expect(selectUpdateApk(chosen, autoPreview2Package)['name'], startsWith('QuangTV-Auto-Preview2-'));
    expect(updateEndpoint(autoPreview2Package), contains('/releases?'));
  });
  test('Production excludes preview and diagnostic prereleases', () {
    final data = [release('auto-preview2-build9999', preview: true), release('quangtv-v1.3.0-vtv-test-build9998', preview: true), release('quangtv-v1.3.0-build999')];
    expect(releaseBuild(selectUpdateRelease(data, 'com.quangduren.quangtv')), 999);
  });
  test('Missing preview does not fall back to production', () {
    expect(() => selectUpdateRelease([release('quangtv-v1.3.0-build999')], autoPreview2Package), throwsException);
  });
  test('Wrong APK package channel and off-repository URLs are rejected', () {
    final wrong = release('auto-preview2-build8', preview: true, asset: 'QuangTV-v1.3.0-build999-arm64.apk');
    expect(() => selectUpdateApk(wrong, autoPreview2Package), throwsException);
    final changed = release('auto-preview2-build8', preview: true);
    (changed['assets'] as List).first['browser_download_url'] = 'https://example.com/fake.apk';
    expect(() => selectUpdateApk(changed, autoPreview2Package), throwsException);
  });
}
