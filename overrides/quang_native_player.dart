import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import '../models/channel.dart';
import 'quang_web_screen.dart';
import 'quang_vtv_source.dart';

/// Public, anonymous HLS fallbacks. No credentials or signed URLs.
class QuangNativePlayer extends StatefulWidget {
  final Channel channel;
  final bool startWithVlc;
  final bool startMuted;
  @visibleForTesting
  final List<String>? fallbackOverride;
  const QuangNativePlayer({
    super.key,
    required this.channel,
    this.startWithVlc = false,
    this.startMuted = false,
    this.fallbackOverride,
  });
  @override
  State<QuangNativePlayer> createState() => _QuangNativePlayerState();
}

class _QuangNativePlayerState extends State<QuangNativePlayer> {
  late double volume;
  double lastAudibleVolume = 1;
  bool fullscreen = false;
  bool controlsVisible = true;
  Timer? controlsTimer;
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
  bool proxyEnabled = false;
  String engineStage = 'Đang chuẩn bị nguồn';
  String lastFailure = '';
  bool forceVlc = false;
  Map<String, String> streamHeaders = {};
  static const _castChannel = MethodChannel('quangtv/cast');
  static const _externalChannel = MethodChannel('quangtv/external_player');

  List<String> resolvedVtvSources = [];
  String? get vtvKey => QuangVtvSource.channelId(widget.channel.name);
  bool get useVtvResolver => vtvKey != null && widget.fallbackOverride == null && widget.channel.country != 'Private';

