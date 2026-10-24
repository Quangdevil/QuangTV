import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class QuangUpdateScreen extends StatefulWidget {
  const QuangUpdateScreen({super.key});
  @override
  State<QuangUpdateScreen> createState() => _QuangUpdateScreenState();
}

class _QuangUpdateScreenState extends State<QuangUpdateScreen> {
  bool busy = false;
  String message = 'Kiểm tra bản QuangTV mới nhất trên GitHub Releases.';
  String? assetUrl;
  String? latestVersion;

  Future<void> check() async {
    setState(() { busy = true; assetUrl = null; });
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/Quangdevil/QuangTV/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('GitHub HTTP ${response.statusCode}');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final assets = data['assets'] as List<dynamic>? ?? [];
      final apk = assets.cast<Map<String, dynamic>>().where(
        (a) => (a['name'] as String? ?? '').endsWith('-arm64.apk'),
      ).firstOrNull;
      if (apk == null) throw Exception('Bản phát hành chưa có APK arm64');
      final info = await PackageInfo.fromPlatform();
      final tag = data['tag_name'] as String? ?? '';
      final match = RegExp(r'build(\\d+)').firstMatch(tag);
      final remoteBuild = int.tryParse(match?.group(1) ?? '') ?? 0;
      final localBuild = int.tryParse(info.buildNumber) ?? 0;
      if (!mounted) return;
      setState(() {
        latestVersion = tag;
        if (remoteBuild > localBuild) {
          assetUrl = apk['browser_download_url'] as String?;
          message = 'Có bản mới: $tag (máy đang dùng ${info.version}+${info.buildNumber}).';
        } else {
          message = 'Bạn đang dùng bản mới nhất (${info.version}+${info.buildNumber}).';
        }
      });
    } catch (e) {
      if (mounted) setState(() => message = 'Không kiểm tra được cập nhật: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> download() async {
    final url = assetUrl;
    if (url == null) return;
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.host != 'github.com') return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không mở được liên kết tải APK')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cập nhật QuangTV')),
    body: SafeArea(child: Padding(padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: busy ? null : check,
          icon: const Icon(Icons.system_update), label: const Text('Kiểm tra cập nhật')),
        if (busy) const LinearProgressIndicator(),
        if (assetUrl != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: download, icon: const Icon(Icons.download),
            label: Text('Tải APK ${latestVersion ?? ''}')),
          const Text('Android sẽ yêu cầu xác nhận cài bản cập nhật. Không cần gỡ ứng dụng cũ.'),
        ],
      ]))),
  );
}
