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
           !RegExp(r'[0-9]').hasMatch(compact[entry.key.length]))) {
        return entry.value;
      }
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
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw StateError('VTVgo HTTP ${response.statusCode}');
      return parse(jsonDecode(response.body));
    } finally {
      if (owned) transport.close();
    }
  }

  // Shared default with Discover/Mây. Never fetch this on successful VTVgo startup.
  static const fallbackPlaylist = 'https://iptv-org.github.io/iptv/countries/vn.m3u';
  static String? _fallbackText;
  static DateTime? _fallbackAt;
  static Future<String>? _fallbackPending;

  static List<String> parseFallbackPlaylist(String text, String name) {
    final id = channelId(name);
    if (id == null) return const [];
    final urls = <String>{};
    String? entryName;
    var restricted = false;
    for (final raw in const LineSplitter().convert(text.replaceFirst('\uFEFF', ''))) {
      final line = raw.trim();
      if (line.startsWith('#EXTINF:')) {
        final comma = line.indexOf(RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*$)'));
        entryName = comma < 0 ? null : line.substring(comma + 1).trim();
        restricted = false;
      } else if (line.startsWith('#EXTHTTP:') || line.startsWith('#EXTVLCOPT:') || line.startsWith('#KODIPROP:')) {
        restricted = true;
      } else if (line.isNotEmpty && !line.startsWith('#') && entryName != null) {
        final uri = Uri.tryParse(line);
        if (!restricted && channelId(entryName) == id && uri != null &&
            uri.scheme == 'https' && uri.host.contains('.') && !uri.host.endsWith('.') &&
            uri.userInfo.isEmpty && !uri.hasPort &&
            !RegExp(r'^[0-9.]+$').hasMatch(uri.host) &&
            !RegExp(r'(?:^|\.)(?:localhost|local|internal|lan|home|test|invalid)$').hasMatch(uri.host) &&
            !RegExp(r'(?:^|\.)(?:vtvdigital\.vn|vtvdigital\.org|vtvgo\.vn)$').hasMatch(uri.host) &&
            uri.path.toLowerCase().endsWith('.m3u8') &&
            !uri.queryParameters.keys.any((key) => RegExp(r'^(?:token|access_token|auth|authorization|api_key|apikey|key|signature|sig|hdnts|hdnea|session|jwt|password|secret)$', caseSensitive: false).hasMatch(key))) {
          urls.add(line);
          if (urls.length == 4) break;
        }
        entryName = null;
      }
    }
    return urls.toList();
  }

  static Future<List<String>> resolveFallback(String name, {http.Client? client}) async {
    if (channelId(name) == null) return const [];
    Future<String> load() async {
      final owned = client == null;
      final transport = client ?? http.Client();
      try {
        final request = http.Request('GET', Uri.parse(fallbackPlaylist))..followRedirects = false;
        final response = await transport.send(request).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) throw StateError('IPTV playlist HTTP ${response.statusCode}');
        final bytes = <int>[];
        await for (final chunk in response.stream.timeout(const Duration(seconds: 8))) {
          if (bytes.length + chunk.length > 2000000) throw StateError('IPTV playlist too large');
          bytes.addAll(chunk);
        }
        final text = utf8.decode(bytes, allowMalformed: true);
        if (!text.trimLeft().startsWith('#EXTM3U')) throw StateError('Invalid IPTV playlist');
        _fallbackText = text;
        _fallbackAt = DateTime.now();
        return text;
      } finally {
        if (owned) transport.close();
      }
    }
    final warm = _fallbackText != null && _fallbackAt != null && DateTime.now().difference(_fallbackAt!).inMinutes < 10;
    if (warm) return parseFallbackPlaylist(_fallbackText!, name);
    final pending = _fallbackPending ??= load();
    try {
      return parseFallbackPlaylist(await pending, name);
    } finally {
      if (identical(_fallbackPending, pending)) _fallbackPending = null;
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
    // Prefer the official Akamai delivery path verified with real H.264/AAC.
    // Keep other API-provided CDNs as fallbacks; never persist signed URLs.
    final ordered = urls.toList();
    int rank(String url) => Uri.parse(url).host.endsWith('.akamaized.net') ? 0 : 1;
    ordered.sort((a, b) => rank(a).compareTo(rank(b)));
    return ordered;
  }
}