  List<String> get sources {
    final urls = resolvedVtvSources.isNotEmpty
        ? List<String>.of(resolvedVtvSources)
        : <String>[widget.channel.url];
    if (widget.fallbackOverride != null) urls.addAll(widget.fallbackOverride!);
    return urls
        .where(
          (u) =>
              Uri.tryParse(u)?.scheme == 'https' ||
              Uri.tryParse(u)?.scheme == 'http',
        )
        .toSet()
        .toList();
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
    volume = widget.startMuted ? 0 : 1;
    _scheduleControlsHide();
    _initializePlayback();
    watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _watch());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (next != fullscreen) {
      fullscreen = next;
      controlsVisible = true;
      _scheduleControlsHide();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          SystemChrome.setEnabledSystemUIMode(
            fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
          );
        }
      });
    }
  }

  void _scheduleControlsHide() {
    controlsTimer?.cancel();
    controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => controlsVisible = false);
    });
  }

  void _revealControls() {
    setState(() => controlsVisible = true);
    _scheduleControlsHide();
  }

  void _toggleControls() {
    if (controlsVisible) {
      controlsTimer?.cancel();
      setState(() => controlsVisible = false);
    } else {
      _revealControls();
    }
  }

  Future<void> _seekRelative(int seconds) async {
    _revealControls();
    final p = controller;
    if (usingVlc || p == null || !canSeek) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Luồng trực tiếp này không hỗ trợ tua.')),
      );
      return;
    }
    final end = p.value.duration.inMilliseconds;
    final target = (p.value.position.inMilliseconds + seconds * 1000)
        .clamp(0, end);
    try {
      await p.seekTo(Duration(milliseconds: target));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tua được nguồn video này.')),
        );
      }
    }
  }

  Future<void> _changeVolume(double next) async {
    _revealControls();
    setState(() {
      volume = next.clamp(0.0, 1.0);
      if (volume > 0) lastAudibleVolume = volume;
    });
    try {
      final video = controller;
      final nativeVlc = vlc;
      if (video != null && video.value.isInitialized) {
        await video.setVolume(volume);
      }
      if (nativeVlc != null && nativeVlc.value.isInitialized) {
        await nativeVlc.setVolume((volume * 100).round());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không điều chỉnh được âm lượng. Hãy thử lại.'),
          ),
        );
      }
    }
  }

  Future<void> _initializePlayback() async {
    try {
      final proxy = await const MethodChannel('quangtv/browser').invokeMapMethod<String, dynamic>('proxyGet');
      proxyEnabled = proxy?['enabled'] == true;
    } on PlatformException {
      if (mounted) setState(() { loading = false; error = 'Không áp dụng được proxy. Hãy kiểm tra Cài đặt.'; });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key =
        'quangtv_headers_${base64Url.encode(utf8.encode(widget.channel.url))}';
    final saved = prefs.getString(key);
    if (saved != null) {
      try {
        final decoded = jsonDecode(saved) as Map<String, dynamic>;
        streamHeaders = decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }
    if (useVtvResolver) {
      if (mounted) setState(() => engineStage = 'Đang lấy nguồn VTVgo mới');
      try {
        resolvedVtvSources = await QuangVtvSource.resolve(widget.channel.name);
        // Never forward saved cookies/auth for an old IPTV CDN to VTVgo.
        streamHeaders = Map<String, String>.of(QuangVtvSource.headers);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          loading = false;
          error = 'Không lấy được nguồn VTVgo mới. Thử lại hoặc mở VTVgo chính thức.';
          lastFailure = 'VTVgo chưa trả nguồn phát; không thử các link CDN cũ.';
        });
        return;
      }
    }
    if (mounted) {
      if (widget.startWithVlc) {
        await _openVlc();
      } else {
        await _open(0);
      }
    }
  }

  void _watch() {
    final p = controller;
    if (!mounted ||
        loading ||
        switching ||
        userPaused ||
        p == null ||
        usingVlc) {
      return;
    }
    final value = p.value;
    if (value.hasError) {
      _failover(value.errorDescription ?? 'Player error');
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (value.isBuffering) {
      bufferingSince ??= now;
      // Buffering is normal for live IPTV. Do not treat it as a fatal error.
      if (now - bufferingSince! >= 30000) {
        _failover('Buffering over 30s');
        return;
      }
    } else {
      bufferingSince = null;
    }
    if (value.isPlaying && value.isInitialized) {
      if (value.position != lastPosition) {
        lastPosition = value.position;
        stalledSince = null;
      } else {
        stalledSince ??= now;
        if (now - stalledSince! >= 30000) {
          _failover('Playback stalled over 30s');
        }
      }
    }
    setState(() {});
  }

  Future<void> _failover([String reason = 'Playback error']) async {
    if (switching || !mounted || error != null) return;
    diagnostic = reason;
    lastFailure = reason;
    engineStage = 'Media3 lỗi, đang chuyển nguồn';
    // A forbidden source will not recover by immediately repeating the request.
    final forbidden = RegExp(r'\b403\b').hasMatch(reason);
    if (!forbidden && vtvKey == null && retriedSources.add(sourceIndex)) {
      await _open(sourceIndex);
      return;
    }
    failedSources.add(sourceIndex);
    final all = sources;
    final next = List<int>.generate(
      all.length,
      (i) => (sourceIndex + i + 1) % all.length,
    ).where((i) => !failedSources.contains(i)).toList();
    if (next.isEmpty) {
      // Try the original URL with VLC once; its own startup timer and error
      // handling stop the retry loop if it cannot play this stream either.
      sourceIndex = 0;
      await _openVlc();
      return;
    }
    await _open(next.first);
  }

  Future<void> _openVlc() async {
    if (!mounted || (usingVlc && loading)) return;
    final token = ++vlcToken;
    final oldVlc = vlc;
    vlc = null;
    if (oldVlc != null) await oldVlc.dispose();
    if (!mounted || token != vlcToken) return;
    final old = controller;
    controller = null;
    usingVlc = true;
    switching = false;
    if (old != null) await old.dispose();
    if (!mounted || token != vlcToken) return;
    setState(() {
      loading = true;
      error = null;
    });
    engineStage = 'VLC nội bộ';
    final url = sources.isEmpty ? null : sources[sourceIndex];
    if (url == null) {
      setState(() {
        loading = false;
        error = 'Không có URL phát hợp lệ';
      });
      return;
    }
    try {
      // libVLC needs its own HTTP options; video_player headers do not propagate.
      final vlcHttp = <String>[
        VlcHttpOptions.httpReconnect(true),
        VlcHttpOptions.httpForwardCookies(true),
        VlcHttpOptions.httpUserAgent(
          streamHeaders['User-Agent'] ?? 'QuangTV/1.3',
        ),
      ];
      var playbackUrl = url;
      if (proxyEnabled) {
        playbackUrl = await const MethodChannel('quangtv/browser').invokeMethod<String>('proxyMediaUrl', {'url': url}) ?? (throw StateError('Proxy chưa sẵn sàng'));
      }
      final referrer = streamHeaders['Referer'] ?? streamHeaders['Referrer'];
      if (referrer != null && referrer.isNotEmpty) {
        vlcHttp.add(VlcHttpOptions.httpReferrer(referrer));
      }
      final player = VlcPlayerController.network(
        playbackUrl,
        // Keep hardware decoding while avoiding opaque zero-copy surfaces that
        // can freeze while the audio/playback clock continues advancing.
        hwAcc: HwAcc.decoding,
        autoPlay: false,
        options: VlcPlayerOptions(
          http: VlcHttpOptions(vlcHttp),
          advanced: VlcAdvancedOptions([
            VlcAdvancedOptions.networkCaching(1500),
          ]),
        ),
      );
      player.addOnInitListener(() async {
        try {
          // Set volume before the first play, including Private's initial mute.
          await player.setVolume((volume * 100).round());
          if (mounted && token == vlcToken) {
            await player.play();
            if (mounted && token == vlcToken) setState(() {});
          }
        } catch (e) {
          if (mounted && token == vlcToken) {
            setState(() {
              loading = false;
              error = 'Không khởi động được VLC: ${e.runtimeType}';
            });
          }
        }
      });
      // VlcPlayer's widget attaches the native texture and initializes the controller.
      // Without rebuilding after assigning vlc, no VlcPlayer is mounted and
      // the 25-second timer always expires, regardless of stream validity.
      setState(() => vlc = player);
      player.addListener(() {
        if (!mounted || token != vlcToken) return;
        final value = player.value;
        if (value.isInitialized || value.isPlaying) {
          vlcStartup?.cancel();
          if (loading) setState(() => loading = false);
        } else if (value.hasError) {
          vlcStartup?.cancel();
          setState(() {
            loading = false;
            error = 'VLC không phát được nguồn. Media3: $lastFailure';
          });
        }
      });
      vlcStartup = Timer(Duration(seconds: vtvKey != null ? 10 : 25), () {
        if (mounted && token == vlcToken && loading) {
          setState(() {
            loading = false;
            error =
                'VLC không khởi tạo được nguồn. Kiểm tra URL hoặc mở VTVgo chính thức.';
          });
        }
      });
    } catch (e) {
      if (mounted && token == vlcToken) {
        setState(() {
          loading = false;
          error = 'Lỗi VLC: ${e.runtimeType}';
        });
      }
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
      setState(() {
        loading = false;
        switching = false;
        error = 'Không có nguồn phát hợp lệ';
      });
      return;
    }
    final url = urls[index];
    final uri = Uri.parse(url);
    final isHls =
        uri.path.toLowerCase().endsWith('.m3u8') ||
        url.toLowerCase().contains('.m3u8?');
    final player = VideoPlayerController.networkUrl(
      uri,
      formatHint: isHls ? VideoFormat.hls : null,
      httpHeaders: {
        'User-Agent': 'QuangTV/1.3 Android Media3',
        'Accept': '*/*',
        ...streamHeaders,
      },
    );
    try {
      await player.initialize().timeout(Duration(seconds: vtvKey != null ? 6 : 12));
      if (!mounted || token != generation) {
        await player.dispose();
        return;
      }
      controller = player;
      await player.setVolume(volume);
      await player.play();
      if (mounted) {
        setState(() {
          loading = false;
          switching = false;
        });
      }
    } catch (e) {
      diagnostic = 'Khởi tạo luồng: ${e.runtimeType}: $e';
      lastFailure = diagnostic;
      await player.dispose();
      if (!mounted || token != generation) return;
      switching = false;
      loading = false;
      await _failover(diagnostic);
    }
  }

  void _retry() {
    failedSources.clear();
    retriedSources.clear();
    if (useVtvResolver) {
      setState(() { error = null; loading = true; });
      resolvedVtvSources = [];
      vlcStartup?.cancel();
      vlcToken++;
      generation++;
      _initializePlayback();
    } else {
      _open(0);
    }
  }

  Future<void> _openExternal() async {
    final url = sources.isNotEmpty ? sources[sourceIndex] : widget.channel.url;
    try {
      final ok =
          await _externalChannel.invokeMethod<bool>('open', {'url': url}) ??
          false;
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không tìm thấy ứng dụng phát video tương thích.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không mở được trình phát ngoài: ${e.runtimeType}'),
          ),
        );
      }
    }
  }

  Future<void> _openCast() async {
    try {
      final opened =
          await _castChannel.invokeMethod<bool>('openSettings') ?? false;
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'TV này cần mở Smart View trong bảng điều khiển nhanh Samsung.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Mở Smart View từ bảng điều khiển nhanh Samsung để phản chiếu màn hình.',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    generation++;
    controlsTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    watchdog?.cancel();
    vlcStartup?.cancel();
    vlcToken++;
    vlc?.dispose();
    controller?.dispose();
    super.dispose();
  }

  Widget _volumeControl() => Row(
    children: [
      IconButton(
        key: const ValueKey('player-mute'),
        tooltip: volume == 0 ? 'Bật tiếng' : 'Tắt tiếng',
        icon: Icon(volume == 0 ? Icons.volume_off : Icons.volume_up),
        onPressed: () => _changeVolume(volume == 0 ? lastAudibleVolume : 0),
      ),
      Expanded(
        child: Slider(
          key: const ValueKey('player-volume'),
          value: volume,
          label: '${(volume * 100).round()}%',
          onChanged: _changeVolume,
        ),
      ),
      SizedBox(width: 42, child: Text('${(volume * 100).round()}%')),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final p = controller;
    final videoReady = !usingVlc && p != null && p.value.isInitialized;
    final vlcReady = usingVlc && vlc != null && error == null;
    final aspect = p != null && videoReady && p.value.aspectRatio > 0
        ? p.value.aspectRatio
        : 16 / 9;
    final visible = controlsVisible;
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: fullscreen
            ? null
            : AppBar(
                title: Text(widget.channel.name),
                actions: [
                  IconButton(
                    tooltip: 'Mở trình phát ngoài',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: _openExternal,
                  ),
                  IconButton(
                    tooltip: 'Phản chiếu lên Samsung TV',
                    icon: const Icon(Icons.cast),
                    onPressed: _openCast,
                  ),
                ],
              ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          key: const ValueKey('player-tap-surface'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Keep this subtree in the same position across rotation: no player restart.
              Positioned.fill(
                bottom: 0,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: aspect,
                    child: vlcReady
                        ? VlcPlayer(
                            controller: vlc!,
                            virtualDisplay: false,
                            aspectRatio: 16 / 9,
                            placeholder: const SizedBox.shrink(),
                          )
                        : videoReady
                        ? VideoPlayer(p)
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
              // Transparent touch layer above native video textures, below controls.
              // The VLC platform view may otherwise swallow parent gestures.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                  onDoubleTapDown: (details) {
                    final width = MediaQuery.sizeOf(context).width;
                    _seekRelative(details.localPosition.dx < width / 2 ? -10 : 10);
                  },
                ),
              ),
              if (loading && visible)
                const Center(child: CircularProgressIndicator()),
              if (error != null)
                Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!, textAlign: TextAlign.center),
                          FilledButton(
                            onPressed: _retry,
                            child: const Text('Thử lại'),
                          ),
                          TextButton(
                            onPressed: () {
                              failedSources.clear();
                              retriedSources.clear();
                              sourceIndex = 0;
                              _openVlc();
                            },
                            child: const Text('Thử VLC nội bộ'),
                          ),
                          TextButton(
                            onPressed: _openExternal,
                            child: const Text('Mở trình phát ngoài'),
                          ),
                          if (vtvKey != null)
                            TextButton.icon(
                              icon: const Icon(Icons.live_tv),
                              label: const Text('Mở VTVgo chính thức'),
                              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
                                builder: (_) => QuangWebScreen(title: 'VTVgo', initialUrl: Uri.parse('https://vtvgo.vn/channel/${vtvKey ?? '1'}')),
                              )),
                            ),
                          if (RegExp(r'\b403\b').hasMatch(lastFailure))
                            const Text('Máy chủ từ chối nguồn phát (HTTP 403). Thử cập nhật danh sách kênh hoặc mở VTVgo.', textAlign: TextAlign.center),
                          SelectableText('Chẩn đoán: $lastFailure'),
                        ],
                      ),
                    ),
                  ),
                ),
              if (fullscreen)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    ignoring: !visible,
                    child: AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: SafeArea(
                        bottom: false,
                        child: Row(
                          children: [
                            BackButton(
                              onPressed: () => Navigator.maybePop(context),
                            ),
                            Expanded(
                              child: Text(
                                widget.channel.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  key: const ValueKey('player-controls'),
                  ignoring: !visible,
                  child: AnimatedOpacity(
                    opacity: visible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      color: Colors.black.withValues(alpha: .75),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!fullscreen)
                                Text(
                                  usingVlc ? 'VLC nội bộ' : 'Android Media3',
                                ),
                              if (p != null && videoReady && canSeek)
                                Slider(
                                  value: p.value.position.inMilliseconds
                                      .clamp(0, p.value.duration.inMilliseconds)
                                      .toDouble(),
                                  max: p.value.duration.inMilliseconds
                                      .toDouble(),
                                  onChanged: (v) {
                                    _revealControls();
                                    p.seekTo(Duration(milliseconds: v.round()));
                                  },
                                ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    tooltip: 'Thử lại',
                                    icon: const Icon(Icons.refresh),
                                    onPressed: _retry,
                                  ),
                                  IconButton(
                                    tooltip: 'Tua lùi 10 giây',
                                    icon: const Icon(Icons.replay_10),
                                    onPressed: () => _seekRelative(-10),
                                  ),
                                  IconButton(
                                    tooltip: 'Phát / Tạm dừng',
                                    icon: Icon(
                                      (usingVlc
                                              ? (vlc?.value.isPlaying ?? false)
                                              : (p?.value.isPlaying ?? false))
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                    ),
                                    onPressed: () async {
                                      _revealControls();
                                      if (usingVlc) {
                                        if (vlc?.value.isPlaying ?? false) {
                                          userPaused = true;
                                          await vlc?.pause();
                                        } else {
                                          userPaused = false;
                                          await vlc?.play();
                                        }
                                      } else if (p != null) {
                                        if (p.value.isPlaying) {
                                          userPaused = true;
                                          await p.pause();
                                        } else {
                                          userPaused = false;
                                          await p.play();
                                        }
                                      }
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Tua tới 10 giây',
                                    icon: const Icon(Icons.forward_10),
                                    onPressed: () => _seekRelative(10),
                                  ),
                                  if (sources.length > 1)
                                    IconButton(
                                      tooltip: 'Đổi nguồn',
                                      icon: const Icon(Icons.skip_next),
                                      onPressed: () {
                                        failedSources.clear();
                                        _open(
                                          (sourceIndex + 1) % sources.length,
                                        );
                                      },
                                    ),
                                ],
                              ),
                              _volumeControl(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
