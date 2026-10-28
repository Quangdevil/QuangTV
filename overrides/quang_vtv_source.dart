import 'dart:convert';
import 'package:http/http.dart' as http;

/// Resolve only VTVgo's anonymous, free, unencrypted live sources.
/// Signed CDN URLs stay in memory and are renewed each time a channel opens.
class QuangVtvSource {
  static const headers = <String, String>{
    'User-Agent': 'Mozilla/5.0',
    'Referer': 'https://vtvgo.vn/',
    'Origin': 'https://vtvgo.vn',
  };
  static const ids = {
    'VTV10': '6', 'VTV1': '1', 'VTV2': '2', 'VTV3': '3',
    'VTV4': '4', 'VTV5': '5', 'VTV6': '13', 'VTV7': '27',
    'VTV8': '36', 'VTV9': '39',
  };

  static String? channelId(String name) {
    final upper = name.toUpperCase();
    final compact = upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (compact.startsWith('VTV5')) {
      if (upper.contains('TÂY NGUYÊN') || upper.contains('TAY NGUYEN')) return '163';
      if (upper.contains('TÂY NAM BỘ') || upper.contains('TAY NAM BO')) return '7';
    }
    for (final entry in ids.entries) {
      if (compact.startsWith(entry.key) &&
          (compact.length == entry.key.length ||
           !RegExp(r'[0-9]').hasMatch(compact[entry.key.length]))) return entry.value;
    }
    return null;
  }

  static Future<List<String>> resolve(String name, {http.Client? client}) async {
    final id = channelId(name);
    if (id == null) return const [];
    final owned = client == null;
    final transport = client ?? http.Client();
    try {
      final response = await transport.post(
        Uri.parse('https://api.vtvdigital.org/live-channel/v21.0/playback/source'),
        headers: {...headers, 'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'channelId': id, 'platform': 'webAndroid'}),
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) throw StateError('VTVgo HTTP ${response.statusCode}');
      return parse(jsonDecode(response.body));
    } finally {
      if (owned) transport.close();
    }
  }

  static List<String> parse(dynamic response) {
    final data = response is Map ? response['data'] : null;
    final modes = data is Map ? data['sourceModes'] : null;
    final urls = <String>{};
    if (modes is List) {
      for (final mode in modes.whereType<Map>()) {
        if (mode['isVip'] != 0 || mode['multiSource'] is! List) continue;
        for (final source in (mode['multiSource'] as List).whereType<Map>()) {
          if (source['manifestType'] != 'hls' || source['drmTypeID'] != 'none' || source['sources'] is! List) continue;
          for (final item in (source['sources'] as List).whereType<Map>()) {
            final uri = Uri.tryParse(item['url'] is String ? item['url'] as String : '');
            if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty) urls.add(uri.toString());
          }
        }
      }
    }
    if (urls.isEmpty) throw StateError('VTVgo chưa cung cấp nguồn miễn phí phù hợp');
    return urls.toList();
  }
}
