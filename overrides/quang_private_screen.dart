import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel.dart';
import 'quang_native_player.dart';

class QuangPrivateSecurity {
  static const pinKey = 'quangtv_pin_hash';
  static String digest(String pin) => sha256.convert(utf8.encode('quangtv-pin-v1:$pin')).toString();
  static bool valid(String pin) => pin.length >= 4 && pin.split('').every((c) => '0123456789'.contains(c));
  static Future<String?> prompt(BuildContext context, String title) async {
    final input = TextEditingController();
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: input, autofocus: true, obscureText: true, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'PIN (ít nhất 4 chữ số)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(ctx, input.text.trim()), child: const Text('Xác nhận')),
      ],
    ));
    input.dispose();
    return result;
  }
  static Future<bool> verify(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(pinKey);
    if (stored == null) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hãy đặt PIN tại Cài đặt trước khi vào Private')));
      return false;
    }
    if (!context.mounted) return false;
    final pin = await prompt(context, 'Mở Private');
    if (pin == null) return false;
    if (digest(pin) == stored) return true;
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN không đúng')));
    return false;
  }
  static Future<void> configure(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(pinKey);
    if (stored != null) {
      if (!context.mounted) return;
      final old = await prompt(context, 'Xác thực PIN hiện tại');
      if (old == null || digest(old) != stored) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN hiện tại không đúng')));
        return;
      }
    }
    if (!context.mounted) return;
    final next = await prompt(context, stored == null ? 'Đặt PIN Private' : 'Đổi PIN Private');
    if (next == null) return;
    if (!valid(next)) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN phải có ít nhất 4 chữ số')));
      return;
    }
    if (!context.mounted) return;
    final again = await prompt(context, 'Nhập lại PIN mới');
    if (again != next) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN xác nhận không khớp')));
      return;
    }
    await prefs.setString(pinKey, digest(next));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu PIN Private')));
  }
}

class QuangPrivateScreen extends StatefulWidget {
  const QuangPrivateScreen({super.key});
  @override
  State<QuangPrivateScreen> createState() => _QuangPrivateScreenState();
}

