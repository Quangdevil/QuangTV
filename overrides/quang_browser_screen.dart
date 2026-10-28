import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel.dart';
import 'quang_native_player.dart';

class QuangBrowserScreen extends StatefulWidget {
  final String initialUrl;
  const QuangBrowserScreen({super.key, this.initialUrl = ''});
  @override
  State<QuangBrowserScreen> createState() => _QuangBrowserScreenState();
}

class _QuangBrowserScreenState extends State<QuangBrowserScreen> {
  static const browser = MethodChannel('quangtv/browser');
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _browse());
  }

  Future<void> _browse() async {
    var page = widget.initialUrl.isEmpty ? 'https://may-viet-web-proxy.daquang.workers.dev/' : widget.initialUrl;
    try {
      while (mounted) {
        final media = await browser.invokeMapMethod<String, dynamic>('open', {'url': page});
        if (!mounted) return;
        if (media == null) {
          Navigator.pop(context);
          return;
        }
        page = media['page'] as String? ?? '';
        final url = media['url'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('quangtv_headers_${base64Url.encode(utf8.encode(url))}', jsonEncode(media['headers'] ?? {}));
        if (!mounted) return;
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => QuangNativePlayer(
          channel: Channel(name: media['title'] as String? ?? 'Video trình duyệt', url: url),
        )));
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? 'Không mở được trình duyệt');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Trình duyệt')),
    body: SafeArea(child: Center(child: error == null
      ? const CircularProgressIndicator()
      : Text(error!, textAlign: TextAlign.center))),
  );
}
