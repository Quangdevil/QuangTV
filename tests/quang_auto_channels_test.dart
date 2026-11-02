import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/screens/quang_auto_channels.dart';

void main() {
  test('car list excludes private/deleted sources and keeps personal channels', () async {
    SharedPreferences.setMockInitialValues({
      'quangtv_cached_channels': jsonEncode([
        {'name': 'Public', 'url': 'https://example.org/public.m3u8'},
        {'name': 'Hidden', 'url': 'https://example.org/private.m3u8'},
        {'name': 'Removed', 'url': 'https://example.org/deleted.m3u8'},
        {'name': 'Invalid', 'url': 'file:///private/video.mp4'},
      ]),
      'quangtv_private_channels': [jsonEncode({'name': 'Private', 'url': 'https://example.org/private.m3u8'})],
      'quangtv_deleted_channels': ['https://example.org/deleted.m3u8'],
      'quangtv_personal_channels': [jsonEncode({'name': 'Personal', 'url': 'https://example.org/personal.m3u8'})],
    });
    final prefs = await SharedPreferences.getInstance();
    await syncQuangAutoChannels(prefs);
    final exported = jsonDecode(prefs.getString('quangtv_auto_channels')!) as List;
    expect(exported.map((e) => e['name']), ['Public', 'Personal']);
    // A later private edit must remove an already exported public source.
    await prefs.setStringList('quangtv_private_channels', [jsonEncode({'name': 'Public now private', 'url': 'https://example.org/public.m3u8'})]);
    await syncQuangAutoChannels(prefs);
    expect((jsonDecode(prefs.getString('quangtv_auto_channels')!) as List).map((e) => e['name']), ['Hidden', 'Personal']);
  });
}
