import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
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
  VlcPlayerController? vlc;
  bool usingVlc = false;
  Timer? vlcStartup;
  int vlcToken = 0;
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
  final Set<int> retriedSources = {};
  String diagnostic = '';
  String engineStage = 'Đang chuẩn bị nguồn';
  String lastFailure = '';
  bool forceVlc = false;
  static const _castChannel = MethodChannel('quangtv/cast');
  static const _externalChannel = MethodChannel('quangtv/external_player');

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
    if (!mounted || loading || switching || userPaused || p == null || usingVlc) return;
    final value = p.value;
    if (value.hasError) { _failover(value.errorDescription ?? 'Player error'); return; }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (value.isBuffering) {
      bufferingSince ??= now;
      // Buffering is normal for live IPTV. Do not treat it as a fatal error.
      if (now - bufferingSince! >= 30000) { _failover('Buffering over 30s'); return; }
    } else {
      bufferingSince = null;
    }
    if (value.isPlaying && value.isInitialized) {
      if (value.position != lastPosition) {
        lastPosition = value.position;
        stalledSince = null;
      } else {
        stalledSince ??= now;
        if (now - stalledSince! >= 30000) _failover('Playback stalled over 30s');
      }
    }
    setState(() {});
  }

  Future<void> _failover([String reason = 'Playback error']) async {
    if (switching || !mounted || error != null) return;
    diagnostic = reason;
    lastFailure = reason;
    engineStage = 'Media3 lỗi, đang chuyển nguồn';
    // Retry the same stream once before trying a different source.
    if (retriedSources.add(sourceIndex)) {
      await _open(sourceIndex);
      return;
    }
    failedSources.add(sourceIndex);
    final all = sources;
    final next = List<int>.generate(all.length, (i) => (sourceIndex + i + 1) % all.length)
        .where((i) => !failedSources.contains(i)).toList();
    if (next.isEmpty) {
      // Always retry the ORIGINAL channel URL with VLC, not a VTV fallback CDN.
      sourceIndex = 0;
      await _openVlc();
      return;
    }
    await _open(next.first);
  }

  Future<void> _openVlc() async {
    if (!mounted || usingVlc) return;
    final token = ++vlcToken;
    final old = controller;
    controller = null;
    usingVlc = true;
    switching = false;
    if (old != null) await old.dispose();
    if (!mounted || token != vlcToken) return;
    setState(() { loading = true; error = null; });
    engineStage = 'VLC nội bộ';
    final url = sources.isEmpty ? null : sources[sourceIndex];
    if (url == null) {
      setState(() { loading = false; error = 'Không có URL phát hợp lệ'; });
      return;
    }
    try {
      final player = VlcPlayerController.network(url, hwAcc: HwAcc.full, autoPlay: true);
      vlc = player;
      player.addListener(() {
        if (!mounted || token != vlcToken) return;
        final value = player.value;
        if (value.isInitialized || value.isPlaying) {
          vlcStartup?.cancel();
          if (loading) setState(() => loading = false);
        } else if (value.hasError) {
          vlcStartup?.cancel();
          setState(() { loading = false; error = 'VLC không phát được nguồn. Media3: $lastFailure'; });
        }
      });
      vlcStartup = Timer(const Duration(seconds: 25), () {
        if (mounted && token == vlcToken && loading) setState(() { loading = false; error = 'VLC không khởi tạo được nguồn sau 25 giây'; });
      });
    } catch (e) {
      if (mounted && token == vlcToken) setState(() { loading = false; error = 'Lỗi VLC: ${e.runtimeType}'; });
    }
  }

  Future<void> _open(int index) async {
    vlcToken++;
    vlcStartup?.cancel();
    final oldVlc = vlc;
    vlc = null;
    usingVlc = false;
    if (oldVlc != null) await oldVlc.dispose();
    engineStage = 'Media3 · HLS';
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
    final url = urls[index];
    final uri = Uri.parse(url);
    final isHls = uri.path.toLowerCase().endsWith('.m3u8') || url.toLowerCase().contains('.m3u8?');
    final player = VideoPlayerController.networkUrl(uri,
      formatHint: isHls ? VideoFormat.hls : null,
      httpHeaders: const {'User-Agent': 'Mozilla/5.0 (Linux; Android 17) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36', 'Accept': '*/*'},
    );
    try {
      await player.initialize().timeout(const Duration(seconds: 12));
      if (!mounted || token != generation) { await player.dispose(); return; }
      controller = player;
      await player.play();
      if (mounted) setState(() { loading = false; switching = false; });
    } catch (e) {
      diagnostic = 'Khởi tạo luồng: ${e.runtimeType}: $e';
      lastFailure = diagnostic;
      await player.dispose();
      if (!mounted || token != generation) return;
      switching = false;
      loading = false;
      await _failover();
    }
  }

  void _retry() {
    failedSources.clear();
    retriedSources.clear();
    _open(0);
  }

  Future<void> _openExternal() async {
    final url = sources.isNotEmpty ? sources[sourceIndex] : widget.channel.url;
    try {
      final ok = await _externalChannel.invokeMethod<bool>('open', {'url': url}) ?? false;
      if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không tìm thấy ứng dụng phát video tương thích.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không mở được trình phát ngoài: ${e.runtimeType}')));
    }
  }

  Future<void> _openCast() async {
    try {
      final opened = await _castChannel.invokeMethod<bool>('openSettings') ?? false;
      if (!opened && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('TV này cần mở Smart View trong bảng điều khiển nhanh Samsung.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mở Smart View từ bảng điều khiển nhanh Samsung để phản chiếu màn hình.')));
    }
  }

  @override
  void dispose() {
    generation++;
    watchdog?.cancel();
    vlcStartup?.cancel();
    vlcToken++;
    vlc?.dispose();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel.name), actions: [
        IconButton(tooltip: 'Mở trình phát ngoài (dự phòng)', icon: const Icon(Icons.open_in_new), onPressed: _openExternal),
        IconButton(tooltip: 'Phản chiếu lên Samsung TV (Smart View)', icon: const Icon(Icons.cast), onPressed: _openCast),
      ]),
      body: SafeArea(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (loading) const CircularProgressIndicator(),
        Text(usingVlc ? 'Đang phát bằng VLC nội bộ' : 'Đang phát bằng Android Media3${sources.length > 1 ? ' · Nguồn ${sourceIndex + 1}/${sources.length}' : ''}'),
        if (error != null) ...[
          Padding(padding: const EdgeInsets.all(16), child: Text(error!, textAlign: TextAlign.center)),
          FilledButton(onPressed: _retry, child: const Text('Thử lại')),
          TextButton.icon(onPressed: () { failedSources.clear(); retriedSources.clear(); sourceIndex = 0; _openVlc(); }, icon: const Icon(Icons.play_circle_outline), label: const Text('Thử VLC nội bộ')),
          TextButton.icon(onPressed: _openExternal, icon: const Icon(Icons.open_in_new), label: const Text('Mở bằng trình phát ngoài')),
          Padding(padding: const EdgeInsets.all(12), child: SelectableText('Chẩn đoán: $lastFailure', textAlign: TextAlign.center)),
        ],
        if (usingVlc && vlc != null) ...[
          AspectRatio(aspectRatio: 16 / 9, child: VlcPlayer(controller: vlc!, aspectRatio: 16 / 9, placeholder: const Center(child: CircularProgressIndicator()))),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(tooltip: 'Thử lại', icon: const Icon(Icons.refresh), onPressed: _retry),
            IconButton(tooltip: 'Tạm dừng', icon: const Icon(Icons.pause), onPressed: () => vlc?.pause()),
            IconButton(tooltip: 'Tiếp tục', icon: const Icon(Icons.play_arrow), onPressed: () => vlc?.play()),
          ]),
        ],
        if (!usingVlc && p != null && p.value.isInitialized) ...[
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
