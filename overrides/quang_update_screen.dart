import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';

const _installer = MethodChannel('quangtv/update');

class _DownloadState {
  final String phase, url, message;
  final int downloaded, total;
  const _DownloadState({
    this.phase = 'idle',
    this.url = '',
    this.message = '',
    this.downloaded = 0,
    this.total = 0,
  });
  factory _DownloadState.fromMap(Map<dynamic, dynamic> map) => _DownloadState(
    phase: map['phase'] as String? ?? 'idle',
    url: map['url'] as String? ?? '',
    message: map['message'] as String? ?? '',
    downloaded: (map['downloaded'] as num?)?.toInt() ?? 0,
    total: (map['total'] as num?)?.toInt() ?? 0,
  );
  bool get running => phase == 'downloading';
  bool get ready => phase == 'ready';
  double? get progress =>
      total > 0 ? (downloaded / total).clamp(0.0, 1.0) : null;
  String get bytesLabel {
    String mb(int value) => (value / 1000000).toStringAsFixed(1);
    if (total <= 0) {
      return 'Đã tải ${mb(downloaded)} MB · Đang xác định dung lượng';
    }
    final remaining = (total - downloaded).clamp(0, total).toInt();
    return 'Đã tải ${mb(downloaded)} / ${mb(total)} MB · Còn ${mb(remaining)} MB';
  }
}

Future<_DownloadState> _readDownload() async => _DownloadState.fromMap(
  await _installer.invokeMapMethod<dynamic, dynamic>('status') ?? {},
);

class _ProgressView extends StatelessWidget {
  final _DownloadState state;
  const _ProgressView(this.state);
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LinearProgressIndicator(value: state.progress),
      const SizedBox(height: 12),
      Text(state.bytesLabel, key: const ValueKey('ota-bytes')),
      if (state.progress != null)
        Text('${(state.progress! * 100).toStringAsFixed(0)}%'),
    ],
  );
}

class QuangUpdateScreen extends StatefulWidget {
  const QuangUpdateScreen({super.key});
  @override
  State<QuangUpdateScreen> createState() => _QuangUpdateScreenState();
}