class _QuangPrivateScreenState extends State<QuangPrivateScreen> {
  static const key = 'quangtv_private_channels';
  final search = TextEditingController();
  final url = TextEditingController();
  final name = TextEditingController();
  List<Channel> channels = [];
  bool ready = false;
  bool importing = false;
  static const playlistKey = 'quangtv_private_playlists';
  List<String> playlistUrls = [];
  @override
  void initState() { super.initState(); _restore(); }
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = <Channel>[];
    for (final entry in prefs.getStringList(key) ?? <String>[]) {
      try {
        final item = jsonDecode(entry) as Map<String, dynamic>;
        final uri = Uri.tryParse(item['url'] as String);
        if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
          loaded.add(Channel(name: item['name'] as String, url: item['url'] as String, country: 'Private'));
        }
      } catch (_) {}
    }
    playlistUrls = prefs.getStringList(playlistKey) ?? <String>[];
    if (mounted) setState(() { channels = loaded; ready = true; });
  }
  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, channels.map((c) => jsonEncode({'name': c.name, 'url': c.url})).toList());
  }
  Future<void> _add() async {
    name.clear(); url.clear();
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Thêm kênh Private'),
      scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Tên kênh')),
        TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'URL phát HTTP/HTTPS')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu')),
      ],
    ));
    if (accepted != true || !mounted) return;
    final uri = Uri.tryParse(url.text.trim());
    if (name.text.trim().isEmpty || uri == null || !['https', 'http'].contains(uri.scheme) || uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tên hoặc URL không hợp lệ')));
      return;
    }
    setState(() {
      channels.removeWhere((c) => c.url == uri.toString());
      channels.add(Channel(name: name.text.trim(), url: uri.toString(), country: 'Private'));
    });
    await _persist();
  }
  Future<List<Channel>> _parsePrivateM3u(String body) async {
    final result = <Channel>[];
    String title = '';
    final headers = <String, String>{};
    final prefs = await SharedPreferences.getInstance();
    for (final raw in body.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.startsWith('#EXTINF:')) {
        title = line.contains(',') ? line.substring(line.indexOf(',') + 1).trim() : 'Kênh TV';
      } else if (line.startsWith('#EXTVLCOPT:http-user-agent=')) {
        headers['User-Agent'] = line.substring('#EXTVLCOPT:http-user-agent='.length).trim();
      } else if (line.startsWith('#EXTVLCOPT:http-referrer=')) {
        headers['Referer'] = line.substring('#EXTVLCOPT:http-referrer='.length).trim();
      } else if (line.startsWith('#EXTHTTP:')) {
        try {
          final data = jsonDecode(line.substring('#EXTHTTP:'.length)) as Map<String, dynamic>;
          for (final key in ['User-Agent', 'Referer', 'Cookie', 'Authorization']) {
            if (data[key] is String) headers[key] = data[key] as String;
          }
        } catch (_) {}
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        final stream = Uri.tryParse(line);
        if (stream != null && (stream.scheme == 'https' || stream.scheme == 'http')) {
          result.add(Channel(name: title.isEmpty ? 'Kênh TV' : title, url: line, country: 'Private'));
          if (headers.isNotEmpty) await prefs.setString('quangtv_headers_${base64Url.encode(utf8.encode(line))}', jsonEncode(headers));
        }
        title = '';
        headers.clear();
      }
    }
    return result;
  }

  Future<void> _importPlaylist({String? sourceUrl}) async {
    final controller = TextEditingController();
    final entered = sourceUrl ?? await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Nhập danh sách M3U Private'),
      content: TextField(controller: controller, keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: 'URL danh sách .m3u / .m3u8')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Tải kênh')),
      ],
    ));
    controller.dispose();
    if (entered == null || !mounted) return;
    final uri = Uri.tryParse(entered);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chỉ hỗ trợ liên kết HTTP hoặc HTTPS hợp lệ')));
      return;
    }
    setState(() => importing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      List<Channel> parsed = [];
      String? networkError;
      try {
        final response = await http.get(uri).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) throw Exception('Máy chủ trả HTTP ${response.statusCode}');
        if (response.body.length > 6000000) throw Exception('Danh sách quá lớn (trên 6 MB)');
        parsed = await _parsePrivateM3u(response.body);
        if (parsed.isEmpty) throw Exception('Máy chủ phản hồi nhưng không tìm thấy URL kênh trong M3U');
      } catch (e) {
        // Do not expose IPTV credentials embedded in URLs in error messages.
        final msg = e.toString();
        if (msg.contains('TimeoutException')) {
          networkError = 'Kết nối quá 20 giây';
        } else if (msg.contains('HTTP ')) {
          networkError = msg;
        } else if (msg.contains('không tìm thấy URL kênh') || msg.contains('quá lớn')) {
          networkError = msg;
        } else {
          networkError = 'Lỗi kết nối hoặc định dạng phản hồi (${e.runtimeType})';
        }
        // Public TV can display its cached channels while offline. Allow Private
        // to import that same cached source, but persist it only in Private storage.
        if (prefs.getString('quangtv_playlist') == entered) {
          final cached = prefs.getString('quangtv_cached_channels');
          if (cached != null) {
            try {
              final items = jsonDecode(cached) as List<dynamic>;
              parsed = items.map((item) => Channel(
                name: item['name'] as String,
                url: item['url'] as String,
                country: 'Private',
              )).toList();
            } catch (_) {}
          }
        }
        if (parsed.isEmpty) throw Exception(networkError);
      }
      if (!mounted) return;
      setState(() {
        final existing = channels.map((c) => c.url).toSet();
        for (final channel in parsed) {
          if (existing.add(channel.url)) channels.add(channel);
        }
      });
      if (!playlistUrls.contains(entered)) playlistUrls.add(entered);
      await _persist();
      await prefs.setStringList(playlistKey, playlistUrls);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã nhập ${parsed.length} kênh vào Private${networkError == null ? '' : ' (từ bộ nhớ TV)'}')));
    } catch (e) {
      if (mounted) await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('Không tải được M3U Private'), content: SelectableText(e.toString().replaceFirst('Exception: ', '')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))]));
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> _refreshPlaylists() async {
    if (importing) return;
    if (playlistUrls.isEmpty) {
      await _importPlaylist();
      return;
    }
    // Refresh each saved source. Imported channels remain available on failure.
    for (final source in List<String>.from(playlistUrls)) {
      if (!mounted) return;
      await _importPlaylist(sourceUrl: source);
    }
  }

  Future<void> _delete(Channel c) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Xóa kênh Private?'), content: Text(c.name),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa'))]));
    if (confirmed != true || !mounted) return;
    setState(() => channels.removeWhere((item) => item.url == c.url));
    await _persist();
  }
  @override
  void dispose() { search.dispose(); url.dispose(); name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final visible = channels.where((c) => c.name.toLowerCase().contains(search.text.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Private'), actions: [
        IconButton(tooltip: 'Khóa và thoát', icon: const Icon(Icons.lock), onPressed: () => Navigator.pop(context)),
      ]),
      bottomNavigationBar: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Thêm kênh')),
          OutlinedButton.icon(onPressed: importing ? null : () => _importPlaylist(),
            icon: const Icon(Icons.playlist_add), label: const Text('Nhập M3U')),
          OutlinedButton.icon(onPressed: importing ? null : _refreshPlaylists,
            icon: const Icon(Icons.refresh), label: const Text('Tải lại M3U')),
        ]),
      )),
      body: SafeArea(child: !ready ? const Center(child: CircularProgressIndicator()) : Column(children: [
        if (importing) const LinearProgressIndicator(),
        Padding(padding: const EdgeInsets.all(16), child: TextField(controller: search, onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm trong Private', border: OutlineInputBorder()))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.centerLeft,
          child: Text('Private · ${visible.length} kênh', style: Theme.of(context).textTheme.titleMedium))),
        Expanded(child: visible.isEmpty
          ? const Center(child: Text('Chưa có kênh Private. Nhấn Thêm kênh để lưu URL.'))
          : ListView.builder(padding: const EdgeInsets.only(bottom: 24), itemCount: visible.length, itemBuilder: (ctx, i) {
            final c = visible[i];
            return ListTile(leading: const Icon(Icons.live_tv), title: Text(c.name),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuangNativePlayer(channel: c, startMuted: true))),
              trailing: IconButton(tooltip: 'Xóa kênh', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(c)));
          })),
      ])),
    );
  }
}
