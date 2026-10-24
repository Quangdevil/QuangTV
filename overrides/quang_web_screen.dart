import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class QuangWebScreen extends StatefulWidget {
  final String title;
  final Uri initialUrl;
  const QuangWebScreen({super.key, required this.title, required this.initialUrl});
  @override
  State<QuangWebScreen> createState() => _QuangWebScreenState();
}
class _QuangWebScreenState extends State<QuangWebScreen> {
  late final WebViewController controller;
  int progress = 0;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) { if (mounted) setState(() => progress = value); },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return NavigationDecision.prevent;
          if (uri.host == 'youtu.be' || uri.host.endsWith('youtube.com') || uri.host.endsWith('youtube-nocookie.com') || uri.host.endsWith('vtvgo.vn') || uri.host.endsWith('vov.vn')) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(widget.initialUrl);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title), actions: [
      IconButton(tooltip: 'Tải lại', icon: const Icon(Icons.refresh), onPressed: controller.reload),
    ]),
    body: SafeArea(child: Column(children: [
      if (progress < 100) LinearProgressIndicator(value: progress / 100),
      Expanded(child: WebViewWidget(controller: controller)),
    ])),
  );
}
