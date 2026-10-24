import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:just_audio/just_audio.dart';

class QuangAudioScreen extends StatefulWidget {
  final String title;
  final String? feedUrl;
  final String? streamUrl;
  const QuangAudioScreen({super.key, required this.title, this.feedUrl, this.streamUrl});
  @override
  State<QuangAudioScreen> createState() => _QuangAudioScreenState();
}
class _Episode {
  final String title;
  final String url;
  const _Episode(this.title, this.url);
}
class _QuangAudioScreenState extends State<QuangAudioScreen> {
  final player = AudioPlayer();
  List<_Episode> episodes = [];
  String? error;
  bool loading = false;
  String? playing;
  @override
  void initState() {
    super.initState();
    if (widget.feedUrl != null) _loadFeed();
    if (widget.streamUrl != null) _play(widget.streamUrl!, widget.title);
  }
  Future<void> _loadFeed() async {
    setState(() { loading = true; error = null; });
    try {
      final uri = Uri.parse(widget.feedUrl!);
      if (uri.scheme != 'https') throw Exception('RSS cần HTTPS');
      final response = await http.get(uri).timeout(const Duration(seconds: 18));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final doc = XmlDocument.parse(response.body);
      final result = <_Episode>[];
      for (final item in doc.findAllElements('item')) {
        final title = item.getElement('title')?.innerText.trim() ?? 'Tập podcast';
        final enclosure = item.getElement('enclosure')?.getAttribute('url');
        if (enclosure != null && Uri.tryParse(enclosure)?.scheme == 'https') {
          result.add(_Episode(title, enclosure));
        }
      }
      if (mounted) setState(() { episodes = result; error = result.isEmpty ? 'RSS không có tập âm thanh HTTPS.' : null; });
    } catch (e) {
      if (mounted) setState(() => error = 'Không tải được podcast: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  Future<void> _play(String url, String title) async {
    setState(() { loading = true; error = null; playing = title; });
    try {
      await player.setUrl(url);
      await player.play();
    } catch (e) {
      if (mounted) setState(() => error = 'Không phát được: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  @override
  void dispose() { player.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(child: Column(children: [
      if (loading) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.all(16), child: Text(error!, style: const TextStyle(color: Colors.red))),
      if (playing != null) ListTile(leading: const Icon(Icons.graphic_eq), title: Text(playing!), subtitle: const Text('Phát trong QuangTV')),
      StreamBuilder<PlayerState>(stream: player.playerStateStream, builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? false;
        return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(tooltip: isPlaying ? 'Tạm dừng' : 'Phát', iconSize: 40,
            onPressed: () => isPlaying ? player.pause() : player.play(),
            icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle)),
          IconButton(tooltip: 'Dừng', onPressed: () => player.stop(), icon: const Icon(Icons.stop_circle_outlined)),
        ]);
      }),
      Expanded(child: ListView.builder(itemCount: episodes.length, itemBuilder: (context, index) {
        final e = episodes[index];
        return ListTile(leading: const Icon(Icons.podcasts), title: Text(e.title), onTap: () => _play(e.url, e.title));
      })),
    ])),
  );
}
