import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uses the same public-only catalog exported for the projection screen.
Future<List<MediaItem>> quangAutoMediaItems() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
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
