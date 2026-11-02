import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Export only public, non-deleted channels to the native car host.
Future<void> syncQuangAutoChannels(SharedPreferences prefs) async {
  final privateUrls = <String>{};
  final deleted = (prefs.getStringList('quangtv_deleted_channels') ?? []).toSet();
  for (final raw in prefs.getStringList('quangtv_private_channels') ?? <String>[]) {
    try { privateUrls.add((jsonDecode(raw) as Map<String, dynamic>)['url'] as String); } catch (_) {}
  }
  final public = <String, Map<String, dynamic>>{};
  final entries = <dynamic>[];
  try { entries.addAll(jsonDecode(prefs.getString('quangtv_cached_channels') ?? '[]') as List); } catch (_) {}
  for (final raw in prefs.getStringList('quangtv_personal_channels') ?? <String>[]) {
    try { entries.add(jsonDecode(raw)); } catch (_) {}
  }
  for (final entry in entries) {
    if (entry is! Map) continue;
    final url = entry['url'];
    final name = entry['name'];
    if (url is! String || name is! String || privateUrls.contains(url) || deleted.contains(url)) continue;
    final uri = Uri.tryParse(url);
    if (uri == null || !['https', 'http'].contains(uri.scheme)) continue;
    public[url] = {'name': name, 'url': url};
  }
  await prefs.setString('quangtv_auto_channels', jsonEncode(public.values.toList()));
}
