import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'quang_audio_screen.dart';
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
    recentChannels = prefs.getStringList('quangtv_recent_channels') ?? [];
    if (mounted) setState(() {});
    await _load();
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
      if (!RegExp(r'^\\d{4,}$').hasMatch(pin)) return false;
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
  }
  Future<void> _savePlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('quangtv_playlist', urlController.text.trim());
    await prefs.setBool('quangtv_playlist_private', playlistPrivate);
  }
  Future<void> _togglePlaylistPrivacy(bool value) async {
    if (value && !await _unlock()) return;
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
      personalChannels.add(Channel(name: name, url: url, country: 'Personal'));
      if (hide) { hiddenUrls.add(url); } else { hiddenUrls.remove(url); }
    });
    await _savePersonal();
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
    recentChannels = [c.url, ...recentChannels.where((url) => url != c.url)].take(30).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('quangtv_recent_channels', recentChannels);
    if (!mounted) return;
    setState(() {});
    await Navigator.push(context, MaterialPageRoute(builder: (_) => QuangNativePlayer(channel: c)));
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
          const Text('Kênh đã xem gần đây', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          for (final url in recentChannels)
            for (final c in [...personalChannels, ...(playlistPrivate && !unlocked ? <Channel>[] : channels)].where((c) => c.url == url && (!hiddenUrls.contains(c.url) || unlocked)))
              ListTile(leading: const Icon(Icons.history), title: Text(c.name), onTap: () => _playProtected(c)),
        ],
        if (section == 0) ...[
          const SizedBox(height: 12),
          const Divider(),
          const Text('VTV · Xem lại phim và chương trình',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Text('Mở kho xem lại chính thức của VTVgo ngay trong QuangTV. Nội dung phụ thuộc VTVgo và quyền phát.'),
          const ListTile(leading: Icon(Icons.movie_filter_outlined), title: Text('VTV xem lại'), subtitle: Text('Chờ nguồn phát/API hợp lệ để tích hợp native. Không sử dụng WebView.')),
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
          const Divider(),
          const Text('Xem gần đây', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          for (final url in recentChannels)
            for (final c in [...personalChannels, ...(playlistPrivate && !unlocked ? <Channel>[] : channels)].where((c) => c.url == url && (!hiddenUrls.contains(c.url) || unlocked)))
              ListTile(leading: const Icon(Icons.history), title: Text(c.name), onTap: () => _playProtected(c)),
        ],
        if (section == 1) ...[
          const Text('YouTube', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Không cần đăng nhập để tìm và xem video công khai. Lịch sử tìm kiếm lưu trên máy.'),
          TextField(controller: youtubeSearch, textInputAction: TextInputAction.search, onSubmitted: _searchYoutube,
            decoration: InputDecoration(hintText: 'Tìm video YouTube', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _searchYoutube(youtubeSearch.text)))),
          const SizedBox(height: 8),
          const Text('Lịch sử tìm kiếm'),
          for (final query in youtubeHistory) ListTile(dense: true, leading: const Icon(Icons.history), title: Text(query), onTap: () => _searchYoutube(query)),
          const ListTile(leading: Icon(Icons.play_circle_outline), title: Text('YouTube native'), subtitle: Text('Đang chờ phương thức tích hợp hợp lệ, không dùng WebView.')),
        ],
        if (section == 2) ...[
          const Text('Podcast · Phát trong QuangTV', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Nhập RSS podcast có tệp âm thanh để xem danh sách tập và nghe trực tiếp.'),
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
          const Text('Phát luồng âm thanh trực tiếp, không chuyển sang ứng dụng VOV. Nhập URL luồng radio hợp lệ (không phải trang web).'),
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
