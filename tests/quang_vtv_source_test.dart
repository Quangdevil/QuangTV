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
}
