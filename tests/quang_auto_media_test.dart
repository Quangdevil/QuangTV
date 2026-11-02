import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audio_service/audio_service.dart';
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
  test('Cold AA start fetches public catalog without a phone Activity and caches it', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.toString(), 'https://iptv-org.github.io/iptv/countries/vn.m3u');
      return http.Response('#EXTM3U\n#EXTINF:-1,VTV1\nhttps://example.com/live.m3u8\n#EXTINF:-1,Local\nfile:///private', 200);
    });
    final items = await quangAutoMediaItems(client: client);
    expect(items.map((i) => i.title), ['VTV1']);
    expect(await quangAutoMediaItems(client: client), hasLength(1));
    expect(calls, 1);
  });
  test('Failed bootstrap remains retryable', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await quangAutoMediaItems(client: MockClient((_) async => http.Response('', 503))), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('quangtv_auto_channels'), false);
  });
  test('VTV playback requests fresh sources while ordinary public URLs stay unchanged', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.method, 'POST');
      expect(jsonDecode(request.body)['channelId'], '1');
      return http.Response('{}', 503);
    });
    final vtv = MediaItem(id: 'https://example.com/old.m3u8', title: 'VTV1 HD');
    expect(await quangAutoPlaybackSources(vtv, client: client), [vtv.id]);
    expect(calls, 1);
    final other = MediaItem(id: 'https://example.com/radio', title: 'Radio');
    expect(await quangAutoPlaybackSources(other, client: client), [other.id]);
    expect(calls, 1);
    expect(quangAutoPlaybackHeaders(vtv)['Referer'], 'https://vtvgo.vn/');
  });
  test('Empty and damaged catalog produce an empty browser list', () async {
    SharedPreferences.setMockInitialValues({'quangtv_auto_channels': '[]'});
    expect(await quangAutoMediaItems(), isEmpty);
    SharedPreferences.setMockInitialValues({'quangtv_auto_channels': 'broken'});
    expect(await quangAutoMediaItems(), isEmpty);
  });
}
