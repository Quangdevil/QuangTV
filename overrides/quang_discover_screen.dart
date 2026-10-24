import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'quang_web_screen.dart';
import '../models/channel.dart';
import 'player_screen.dart';

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
  Set<String> favorites = {};
  List<String> recentChannels = [];
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
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(channel: c)));
  }

  Future<void> _searchYoutube(String query) async {
    query = query.trim();
    if (query.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    youtubeHistory = [query, ...youtubeHistory.where((x) => x != query)].take(30).toList();
    await prefs.setStringList('quangtv_youtube_search_history', youtubeHistory);
    if (mounted) setState(() {});
    final uri = Uri.https('www.youtube.com', '/results', {'search_query': query});
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => QuangWebScreen(title: 'YouTube', initialUrl: uri)));
  }

  @override
  void dispose() {
    urlController.dispose();
    searchController.dispose();
    youtubeSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = searchController.text.toLowerCase();
    final shown = channels.where((c) => c.name.toLowerCase().contains(filter)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('QuangTV · TV & Podcast')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 0, label: Text('TV')), ButtonSegment(value: 1, label: Text('YouTube')), ButtonSegment(value: 2, label: Text('Podcast')), ButtonSegment(value: 3, label: Text('Radio')), ButtonSegment(value: 4, label: Text('Ưa thích'))],
          selected: {section},
          onSelectionChanged: (values) => setState(() => section = values.first),
        ),
        const SizedBox(height: 12),
        if (section == 0) ...[
        const Text('Truyền hình Việt Nam', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(controller: urlController, keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Link M3U (có thể nhập tay)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          FilledButton(onPressed: loading ? null : _load, child: const Text('Tải danh sách')),
          OutlinedButton(onPressed: () { urlController.text = defaultUrl; _load(); }, child: const Text('TV Việt Nam · GitHub')),
        ]),
        if (loading) const LinearProgressIndicator(),
        if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
        TextField(controller: searchController, onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm kênh TV')),
        Text('${shown.length} kênh', style: Theme.of(context).textTheme.bodySmall),
        SizedBox(height: 280, child: ListView.builder(itemCount: shown.length, itemBuilder: (context, i) {
          final channel = shown[i];
          return ListTile(dense: true, leading: const Icon(Icons.live_tv), title: Text(channel.name),
            trailing: IconButton(tooltip: 'Ưa thích', icon: Icon(favorites.contains(channel.url) ? Icons.favorite : Icons.favorite_border), onPressed: () => _toggleFavorite(channel)),
            onTap: () => _playChannel(channel));
        })),
        ],
        if (section == 0) ...[
          const SizedBox(height: 12),
          const Divider(),
          const Text('VTV · Xem lại phim và chương trình',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Text('Mở kho xem lại chính thức của VTVgo ngay trong QuangTV. Nội dung phụ thuộc VTVgo và quyền phát.'),
          ListTile(
            leading: const Icon(Icons.movie_filter_outlined),
            title: const Text('VTVgo · Phim và chương trình xem lại'),
            subtitle: const Text('Chọn phim, tập hoặc chương trình trên VTVgo'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => QuangWebScreen(
                title: 'VTVgo · Xem lại',
                initialUrl: Uri.parse('https://vtvgo.vn/'),
              ),
            )),
          ),
        ],
        if (section == 4) ...[
          const Text('Kênh yêu thích', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          for (final c in channels.where((c) => favorites.contains(c.url)))
            ListTile(leading: const Icon(Icons.favorite), title: Text(c.name), onTap: () => _playChannel(c), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => _toggleFavorite(c))),
          const Divider(),
          const Text('Xem gần đây', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          for (final url in recentChannels)
            for (final c in channels.where((c) => c.url == url))
              ListTile(leading: const Icon(Icons.history), title: Text(c.name), onTap: () => _playChannel(c)),
        ],
        if (section == 1) ...[
          const Text('YouTube', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Không cần đăng nhập để tìm và xem video công khai. Lịch sử tìm kiếm lưu trên máy.'),
          TextField(controller: youtubeSearch, textInputAction: TextInputAction.search, onSubmitted: _searchYoutube,
            decoration: InputDecoration(hintText: 'Tìm video YouTube', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _searchYoutube(youtubeSearch.text)))),
          const SizedBox(height: 8),
          const Text('Lịch sử tìm kiếm'),
          for (final query in youtubeHistory) ListTile(dense: true, leading: const Icon(Icons.history), title: Text(query), onTap: () => _searchYoutube(query)),
          FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuangWebScreen(title: 'YouTube', initialUrl: Uri.parse('https://www.youtube.com/')))), icon: const Icon(Icons.play_circle), label: const Text('Mở YouTube')),
        ],
        if (section == 2) ...[
        const Divider(),
        const Text('Podcast & câu chuyện tiếng Việt', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Text('Mở tìm kiếm trong YouTube chính thức để dùng tài khoản và danh sách phát của bạn.'),
        for (final item in const [
          ['Bài học kinh doanh', 'podcast bài học kinh doanh tiếng Việt khởi nghiệp'],
          ['Đàm phán và bán hàng', 'podcast nghệ thuật đàm phán bán hàng tiếng Việt'],
          ['Quản trị dòng tiền', 'podcast quản lý dòng tiền kinh doanh tiếng Việt'],
          ['Truyện gia đình cho bé', 'truyện kể gia đình cho bé tiếng Việt'],
          ['Lòng biết ơn và chia sẻ', 'truyện thiếu nhi lòng biết ơn chia sẻ gia đình'],
          ['Truyện trước giờ ngủ', 'kể chuyện cho bé trước giờ ngủ tiếng Việt'],
        ]) ListTile(
          leading: const Icon(Icons.podcasts),
          title: Text(item[0]),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _searchYoutube(item[1]),
        ),
        ],
        if (section == 3) ...[
          const Text('Đài Tiếng nói Việt Nam', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Các kênh trực tuyến chính thức. Không dùng tần số FM để giả làm link phát.'),
          for (final station in const [
            ['VOV Giao thông Hà Nội · FM 91 MHz', 'https://vov.vn/vov-plus/radio'],
            ['VOV Giao thông TP.HCM · FM 90 MHz', 'https://vov.vn/vov-plus/radio'],
            ['VOV1 · Thời sự', 'https://vov.vn/vov-plus/radio'],
            ['VOV2 · Văn hóa xã hội', 'https://vov.vn/vov-plus/radio'],
            ['VOV3 · Âm nhạc', 'https://vov.vn/vov-plus/radio'],
            ['VOV5 · Đối ngoại', 'https://vov.vn/vov-plus/radio'],
            ['VOV Sonata · FM 89 MHz', 'https://vov.vn/vov-plus/radio'],
          ]) ListTile(leading: const Icon(Icons.radio), title: Text(station[0]), trailing: const Icon(Icons.open_in_new), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuangWebScreen(title: station[0], initialUrl: Uri.parse(station[1]))))),
        ],
      ])),
    );
  }
}
