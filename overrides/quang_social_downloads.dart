import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'quang_native_browser.dart';

/// One app destination for links explicitly pasted or shared by the user.
class QuangSocialDownloads extends StatefulWidget {
  final String initialText;
  final bool fullscreen;
  final ValueChanged<bool> onFullscreen;
  const QuangSocialDownloads({super.key, this.initialText = '', required this.fullscreen, required this.onFullscreen});
  @override
  State<QuangSocialDownloads> createState() => _QuangSocialDownloadsState();
}

class _QuangSocialDownloadsState extends State<QuangSocialDownloads> {
  static const api = MethodChannel('quangtv/modules');
  final input = TextEditingController();
  Map<String, dynamic>? video;
  bool busy = false, files = false;
  String error = '', browserPage = '';
  int request = 0;
  @override
  void initState() { super.initState(); input.text = widget.initialText; }
  @override
  void didUpdateWidget(covariant QuangSocialDownloads oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialText != widget.initialText && widget.initialText.isNotEmpty) {
      request++; input.text = widget.initialText;
      video = null; error = ''; files = false; browserPage = ''; busy = false;
    }
  }
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if ((data?.text ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa có văn bản trong bộ nhớ tạm. Bạn có thể Chia sẻ → QuangTV từ ứng dụng gốc.')));
      return;
    }
    setState(() { input.text = data!.text!; video = null; error = ''; });
  }
  Future<void> _resolve() async {
    final text = input.text.trim(); if (text.isEmpty || busy) return;
    final current = ++request;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() { busy = true; video = null; error = ''; files = false; });
    try {
      final result = await api.invokeMapMethod<String, dynamic>('socialResolve', {'text': text});
      if (mounted && current == request) setState(() => video = result);
    } on PlatformException catch (e) {
      if (mounted && current == request) setState(() => error = e.message ?? 'Chưa lấy được nguồn video.');
    } finally { if (mounted && current == request) setState(() => busy = false); }
  }
  Future<void> _download(Map<String, dynamic> choice) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await api.invokeMethod<Object>('socialDownload', {
        'url': choice['url'], 'page': video?['page'],
        'name': '${video?['platform'] ?? 'Video'}-${DateTime.now().millisecondsSinceEpoch}.mp4',
      });
      if (mounted) setState(() => files = true);
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? 'Không bắt đầu được lượt tải.');
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> _openPage() async {
    try {
      final url = await api.invokeMethod<String>('socialPage', {'text': input.text});
      if (mounted && url != null) setState(() { browserPage = url; files = false; });
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? 'Link không hợp lệ.');
    }
  }
  @override
  void dispose() { request++; input.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (browserPage.isNotEmpty) return Column(children: [
      if (!widget.fullscreen) ListTile(dense: true, leading: IconButton(tooltip: 'Về tải video', icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => browserPage = '')), title: const Text('Phát video rồi chọn Bắt video')),
      Expanded(child: QuangNativeBrowser(key: ValueKey(browserPage), initialUrl: browserPage, direct: true, fullscreen: widget.fullscreen, onFullscreen: widget.onFullscreen)),
    ]);
    if (files) return Column(children: [ListTile(leading: IconButton(tooltip: 'Về tải video', icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => files = false)), title: const Text('Tải video')), const Expanded(child: QuangNativeDownloads())]);
    final choices = (video?['choices'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
      Row(children: [const Expanded(child: Text('Tải video', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700))), IconButton(tooltip: 'Đã tải', onPressed: () => setState(() => files = true), icon: const Icon(Icons.folder_outlined))]),
      const Padding(padding: EdgeInsets.only(top: 6, bottom: 20), child: Text('Facebook · TikTok · Douyin', style: TextStyle(color: Color(0xff93a7b3)))),
      TextField(key: const ValueKey('social-input'), controller: input, minLines: 3, maxLines: 6, keyboardType: TextInputType.multiline, decoration: const InputDecoration(hintText: 'Dán link hoặc cả đoạn chia sẻ vào đây', alignLabelWithHint: true)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [FilledButton.icon(key: const ValueKey('social-resolve'), onPressed: busy ? null : _resolve, icon: const Icon(Icons.travel_explore), label: const Text('Lấy video')), OutlinedButton.icon(onPressed: busy ? null : _paste, icon: const Icon(Icons.content_paste), label: const Text('Dán link'))]),
      if (busy) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: LinearProgressIndicator()),
      if (error.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (video != null) ...[
        const SizedBox(height: 20), Text(video?['title']?.toString() ?? 'Video', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        for (final choice in choices) Card(child: ListTile(title: Text(choice['quality']?.toString() ?? 'Nguồn video'), subtitle: const Text('Watermark: chưa xác nhận'), trailing: IconButton(tooltip: 'Tải video', onPressed: busy ? null : () => _download(choice), icon: const Icon(Icons.download_outlined)))),
        if (choices.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(video?['status']?.toString() ?? 'Trang chưa cung cấp nguồn tải.')),
      ],
      const SizedBox(height: 22),
      OutlinedButton.icon(key: const ValueKey('social-open-page'), onPressed: busy ? null : _openPage, icon: const Icon(Icons.public), label: const Text('Mở trang để nhận diện')),
      const Padding(padding: EdgeInsets.only(top: 16), child: Text('Có thể dùng Chia sẻ → QuangTV ngay từ ứng dụng gốc. Video cần đăng nhập hoặc xác minh có thể chưa lấy được nguồn. Nguồn tải gốc có thể chứa watermark.', style: TextStyle(fontSize: 12, height: 1.6, color: Color(0xff93a7b3)))),
    ]);
  }
}
