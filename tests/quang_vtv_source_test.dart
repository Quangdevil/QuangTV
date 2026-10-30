import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_viewer/screens/quang_vtv_source.dart';

void main() {
  Map<String, dynamic> fixture(String url) => {'data': {'sourceModes': [
    {'id': 'default', 'isVip': 0, 'multiSource': [
      {'manifestType': 'hls', 'drmTypeID': 'none', 'sources': [{'url': url}]},
      {'manifestType': 'hls', 'drmTypeID': 'widevine', 'sources': [{'url': 'https://example.org/drm.m3u8'}]},
    ]},
    {'isVip': 1, 'multiSource': [
      {'manifestType': 'hls', 'drmTypeID': 'none', 'sources': [{'url': 'https://example.org/paid.m3u8'}]},
    ]},
  ]}};

  test('VTVgo returns only anonymous free HLS, preserving signed query', () {
    const url = 'https://example.org/live.m3u8?hdnts=exp=123~acl=/live/*~hmac=abc';
    expect(QuangVtvSource.parse(fixture(url)), [url]);
    expect(() => QuangVtvSource.parse({'data': {'sourceModes': []}}), throwsStateError);
  });

  test('Each channel open obtains a fresh URL; no login credentials sent', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.host, 'api.vtvdigital.org');
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {'channelId': '3', 'platform': 'webAndroid'});
      expect(request.headers.keys.map((key) => key.toLowerCase()), isNot(contains('authorization')));
      return http.Response(jsonEncode(fixture('https://example.org/live-$calls.m3u8')), 200);
    });
    expect(await QuangVtvSource.resolve('VTV3 HD', client: client), ['https://example.org/live-1.m3u8']);
    expect(await QuangVtvSource.resolve('VTV3 HD', client: client), ['https://example.org/live-2.m3u8']);
    client.close();
  });

  test('Channel variants resolve correctly and HTTP rejection is explicit', () async {
    expect(QuangVtvSource.channelId('VTV10 HD'), '6');
    expect(QuangVtvSource.channelId('VTV7'), '27');
    expect(QuangVtvSource.channelId('VTV5 Tây Nguyên'), '163');
    expect(QuangVtvSource.channelId('VTV5 Tây Nam Bộ'), '7');
    expect(QuangVtvSource.channelId('VTV11'), isNull);
    expect(QuangVtvSource.channelId('Private channel'), isNull);
    final client = MockClient((_) async => http.Response('Forbidden', 403));
    await expectLater(QuangVtvSource.resolve('VTV1', client: client), throwsStateError);
    client.close();
  });
  test('IPTV fallback matches the exact channel and excludes protected or incompatible entries', () {
    const text = '#EXTM3U\n'
        '#EXTINF:-1,VTV3 HD\nhttps://cdn.example.org/vtv3.m3u8\n'
        '#EXTINF:-1,VTV30\nhttps://cdn.example.org/wrong.m3u8\n'
        '#EXTINF:-1,VTV3\n#EXTHTTP:{"Cookie":"secret"}\nhttps://cdn.example.org/header.m3u8\n'
        '#EXTINF:-1,VTV3\nhttps://cdn.example.org/secret.m3u8?token=secret\n'
        '#EXTINF:-1,VTV3\n#KODIPROP:inputstream.adaptive.license_type=widevine\nhttps://cdn.example.org/drm.m3u8\n'
        '#EXTINF:-1,VTV3\nhttp://cdn.example.org/plain.m3u8\n'
        '#EXTINF:-1,VTV3\nhttps://live.vtvdigital.vn/master.m3u8\n'
        '#EXTINF:-1,VTV5 Tay Nam Bo HD\nhttps://cdn.example.org/tnb.m3u8\n'
        '#EXTINF:-1,VTV5 HD\nhttps://cdn.example.org/vtv5.m3u8\n';
    expect(QuangVtvSource.parseFallbackPlaylist(text, 'VTV3'), ['https://cdn.example.org/vtv3.m3u8']);
    expect(QuangVtvSource.parseFallbackPlaylist(text, 'VTV5 Tây Nam Bộ'), ['https://cdn.example.org/tnb.m3u8']);
    expect(QuangVtvSource.parseFallbackPlaylist(text, 'VTV5'), ['https://cdn.example.org/vtv5.m3u8']);
    expect(QuangVtvSource.parseFallbackPlaylist(text, 'VTV11'), isEmpty);
  });

  test('fallback fetch is explicit, bounded, shared and cached; never forwards VTV headers', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.toString(), QuangVtvSource.fallbackPlaylist);
      expect(request.method, 'GET');
      expect(request.headers.keys.map((key) => key.toLowerCase()), isNot(contains('cookie')));
      expect(request.headers.keys.map((key) => key.toLowerCase()), isNot(contains('referer')));
      return http.Response('#EXTM3U\n#EXTINF:-1,VTV3 HD\nhttps://cdn.example.org/3.m3u8\n#EXTINF:-1,VTV1\nhttps://cdn.example.org/1.m3u8\n', 200);
    });
    expect(calls, 0);
    final both = await Future.wait([
      QuangVtvSource.resolveFallback('VTV3', client: client),
      QuangVtvSource.resolveFallback('VTV1', client: client),
    ]);
    expect(calls, 1);
    expect(both[0], ['https://cdn.example.org/3.m3u8']);
    expect(both[1], ['https://cdn.example.org/1.m3u8']);
    expect(await QuangVtvSource.resolveFallback('VTV3', client: client), both[0]);
    expect(calls, 1);
    client.close();
  });

}
