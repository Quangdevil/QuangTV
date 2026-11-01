import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_viewer/services/quang_auto_media.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Media browser reads shared public catalog and ignores malformed entries', () async {
    SharedPreferences.setMockInitialValues({'quangtv_auto_channels': '[{"name":"VTV1","url":"https://example.com/live.m3u8"},{"name":"Duplicate","url":"https://example.com/live.m3u8"},{"name":"Local","url":"file:///secret"},{"url":9}]'});
    final items = await quangAutoMediaItems();
    expect(items, hasLength(1));
    expect(items.single.id, 'https://example.com/live.m3u8');
    expect(items.single.playable, true);
  });
  test('Empty and damaged catalog produce an empty browser list', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await quangAutoMediaItems(), isEmpty);
    SharedPreferences.setMockInitialValues({'quangtv_auto_channels': 'broken'});
    expect(await quangAutoMediaItems(), isEmpty);
  });
}
