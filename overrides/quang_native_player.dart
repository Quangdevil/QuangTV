import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/channel.dart';

/// Public, anonymous HLS fallbacks. No credentials or signed URLs.
class QuangNativePlayer extends StatefulWidget {
  final Channel channel;
  const QuangNativePlayer({super.key, required this.channel});
  @override
  State<QuangNativePlayer> createState() => _QuangNativePlayerState();
}

class _QuangNativePlayerState extends State<QuangNativePlayer> {
  VideoPlayerController? controller;
  Timer? watchdog;
  String? error;
  bool loading = true;
  bool switching = false;
  bool userPaused = false;
  int sourceIndex = 0;
  int generation = 0;
  int? bufferingSince;
  int? stalledSince;
  Duration lastPosition = Duration.zero;
  final Set<int> failedSources = {};

  static const Map<String, List<String>> fallback = {
    'VTV1': [
      'https://live.fptplay53.net/live/media/vtv1/live247-hls-avc/index.m3u8',
      'https://vtvgolive-failover.vtvdigital.vn/vtvgo/vtv1-manifest.m3u8',
      'https://ott1.nethubtv.vn/live/vtv1/playlist.m3u8',
    ],
    'VTV2': [
      'https://live.fptplay53.net/live/media/vtv2/live247-hls-avc/index.m3u8',
      'https://vtvgolive-failover.vtvdigital.vn/vtvgo/vtv2-manifest.m3u8',
    ],
    'VTV3': [
      'https://live.fptplay53.net/live/media/vtv3/live247-hls-avc/index.m3u8',
      'https://vtvgolive-failover.vtvdigital.vn/vtvgo/vtv3-manifest.m3u8',
    ],
    'VTV4': ['https://live.fptplay53.net/live/media/vtv4/live247-hls-avc/index.m3u8'],
    'VTV5': ['https://live.fptplay53.net/live/media/vtv5/live247-hls-avc/index.m3u8'],
    'VTV7': ['https://live.fptplay53.net/live/media/vtv7/live247-hls-avc/index.m3u8'],
    'VTV8': ['https://live.fptplay53.net/live/media/vtv8/live-hls-avc/index.m3u8'],
    'VTV9': ['https://live.fptplay53.net/live/media/vtv9/live247-hls-avc/index.m3u8'],
  };

  String? get vtvKey {
    final name = widget.channel.name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    for (final key in fallback.keys) {
      if (name.startsWith(key) && (name.length == key.length || !RegExp(r'[0-9]').hasMatch(name.substring(key.length, key.length + 1)))) return key;
    }
    return null;
  }

  List<String> get sources {
    final urls = <String>[widget.channel.url];
    final key = vtvKey;
    if (key != null) urls.addAll(fallback[key]!);
    return urls.where((u) => Uri.tryParse(u)?.scheme == 'https' || Uri.tryParse(u)?.scheme == 'http').toSet().toList();
  }

  bool get canSeek {
    final p = controller;
    if (p == null || !p.value.isInitialized) return false;
    final d = p.value.duration;
    return d.inSeconds > 0 && d.inSeconds < 86400;
  }

  @override
  void initState() {
    super.initState();
    _open(0);
    watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _watch());
  }

  void _watch() {
    final p = controller;
    if (!mounted || loading || switching || userPaused || p == null) return;
    final value = p.value;
    if (value.hasError) { _failover(); return; }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (value.isBuffering) {
      bufferingSince ??= now;
      if (now - bufferingSince! >= 4500) { _failover(); return; }
    } else {
      bufferingSince = null;
    }
    if (value.isPlaying && value.isInitialized) {
      if (value.position != lastPosition) {
        lastPosition = value.position;
        stalledSince = null;
      } else {
        stalledSince ??= now;
        if (now - stalledSince! >= 6000) _failover();
      }
    }
    setState(() {});
  }

  Future<void> _failover() async {
    if (switching || !mounted) return;
    failedSources.add(sourceIndex);
    final all = sources;
    final next = List<int>.generate(all.length, (i) => (sourceIndex + i + 1) % all.length)
        .where((i) => !failedSources.contains(i)).toList();
    if (next.isEmpty) {
      setState(() => error = 'Tất cả nguồn đều bị gián đoạn. Bấm Thử lại để kiểm tra lại.');
      await controller?.pause();
      return;
    }
    await _open(next.first);
  }

  Future<void> _open(int index) async {
    if (!mounted) return;
    final token = ++generation;
    switching = true;
    final old = controller;
    controller = null;
    if (old != null) await old.dispose();
    if (!mounted || token != generation) return;
    setState(() {
      loading = true;
      error = null;
      sourceIndex = index;
      bufferingSince = null;
      stalledSince = null;
      lastPosition = Duration.zero;
      userPaused = false;
    });
    final urls = sources;
    if (index >= urls.length) {
      setState(() { loading = false; switching = false; error = 'Không có nguồn phát hợp lệ'; });
      return;
    }
    final player = VideoPlayerController.networkUrl(Uri.parse(urls[index]));
    try {
      await player.initialize().timeout(const Duration(seconds: 12));
      if (!mounted || token != generation) { await player.dispose(); return; }
      controller = player;
      await player.play();
      if (mounted) setState(() { loading = false; switching = false; });
    } catch (_) {
      await player.dispose();
      if (!mounted || token != generation) return;
      switching = false;
      loading = false;
      await _failover();
    }
  }

  void _retry() {
    failedSources.clear();
    _open(0);
  }

  @override
  void dispose() {
    generation++;
    watchdog?.cancel();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel.name)),
      body: SafeArea(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (loading) const CircularProgressIndicator(),
        if (sources.length > 1)
          Text('Nguồn ${sourceIndex + 1}/${sources.length} · Tự chuyển khi lag'),
        if (error != null) ...[
          Padding(padding: const EdgeInsets.all(16), child: Text(error!, textAlign: TextAlign.center)),
          FilledButton(onPressed: _retry, child: const Text('Thử lại')),
        ],
        if (p != null && p.value.isInitialized) ...[
          AspectRatio(aspectRatio: p.value.aspectRatio > 0 ? p.value.aspectRatio : 16 / 9, child: VideoPlayer(p)),
          if (canSeek) Slider(
            value: p.value.position.inMilliseconds.clamp(0, p.value.duration.inMilliseconds).toDouble(),
            max: p.value.duration.inMilliseconds.toDouble(),
            onChanged: (v) => p.seekTo(Duration(milliseconds: v.round())),
          ) else const Text('TRỰC TIẾP · Không hỗ trợ tua'),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _retry),
            IconButton(icon: Icon(p.value.isPlaying ? Icons.pause : Icons.play_arrow), onPressed: () async {
              if (p.value.isPlaying) { userPaused = true; await p.pause(); }
              else { userPaused = false; await p.play(); }
              if (mounted) setState(() {});
            }),
            if (sources.length > 1) IconButton(tooltip: 'Đổi nguồn', icon: const Icon(Icons.skip_next), onPressed: () {
              failedSources.clear();
              _open((sourceIndex + 1) % sources.length);
            }),
          ]),
        ],
      ]))),
    );
  }
}
