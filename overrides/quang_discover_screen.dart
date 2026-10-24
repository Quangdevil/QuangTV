import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'quang_audio_screen.dart';
import 'quang_web_screen.dart';
import '../models/channel.dart';
import 'quang_native_player.dart';

class QuangDiscoverScreen extends StatefulWidget {
  const QuangDiscoverScreen({super.key});
  @override
  State<QuangDiscoverScreen> createState() => _QuangDiscoverScreenState();
}

class _QuangDiscoverScreenState extends State<QuangDiscoverScreen> {
  static const defaultUrl = 'https://iptv-org.github.io/iptv/countries/vn.m3u';
  final urlController = TextEditingController(text: defaultUrl);
  final searchController = TextEditingController();
  List<Channel> channels = [];
  int section = 0;
  List<String> youtubeHistory = [];
  final youtubeSearch = TextEditingController();
  final podcastFeed = TextEditingController();
  final radioStream = TextEditingController();
  Set<String> favorites = {};
  List<String> recentChannels = [];
  List<Channel> personalChannels = [];
  List<Channel> privateChannels = [];
  Set<String> hiddenUrls = {};
  String? pinDigest;
  bool unlocked = false;
  bool playlistPrivate = false;
  bool loading = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    urlController.text = prefs.getString('quangtv_playlist') ?? defaultUrl;
    youtubeHistory = prefs.getStringList('quangtv_youtube_search_history') ?? [];
    favorites = (prefs.getStringList('quangtv_favorites') ?? []).toSet();
    pinDigest = prefs.getString('quangtv_pin_hash');
    playlistPrivate = prefs.getBool('quangtv_playlist_private') ?? false;
    hiddenUrls = (prefs.getStringList('quangtv_hidden_urls') ?? []).toSet();
    for (final item in prefs.getStringList('quangtv_personal_channels') ?? <String>[]) {
      try { final data = jsonDecode(item) as Map<String, dynamic>; personalChannels.add(Channel(name: data['name'] as String, url: data['url'] as String, country: 'Personal')); } catch (_) {}
    }
    for (final item in prefs.getStringList('quangtv_private_channels') ?? <String>[]) {
      try { final data = jsonDecode(item) as Map<String, dynamic>; privateChannels.add(Channel(name: data['name'] as String, url: data['url'] as String, country: 'Private')); } catch (_) {}
    }
    recentChannels = (prefs.getStringList('quangtv_recent_channels') ?? []).where((url) => !hiddenUrls.contains(url) && !privateChannels.any((c) => c.url == url)).toList();
    favorites.removeWhere((url) => hiddenUrls.contains(url) || privateChannels.any((c) => c.url == url));
    if (mounted) setState(() {});
    final cached = prefs.getString('quangtv_cached_channels');
    if (cached != null) {
      try {
        final list = jsonDecode(cached) as List<dynamic>;
        channels = list.map((v) => Channel(name: v['name'] as String, url: v['url'] as String, country: 'Vietnam')).toList();
        if (mounted) setState(() {});
      } catch (_) {}
    } else {
      await _load();
    }
  }

  Future<void> _load() async {
    final uri = Uri.tryParse(urlController.text.trim());
    if (uri == null || uri.scheme != 'https') {
      setState(() => error = 'Chỉ hỗ trợ liên kết HTTPS hợp lệ');
      return;
    }
    final savedPrefs = await SharedPreferences.getInstance();
    await savedPrefs.setString('quangtv_playlist', uri.toString());
    setState(() { loading = true; error = ''; });
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      if (response.body.length > 6000000) throw Exception('Danh sách quá lớn');
      final lines = response.body.split(RegExp(r'\r?\n'));
      final result = <Channel>[];
      String name = '';
      for (final line in lines) {
        final s = line.trim();
        if (s.startsWith('#EXTINF:')) {
          name = s.contains(',') ? s.substring(s.indexOf(',') + 1).trim() : 'Kênh TV';
        } else if (s.isNotEmpty && !s.startsWith('#')) {
          final stream = Uri.tryParse(s);
          if (stream != null && (stream.scheme == 'https' || stream.scheme == 'http')) {
            result.add(Channel(name: name.isEmpty ? 'Kênh TV' : name, url: s, country: 'Vietnam'));
          }
          name = '';
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('quangtv_playlist', uri.toString());
      await prefs.setString('quangtv_cached_channels', jsonEncode(result.map((c) => {'name': c.name, 'url': c.url}).toList()));
      if (mounted) setState(() => channels = result);
    } catch (e) {
      if (mounted) setState(() => error = 'Không tải được danh sách: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _hashPin(String pin) => sha256.convert(utf8.encode('quangtv-pin-v1:$pin')).toString();
  Future<String?> _askText(String title, String label, {bool secret = false}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title), content: TextField(controller: controller, obscureText: secret, autofocus: true,
      decoration: InputDecoration(labelText: label)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
      FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('OK'))]));
    controller.dispose();
    return result;
  }
  Future<bool> _unlock() async {
    if (unlocked) return true;
    final pin = await _askText(pinDigest == null ? 'Tạo PIN' : 'Nhập PIN', 'Tối thiểu 4 số', secret: true);
    if (pin == null || !mounted) return false;
    if (pinDigest == null) {
      if (pin.length < 4 || !pin.split('').every((c) => '0123456789'.contains(c))) return false;
      pinDigest = _hashPin(pin);
      await (await SharedPreferences.getInstance()).setString('quangtv_pin_hash', pinDigest!);
    } else if (_hashPin(pin) != pinDigest) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sai PIN')));
      return false;
    }
    if (mounted) setState(() => unlocked = true);
    return true;
  }
  Future<void> _savePersonal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('quangtv_personal_channels', personalChannels.map((c) => jsonEncode({'name': c.name, 'url': c.url})).toList());
    await prefs.setStringList('quangtv_hidden_urls', hiddenUrls.toList());
    await prefs.setStringList('quangtv_private_channels', privateChannels.map((c) => jsonEncode({'name': c.name, 'url': c.url})).toList());
  }
  Future<void> _savePlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('quangtv_playlist', urlController.text.trim());
    await prefs.setBool('quangtv_playlist_private', playlistPrivate);
  }
  Future<void> _togglePlaylistPrivacy(bool value) async {
    if (!await _unlock()) return;
    if (!mounted) return;
    setState(() => playlistPrivate = value);
    await _savePlaylist();
  }
  Future<void> _addPersonalChannel() async {
    final name = await _askText('Thêm kênh cá nhân', 'Tên kênh');
    if (name == null || name.isEmpty || !mounted) return;
    final url = await _askText('Nguồn phát', 'URL video .m3u8 / .mp4');
    if (url == null || !mounted) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL HTTP/HTTPS không hợp lệ')));
      return;
    }
    final hide = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Bảo vệ kênh này?'),
      content: const Text('Kênh ẩn yêu cầu mã PIN khi xem.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Công khai')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Ẩn bằng PIN')),
      ],
    ));
    if (hide == null || !mounted) return;
    if (hide && !await _unlock()) return;
    setState(() {
      personalChannels.removeWhere((c) => c.url == url);
      privateChannels.removeWhere((c) => c.url == url);
      if (hide) {
        privateChannels.add(Channel(name: name, url: url, country: 'Private'));
        hiddenUrls.add(url);
        recentChannels.removeWhere((item) => item == url);
        favorites.remove(url);
      } else { personalChannels.add(Channel(name: name, url: url, country: 'Personal')); hiddenUrls.remove(url); }
    });
    await _savePersonal();
    if (hide) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('quangtv_recent_channels', recentChannels);
      await prefs.setStringList('quangtv_favorites', favorites.toList());
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu kênh trên thiết bị')));
  }

  Future<void> _playProtected(Channel channel) async {
    if ((hiddenUrls.contains(channel.url) || (playlistPrivate && channels.any((c) => c.url == channel.url))) && !await _unlock()) return;
    if (!mounted) return;
    await _playChannel(channel);
  }

  Future<void> _toggleFavorite(Channel c) async {
    setState(() { if (!favorites.add(c.url)) favorites.remove(c.url); });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('quangtv_favorites', favorites.toList());
  }

  Future<void> _playChannel(Channel c) async {
    if (privateChannels.any((item) => item.url == c.url) || hiddenUrls.contains(c.url)) {
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => QuangNativePlayer(channel: c)));
      return;
    }
    recentChannels = [c.url, ...recentChannels.where((url) => url != c.url)].take(30).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('quangtv_recent_channels', recentChannels);
    if (!mounted) return;
    setState(() {});
    await Navigator.push(context, MaterialPageRoute(builder: (_) => QuangNativePlayer(channel: c)));
  }

  Future<void> _changePin() async {
    if (!await _unlock()) return;
    final next = await _askText('Đổi mã PIN', 'PIN mới, tối thiểu 4 chữ số', secret: true);
    if (next == null || !RegExp(r'^[0-9]{4,}\$').hasMatch(next)) return;
    final again = await _askText('Xác nhận PIN mới', 'Nhập lại PIN', secret: true);
    if (again != next) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN xác nhận không khớp')));
      return;
    }
    pinDigest = _hashPin(next);
    await (await SharedPreferences.getInstance()).setString('quangtv_pin_hash', pinDigest!);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đổi PIN')));
  }

  Future<void> _addPrivateChannel() async {
    if (!await _unlock()) return;
    final name = await _askText('Thêm kênh ẩn', 'Tên kênh');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final url = await _askText('Nguồn phát kênh ẩn', 'URL HTTP/HTTPS');
    final uri = Uri.tryParse(url ?? '');
    if (uri == null || !['http', 'https'].contains(uri.scheme) || !mounted) return;
    setState(() {
      privateChannels.removeWhere((c) => c.url == url);
      personalChannels.removeWhere((c) => c.url == url);
      privateChannels.add(Channel(name: name.trim(), url: url!, country: 'Private'));
      hiddenUrls.add(url);
      favorites.remove(url);
      recentChannels.removeWhere((item) => item == url);
    });
    await _savePersonal();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('quangtv_favorites', favorites.toList());
    await prefs.setStringList('quangtv_recent_channels', recentChannels);
  }

  Future<void> _removeRecent(String url) async {
    setState(() => recentChannels.removeWhere((item) => item == url));
    await (await SharedPreferences.getInstance()).setStringList('quangtv_recent_channels', recentChannels);
  }

  Future<void> _clearRecents() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Xóa toàn bộ lịch sử xem?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa tất cả')),
      ],
    ));
    if (confirm != true || !mounted) return;
    setState(() => recentChannels.clear());
    await (await SharedPreferences.getInstance()).remove('quangtv_recent_channels');
  }

  Future<void> _discoverPodcasts(String topic) async {
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': topic, 'media': 'podcast', 'entity': 'podcast',
        'country': 'vn', 'limit': '35',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 18));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .where((item) => Uri.tryParse(item['feedUrl']?.toString() ?? '')?.scheme == 'https')
          .toList();
      if (!mounted) return;
      await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (ctx) => SafeArea(
        child: SizedBox(height: MediaQuery.sizeOf(ctx).height * 0.72, child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Text('Podcast: $topic', style: Theme.of(ctx).textTheme.titleLarge)),
          Expanded(child: results.isEmpty
            ? const Center(child: Text('Chưa tìm được RSS âm thanh hợp lệ'))
            : ListView.builder(itemCount: results.length, itemBuilder: (context, index) {
                final item = results[index];
                final title = item['collectionName']?.toString() ?? 'Podcast';
                final feed = item['feedUrl'].toString();
                return ListTile(leading: const Icon(Icons.podcasts), title: Text(title),
                  subtitle: Text(item['artistName']?.toString() ?? ''),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(this.context, MaterialPageRoute(builder: (_) => QuangAudioScreen(title: title, feedUrl: feed)));
                  });
              })),
        ])),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không tải được thư viện podcast: $e')));
    }
  }

  Future<void> _openPodcast(int appleId, String title) async {
    try {
      final uri = Uri.https('itunes.apple.com', '/lookup', {'id': '$appleId', 'entity': 'podcast'});
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('Danh mục HTTP ${response.statusCode}');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) throw Exception('Không tìm thấy chương trình');
      final feed = (results.first as Map<String, dynamic>)['feedUrl'] as String?;
      if (feed == null || Uri.tryParse(feed)?.scheme != 'https') throw Exception('Không có RSS HTTPS hợp lệ');
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => QuangAudioScreen(title: title, feedUrl: feed)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không tải được podcast: $e')));
    }
  }

  void _openRadio(String title, String url) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => QuangAudioScreen(title: title, streamUrl: url)));
  }

  Future<void> _searchYoutube(String query) async {
    query = query.trim();
    if (query.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    youtubeHistory = [query, ...youtubeHistory.where((x) => x != query)].take(30).toList();
    await prefs.setStringList('quangtv_youtube_search_history', youtubeHistory);
    if (mounted) setState(() {});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('YouTube native đang phát triển. Đã lưu từ khóa tìm kiếm.')));
  }

  @override
  void dispose() {
    urlController.dispose();
    searchController.dispose();
    youtubeSearch.dispose();
    podcastFeed.dispose();
    radioStream.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = searchController.text.toLowerCase();
    final shown = [...personalChannels, ...(playlistPrivate && !unlocked ? <Channel>[] : channels)].where((c) => c.name.toLowerCase().contains(filter) && (!hiddenUrls.contains(c.url) || unlocked)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('QuangTV')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        SizedBox(width: double.infinity, child: SegmentedButton<int>(
          segments: const [ButtonSegment(value: 0, icon: Icon(Icons.live_tv), tooltip: 'TV'), ButtonSegment(value: 1, icon: Icon(Icons.smart_display), tooltip: 'YouTube'), ButtonSegment(value: 2, icon: Icon(Icons.podcasts), tooltip: 'Podcast'), ButtonSegment(value: 3, icon: Icon(Icons.radio), tooltip: 'Radio'), ButtonSegment(value: 4, icon: Icon(Icons.favorite), tooltip: 'Ưa thích')],
          selected: {section},
          onSelectionChanged: (values) => setState(() => section = values.first),
        )),
        const SizedBox(height: 12),
        if (section == 0) ...[
        const Text('Truyền hình Việt Nam', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(controller: urlController, keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Link M3U (có thể nhập tay)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          FilledButton(onPressed: loading ? null : _load, child: const Text('Tải danh sách')),
          OutlinedButton.icon(onPressed: _addPersonalChannel, icon: const Icon(Icons.add), label: const Text('Thêm kênh')),
          OutlinedButton.icon(onPressed: () async { if (unlocked) { setState(() => unlocked = false); } else { await _unlock(); } }, icon: Icon(unlocked ? Icons.lock_open : Icons.lock), label: Text(unlocked ? 'Khóa lại' : 'Mở bằng PIN')),
          OutlinedButton(onPressed: () { urlController.text = defaultUrl; _load(); }, child: const Text('TV Việt Nam · GitHub')),
        ]),
        const Divider(),
        Row(children: [
          const Expanded(child: Text('Kênh ẩn · PIN', style: TextStyle(fontWeight: FontWeight.bold))),
          TextButton.icon(onPressed: _changePin, icon: const Icon(Icons.password), label: Text(pinDigest == null ? 'Đặt PIN' : 'Đổi PIN')),
        ]),
        Row(children: [
          OutlinedButton.icon(onPressed: () async { if (unlocked) { setState(() => unlocked = false); } else { await _unlock(); } }, icon: Icon(unlocked ? Icons.lock : Icons.lock_open), label: Text(unlocked ? 'Khóa kênh ẩn' : 'Mở kênh ẩn')),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: _addPrivateChannel, icon: const Icon(Icons.add), label: const Text('Thêm URL ẩn')),
        ]),
        if (unlocked) ...[
          for (final c in privateChannels)
            ListTile(leading: const Icon(Icons.lock), title: Text(c.name),
              onTap: () => _playChannel(c),
              trailing: IconButton(tooltip: 'Xóa kênh ẩn', icon: const Icon(Icons.delete_outline), onPressed: () async {
                setState(() { privateChannels.removeWhere((item) => item.url == c.url); hiddenUrls.remove(c.url); });
                await _savePersonal();
              })),
        ],
        SwitchListTile(title: const Text('Ẩn toàn bộ danh sách M3U bằng PIN'), value: playlistPrivate, onChanged: _togglePlaylistPrivacy),
        if (playlistPrivate && !unlocked) const Text('Danh sách riêng tư đang khóa'),
        if (loading) const LinearProgressIndicator(),
        if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
        TextField(controller: searchController, onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm kênh TV')),
        Text('${shown.length} kênh', style: Theme.of(context).textTheme.bodySmall),
        SizedBox(height: 280, child: ListView.builder(itemCount: shown.length, itemBuilder: (context, i) {
          final channel = shown[i];
          return ListTile(dense: true, leading: const Icon(Icons.live_tv), title: Text(channel.name),
            trailing: IconButton(tooltip: 'Ưa thích', icon: Icon(favorites.contains(channel.url) ? Icons.favorite : Icons.favorite_border), onPressed: () => _toggleFavorite(channel)),
            onTap: () => _playProtected(channel));
        })),
        ],
        if (section == 0) ...[
          const Divider(),
          Row(children: [
            const Expanded(child: Text('Kênh đã xem gần đây', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            if (recentChannels.isNotEmpty) TextButton.icon(onPressed: _clearRecents, icon: const Icon(Icons.delete_sweep), label: const Text('Xóa tất cả')),
          ]),
          for (final url in recentChannels)
            for (final c in [...personalChannels, ...(playlistPrivate && !unlocked ? <Channel>[] : channels)].where((c) => c.url == url && (!hiddenUrls.contains(c.url) || unlocked)))
              Dismissible(
                key: ValueKey('recent_$url'),
                direction: DismissDirection.horizontal,
                background: Container(color: Colors.red.shade700, alignment: Alignment.centerLeft, padding: const EdgeInsets.all(12), child: const Icon(Icons.delete, color: Colors.white)),
                secondaryBackground: Container(color: Colors.red.shade700, alignment: Alignment.centerRight, padding: const EdgeInsets.all(12), child: const Icon(Icons.delete, color: Colors.white)),
                onDismissed: (_) => _removeRecent(url),
                child: ListTile(leading: const Icon(Icons.history), title: Text(c.name), onTap: () => _playProtected(c), trailing: IconButton(tooltip: 'Xóa lịch sử kênh', icon: const Icon(Icons.close), onPressed: () => _removeRecent(url))),
              ),
        ],
        if (section == 0) ...[
          const SizedBox(height: 12),
          const Divider(),
          const Text('VTV · Xem lại phim và chương trình',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Text('Mở kho xem lại chính thức của VTVgo ngay trong QuangTV. Nội dung phụ thuộc VTVgo và quyền phát.'),
          ListTile(leading: const Icon(Icons.movie_filter_outlined), title: const Text('VTVgo · Xem lại (web tạm)'), subtitle: const Text('Chọn chương trình trên VTVgo trong QuangTV'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuangWebScreen(title: 'VTVgo · Xem lại', initialUrl: Uri.parse('https://vtvgo.vn/'))))),
        ],
        if (section == 4) ...[
          const Text('Kênh yêu thích', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          for (final c in [...personalChannels, ...(playlistPrivate && !unlocked ? <Channel>[] : channels)].where((c) => favorites.contains(c.url) && (!hiddenUrls.contains(c.url) || unlocked)))
            Dismissible(
              key: ValueKey('favorite_${c.url}'),
              direction: DismissDirection.endToStart,
              background: Container(color: Colors.red.shade700, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.heart_broken, color: Colors.white)),
              onDismissed: (_) => _toggleFavorite(c),
              child: ListTile(leading: const Icon(Icons.favorite), title: Text(c.name), onTap: () => _playProtected(c), trailing: IconButton(tooltip: 'Bỏ yêu thích', icon: const Icon(Icons.favorite), onPressed: () => _toggleFavorite(c))),
            ),

        ],
        if (section == 1) ...[
          const Text('YouTube', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Không cần đăng nhập để tìm và xem video công khai. Lịch sử tìm kiếm lưu trên máy.'),
          TextField(controller: youtubeSearch, textInputAction: TextInputAction.search, onSubmitted: _searchYoutube,
            decoration: InputDecoration(hintText: 'Tìm video YouTube', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _searchYoutube(youtubeSearch.text)))),
          const SizedBox(height: 8),
          const Text('Lịch sử tìm kiếm'),
          for (final query in youtubeHistory) ListTile(dense: true, leading: const Icon(Icons.history), title: Text(query), onTap: () => _searchYoutube(query)),
          ListTile(leading: const Icon(Icons.play_circle_outline), title: const Text('Mở YouTube · QuangTube tạm'), subtitle: const Text('Tìm và xem trong QuangTV, không mở app ngoài'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuangWebScreen(title: 'YouTube · QuangTV', initialUrl: Uri.parse('https://m.youtube.com/'))))),
        ],
        if (section == 2) ...[
          const Text('Podcast · Phát trong QuangTV', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Thư viện podcast tiếng Việt · Chọn để nghe ngay'),
          ListTile(leading: const Icon(Icons.child_care), title: const Text('Chú Mèo Đi Dép · Kho truyện cổ tích'), subtitle: const Text('Truyện gia đình, cổ tích cho trẻ'), onTap: () => _openPodcast(1532630528, 'Chú Mèo Đi Dép')),
          ListTile(leading: const Icon(Icons.account_balance_wallet), title: const Text('VOV · Kinh tế Tài chính'), subtitle: const Text('Kinh tế, tài chính và kinh doanh'), onTap: () => _openPodcast(1447843388, 'VOV Kinh tế Tài chính')),
          ListTile(leading: const Icon(Icons.business_center), title: const Text('Business Insights · Vietsuccess'), subtitle: const Text('Quản trị, lãnh đạo, phát triển con người'), onTap: () => _openPodcast(1569229068, 'Business Insights')),
          const Divider(),
          const Text('Khám phá thêm podcast tiếng Việt'),
          for (final topic in <String>[
            'truyện cổ tích thiếu nhi', 'truyện kể bé ngủ ngon', 'truyện ngụ ngôn',
            'chuyện gia đình trẻ em', 'giáo dục kỹ năng sống', 'truyện vui thiếu nhi',
            'bài học kinh doanh', 'khởi nghiệp kinh doanh', 'quản trị dòng tiền',
            'quản trị nhân sự', 'kỹ năng giao tiếp', 'tâm lý con người',
            'lãnh đạo quản trị', 'marketing bán hàng', 'kinh tế tài chính',
          ])
            ListTile(dense: true, leading: const Icon(Icons.library_music), title: Text(topic),
              trailing: const Icon(Icons.chevron_right), onTap: () => _discoverPodcasts(topic)),
          const Divider(),
          const Text('Hoặc nhập RSS podcast của bạn'),
          const SizedBox(height: 12),
          TextField(controller: podcastFeed, keyboardType: TextInputType.url,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.rss_feed), hintText: 'https://.../podcast.xml', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          FilledButton.icon(icon: const Icon(Icons.podcasts), label: const Text('Mở danh sách tập'),
            onPressed: () {
              final uri = Uri.tryParse(podcastFeed.text.trim());
              if (uri?.scheme != 'https') { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nhập link RSS HTTPS hợp lệ'))); return; }
              Navigator.push(context, MaterialPageRoute(builder: (_) => QuangAudioScreen(title: 'Podcast', feedUrl: uri.toString())));
            }),
        ],
        if (section == 3) ...[
          const Text('Radio · Nghe trong QuangTV', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Chọn đài để nghe ngay, không cần nhập URL.'),
          ListTile(leading: const Icon(Icons.traffic), title: const Text('VOV Giao thông Hà Nội · FM 91'), onTap: () => _openRadio('VOV Giao thông Hà Nội', 'https://play.vovgiaothong.vn/live/gthn/playlist.m3u8')),
          ListTile(leading: const Icon(Icons.traffic), title: const Text('VOV Giao thông TP.HCM'), onTap: () => _openRadio('VOV Giao thông TP.HCM', 'https://play.vovgiaothong.vn/live/gthcm/playlist.m3u8')),
          ListTile(leading: const Icon(Icons.music_note), title: const Text('VOV Sonata · FM 89'), subtitle: const Text('Giao hưởng, jazz, nhạc không lời'), onTap: () => _openRadio('VOV Sonata FM89', 'http://media.kythuatvov.vn:1936/live/VOV89.sdp/playlist.m3u8')),
          ListTile(leading: const Icon(Icons.public), title: const Text('VOV1 · Thời sự'), onTap: () => _openRadio('VOV1', 'https://stream.vovmedia.vn/vov1')),
          ListTile(leading: const Icon(Icons.auto_stories), title: const Text('VOV2 · Văn hóa, đời sống'), onTap: () => _openRadio('VOV2', 'https://stream.vovmedia.vn/vov2')),
          ListTile(leading: const Icon(Icons.music_note), title: const Text('VOV3 · Âm nhạc'), onTap: () => _openRadio('VOV3', 'https://stream.vovmedia.vn/vov3')),
          ListTile(leading: const Icon(Icons.language), title: const Text('VOV5 · Đối ngoại'), onTap: () => _openRadio('VOV5', 'https://stream.vovmedia.vn/vov5')),
          ListTile(leading: const Icon(Icons.water), title: const Text('VOV Giao thông Mê Kông'), onTap: () => _openRadio('VOV Giao thông Mê Kông', 'https://str.vov.gov.vn/vovlive/vovgtMeKong.sdp_aac/playlist.m3u8')),
          ListTile(leading: const Icon(Icons.radio), title: const Text('VOH · FM 99.9'), onTap: () => _openRadio('VOH FM 99.9', 'https://strm.voh.com.vn/radio/channel3/playlist.m3u8')),
          ListTile(leading: const Icon(Icons.radio), title: const Text('VOH · AM 610'), onTap: () => _openRadio('VOH AM 610', 'https://strm.voh.com.vn/radio/channel2/playlist.m3u8')),
          const Divider(),
          const Text('Hoặc nhập nguồn phát radio riêng'),
          const SizedBox(height: 12),
          TextField(controller: radioStream, keyboardType: TextInputType.url,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.radio), hintText: 'https://.../live.mp3', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          FilledButton.icon(icon: const Icon(Icons.play_arrow), label: const Text('Nghe radio'),
            onPressed: () {
              final uri = Uri.tryParse(radioStream.text.trim());
              if (uri?.scheme != 'https') { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nhập URL luồng HTTPS hợp lệ'))); return; }
              Navigator.push(context, MaterialPageRoute(builder: (_) => QuangAudioScreen(title: 'Radio', streamUrl: uri.toString())));
            }),
        ],
      ])),
    );
  }
}