class _QuangUpdateScreenState extends State<QuangUpdateScreen> {
  bool busy = false;
  bool polling = false;
  String message = 'Kiểm tra bản QuangTV mới nhất trên GitHub Releases.';
  String? assetUrl, latestVersion;
  String assetDigest = '';
  int assetBytes = 0;
  _DownloadState state = const _DownloadState();
  Timer? timer;

  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(milliseconds: 500), (_) => refresh());
  }

  Future<void> refresh() async {
    if (polling) return;
    polling = true;
    try {
      final next = await _readDownload();
      if (mounted) setState(() => state = next);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => message = e.message ?? 'Không đọc được trạng thái tải');
      }
    } finally {
      polling = false;
    }
  }

  Future<void> check() async {
    setState(() {
      busy = true;
      assetUrl = null;
    });
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://api.github.com/repos/Quangdevil/QuangTV/releases/latest',
            ),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('GitHub HTTP ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final assets = data['assets'] as List<dynamic>? ?? [];
      final apk = assets
          .cast<Map<String, dynamic>>()
          .where((a) => (a['name'] as String? ?? '').endsWith('-arm64.apk'))
          .firstOrNull;
      if (apk == null) throw Exception('Bản phát hành chưa có APK arm64');
      final info = await PackageInfo.fromPlatform();
      final tag = data['tag_name'] as String? ?? '';
      final match = RegExp('build([0-9]+)').firstMatch(tag);
      final remoteBuild = int.tryParse(match?.group(1) ?? '') ?? 0;
      final localBuild = int.tryParse(info.buildNumber) ?? 0;
      if (!mounted) return;
      setState(() {
        latestVersion = tag;
        if (remoteBuild > localBuild) {
          assetUrl = apk['browser_download_url'] as String?;
          assetBytes = (apk['size'] as num?)?.toInt() ?? 0;
          assetDigest = apk['digest'] as String? ?? '';
          message =
              'Có bản mới: $tag (máy đang dùng ${info.version}+${info.buildNumber}).';
        } else {
          message =
              'Bạn đang dùng bản mới nhất (${info.version}+${info.buildNumber}).';
        }
      });
    } catch (e) {
      if (mounted) setState(() => message = 'Không kiểm tra được cập nhật: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> showProgress() async {
    final ready = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DownloadDialog(),
    );
    await refresh();
    if (ready == true && mounted) await installReady();
  }

  Future<void> download() async {
    if (busy || state.running) return;
    final url = assetUrl ?? (state.url.isNotEmpty ? state.url : null);
    if (url == null) return;
    setState(() => busy = true);
    try {
      await _installer.invokeMethod<dynamic>('start', {
        'url': url,
        'total': assetBytes > 0 ? assetBytes : state.total,
        'digest': assetDigest,
      });
      await refresh();
      if (mounted) await showProgress();
    } on PlatformException catch (e) {
      if (mounted) setState(() => message = 'Cập nhật thất bại: ${e.message}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> installReady() async {
    try {
      await _installer.invokeMethod<void>('installReady');
      if (mounted) {
        setState(
          () => message =
              'Đã mở trình cài đặt Android. Nếu đóng hộp thoại, bấm Cài đặt bản đã tải để mở lại; không cần tải lại APK.',
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => message = 'Không mở được trình cài đặt: ${e.message}');
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cập nhật QuangTV')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy || state.running ? null : check,
              icon: const Icon(Icons.system_update),
              label: const Text('Kiểm tra cập nhật'),
            ),
            if (state.phase != 'idle') ...[
              const SizedBox(height: 20),
              _ProgressView(state),
              const SizedBox(height: 12),
              if (state.running) ...[
                const Text(
                  'Đang tải APK. Có thể ẩn hộp thoại; lượt tải vẫn tiếp tục.',
                ),
                TextButton(
                  key: const ValueKey('ota-show-progress'),
                  onPressed: showProgress,
                  child: const Text('Xem tiến trình'),
                ),
              ],
              if (state.ready && (assetUrl == null || assetUrl == state.url))
                FilledButton.icon(
                  key: const ValueKey('ota-install-ready'),
                  onPressed: installReady,
                  icon: const Icon(Icons.install_mobile),
                  label: const Text('Cài đặt bản đã tải'),
                ),
              if (state.phase == 'paused' || state.phase == 'error') ...[
                Text(
                  state.message.isEmpty
                      ? 'Lượt tải đang tạm dừng.'
                      : state.message,
                ),
                FilledButton(
                  onPressed: busy ? null : download,
                  child: const Text('Tiếp tục tải'),
                ),
              ],
            ],
            if (busy && !state.running)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            if (assetUrl != null &&
                !state.running &&
                (!state.ready || assetUrl != state.url)) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy ? null : download,
                icon: const Icon(Icons.download),
                label: Text('Tải và cập nhật ${latestVersion ?? ''}'),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Android sẽ yêu cầu xác nhận cài đặt. APK đã tải được giữ lại khi đóng trình cài đặt; không cần gỡ ứng dụng cũ.',
            ),
          ],
        ),
      ),
    ),
  );
}

class _DownloadDialog extends StatefulWidget {
  const _DownloadDialog();
  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  _DownloadState state = const _DownloadState(phase: 'downloading');
  Timer? timer;
  bool polling = false;
  @override
  void initState() {
    super.initState();
    tick();
    timer = Timer.periodic(const Duration(milliseconds: 400), (_) => tick());
  }

  Future<void> tick() async {
    if (polling) return;
    polling = true;
    try {
      final next = await _readDownload();
      if (!mounted) return;
      setState(() => state = next);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => state = _DownloadState(
            phase: 'error',
            message: e.message ?? 'Lỗi cập nhật',
          ),
        );
      }
    } finally {
      polling = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: Text(
        state.ready
            ? 'Đã tải xong APK'
            : state.running
            ? 'Đang tải cập nhật'
            : 'Lượt tải tạm dừng',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProgressView(state),
          if (state.message.isNotEmpty) Text(state.message),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('ota-hide-progress'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(state.running ? 'Ẩn, tiếp tục tải' : 'Đóng'),
        ),
        if (state.ready)
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cài đặt'),
          ),
      ],
    ),
  );
}
