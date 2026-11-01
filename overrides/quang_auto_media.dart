import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../screens/quang_vtv_source.dart';

/// Uses the same public-only catalog exported for the projection screen.
Future<List<MediaItem>> quangAutoMediaItems({http.Client? client}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  // AA may start this service before any phone Activity has ever opened.
  // An explicitly saved empty list is respected; only an absent catalog bootstraps.
  if (!prefs.containsKey('quangtv_auto_channels')) {
    final transport = client ?? http.Client();
    try {
      final response = await transport.get(Uri.parse(QuangVtvSource.fallbackPlaylist))
          .timeout(const Duration(seconds: 7));
      if (response.statusCode == 200 && response.body.length <= 6000000) {
        final entries = <Map<String, String>>[];
        String title = '';
        for (final raw in response.body.split(RegExp(r'\r?\n'))) {
          final line = raw.trim();
          if (line.startsWith('#EXTINF:')) {
            title = line.contains(',') ? line.substring(line.indexOf(',') + 1).trim() : '';
          } else if (line.isNotEmpty && !line.startsWith('#')) {
            final uri = Uri.tryParse(line);
            if (title.isNotEmpty && uri != null && ['https', 'http'].contains(uri.scheme) && uri.host.isNotEmpty) {
              entries.add({'name': title, 'url': line});
            }
            title = '';
          }
        }
        if (entries.isNotEmpty) await prefs.setString('quangtv_auto_channels', jsonEncode(entries));
      }
    } catch (_) { /* A network failure must leave the catalog retryable. */ }
    finally { if (client == null) transport.close(); }
  }
  try {
    final entries = jsonDecode(prefs.getString('quangtv_auto_channels') ?? '[]') as List;
    final items = <String, MediaItem>{};
    for (final entry in entries) {
      if (entry is! Map) continue;
      final id = entry['url'];
      final title = entry['name'];
      if (id is! String || title is! String || title.trim().isEmpty) continue;
      final uri = Uri.tryParse(id);
      if (uri == null || !['https', 'http'].contains(uri.scheme) || uri.host.isEmpty) continue;
      items[id] = MediaItem(id: id, title: title, album: 'QuangTV Auto', playable: true);
    }
    return items.values.toList();
  } catch (_) {
    return [];
  }
}

/// Renew VTV's anonymous source for every play; never reuse expired signed URLs.
Future<List<String>> quangAutoPlaybackSources(MediaItem item, {http.Client? client}) async {
  if (QuangVtvSource.channelId(item.title) != null) {
    try {
      final fresh = await QuangVtvSource.resolve(item.title, client: client);
      if (fresh.isNotEmpty) return [...fresh, item.id];
    } catch (_) { /* Keep the public playlist URL as a last fallback. */ }
  }
  return [item.id];
}

Map<String, String> quangAutoPlaybackHeaders(MediaItem item) =>
    QuangVtvSource.channelId(item.title) == null ? const {} : QuangVtvSource.headers;
