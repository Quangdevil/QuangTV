import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/channel.dart';

/// Dedicated QuangTV player: never launches third-party apps.
class QuangNativePlayer extends StatefulWidget {
  final Channel channel;
  const QuangNativePlayer({super.key, required this.channel});
  @override
  State<QuangNativePlayer> createState() => _QuangNativePlayerState();
}

class _QuangNativePlayerState extends State<QuangNativePlayer> {
  VideoPlayerController? controller;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final old = controller;
    controller = null;
    if (old != null) await old.dispose();
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    final uri = Uri.tryParse(widget.channel.url);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) {
      setState(() { loading = false; error = 'URL nguồn phát không hợp lệ'; });
      return;
    }
    final player = VideoPlayerController.networkUrl(uri);
    try {
      await player.initialize().timeout(const Duration(seconds: 25));
      if (!mounted) { await player.dispose(); return; }
      controller = player;
      await player.play();
      if (mounted) setState(() => loading = false);
    } catch (e) {
      await player.dispose();
      if (mounted) setState(() { loading = false; error = 'Không thể phát nguồn này trong QuangTV: $e'; });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel.name)),
      body: SafeArea(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (loading) const CircularProgressIndicator(),
        if (error != null) ...[
          Padding(padding: const EdgeInsets.all(20), child: Text(error!, textAlign: TextAlign.center)),
          FilledButton.icon(onPressed: _open, icon: const Icon(Icons.refresh), label: const Text('Thử lại')),
        ],
        if (player != null && player.value.isInitialized) ...[
          AspectRatio(aspectRatio: player.value.aspectRatio > 0 ? player.value.aspectRatio : 16 / 9,
            child: VideoPlayer(player)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: const Icon(Icons.replay), onPressed: _open),
            IconButton(icon: Icon(player.value.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () async {
                if (player.value.isPlaying) { await player.pause(); } else { await player.play(); }
                if (mounted) setState(() {});
              }),
          ]),
        ],
      ]))),
    );
  }
}
