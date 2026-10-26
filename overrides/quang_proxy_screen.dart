import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'quang_network.dart';

class QuangProxyScreen extends StatefulWidget {
  const QuangProxyScreen({super.key});
  @override
  State<QuangProxyScreen> createState() => _QuangProxyScreenState();
}

class _QuangProxyScreenState extends State<QuangProxyScreen> {
  static const bridge = MethodChannel('quangtv/browser');
  final host = TextEditingController();
  final port = TextEditingController();
  final user = TextEditingController();
  final password = TextEditingController();
  final checkUrl = TextEditingController(text: "https://web.telegram.org/k/");
  String type = 'http';
  bool enabled = false, busy = true, hasPassword = false;
  String message = '';
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final value = await bridge.invokeMapMethod<String, dynamic>('proxyGet') ?? {};
      QuangNetwork.update(value);
      if (!mounted) return;
      host.text = value['host'] as String? ?? '';
      final savedPort = value['port'] as int? ?? 0;
      port.text = savedPort == 0 ? '' : '$savedPort';
      user.text = value['user'] as String? ?? '';
      setState(() { type = value['type'] as String? ?? 'http'; enabled = value['enabled'] == true; hasPassword = value['hasPassword'] == true; });
    } on PlatformException { if (mounted) setState(() => message = 'Không đọc được cấu hình cũ. Hãy nhập và lưu lại.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<bool> _save() async {
    if (host.text.trim().isEmpty || (int.tryParse(port.text) ?? 0) < 1 || (int.tryParse(port.text) ?? 0) > 65535) {
      setState(() => message = 'Nhập máy chủ và cổng từ 1 đến 65535.'); return false;
    }
    setState(() { busy = true; message = ''; });
    try {
      final value = await bridge.invokeMapMethod<String, dynamic>('proxySave', {'enabled': enabled, 'type': type, 'host': host.text.trim(), 'port': int.tryParse(port.text) ?? 0, 'user': user.text.trim(), 'password': password.text});
      QuangNetwork.update(value);
      if (!mounted) return false;
      setState(() { hasPassword = value?['hasPassword'] == true; message = 'Đã lưu cấu hình. Bật/tắt tại nút VPN ứng dụng trên màn hình IPTV.'; });
      password.clear(); return true;
    } on PlatformException catch (e) { if (mounted) setState(() => message = e.message ?? 'Không lưu được proxy.'); return false; }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> _paste() async {
    final value = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final parts = value?.text?.trim().split(':') ?? [];
    if (parts.length < 2 || int.tryParse(parts[1]) == null) { setState(() => message = 'Dán định dạng IP:CỔNG:TÀI_KHOẢN:MẬT_KHẨU.'); return; }
    host.text = parts[0]; port.text = parts[1]; user.text = parts.length > 2 ? parts[2] : ''; password.text = parts.length > 3 ? parts.sublist(3).join(':') : '';
    setState(() => message = 'Đã nhập từ bộ nhớ tạm. Chọn đúng loại proxy, lưu rồi bật tại màn hình IPTV.');
  }
  Future<void> _check(bool viaProxy) async {
    setState(() { busy = true; message = 'Đang kiểm tra ${viaProxy ? 'qua proxy' : 'trực tiếp'}…'; });
    try {
      final result = await bridge.invokeMapMethod<String, dynamic>('networkCheck', {'url': checkUrl.text.trim(), 'viaProxy': viaProxy});
      if (mounted) setState(() => message = '${viaProxy ? 'Proxy' : 'Trực tiếp'}: ${result?['detail']} (${result?['ms']} ms)');
    } on PlatformException catch (e) { if (mounted) setState(() => message = e.message ?? 'Không kiểm tra được'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  void dispose() { for (final c in [host, port, user, password, checkUrl]) { c.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Proxy QuangTV')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Áp dụng cho HTTP/HTTPS trong trình duyệt, QuangTube, player Media3/VLC và tải video. Không phải VPN toàn điện thoại; không chuyển các ứng dụng khác hoặc UDP/WebRTC qua proxy.'),
      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Bật/tắt tại vị trí Sort cũ trên màn hình IPTV. Nhấn giữ nút để mở cấu hình. Mặc định dùng mạng trực tiếp; không tự chuyển sang proxy trả phí.')),
      OutlinedButton.icon(onPressed: busy ? null : _paste, icon: const Icon(Icons.content_paste), label: const Text('Dán IP:cổng:tài khoản:mật khẩu')),
      DropdownButtonFormField<String>(initialValue: type, key: ValueKey(type), decoration: const InputDecoration(labelText: 'Loại proxy'), items: const [DropdownMenuItem(value: 'http', child: Text('HTTP (hỗ trợ web HTTPS)')), DropdownMenuItem(value: 'https', child: Text('HTTPS (TLS tới proxy)')), DropdownMenuItem(value: 'socks5', child: Text('SOCKS5 (DNS qua proxy)'))], onChanged: busy ? null : (value) => setState(() => type = value ?? 'http')),
      TextField(controller: host, enabled: !busy, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'Máy chủ / IP')),
      TextField(controller: port, enabled: !busy, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cổng')),
      TextField(controller: user, enabled: !busy, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'Tài khoản')),
      TextField(controller: password, enabled: !busy, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: 'Mật khẩu', hintText: hasPassword ? 'Để trống để giữ mật khẩu đã lưu' : null)),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : _save, child: const Text('Lưu cấu hình')),
      const Divider(height: 32),
      const Text('Kiểm tra trang đang lỗi', style: TextStyle(fontWeight: FontWeight.bold)),
      TextField(controller: checkUrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'URL trang web')),
      const Text('Kiểm tra trực tiếp bỏ qua proxy của ứng dụng. VPN bên ngoài điện thoại vẫn có thể ảnh hưởng kết quả. Socket thường không đổi IP hay tự vượt chặn mạng.'),
      Wrap(spacing: 8, children: [
        OutlinedButton(onPressed: busy ? null : () => _check(false), child: const Text('Kiểm tra trực tiếp')),
        OutlinedButton(onPressed: busy ? null : () => _check(true), child: const Text('Kiểm tra qua proxy')),
      ]),
      if (busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      if (message.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(message)),
      const Text('Tài khoản/mật khẩu lưu mã hóa bằng khóa Android Keystore trên máy này. Kiểm tra IP gửi yêu cầu HTTPS tới api.ipify.org qua proxy; không gửi mật khẩu tới dịch vụ kiểm tra. Khi proxy lỗi, hãy sửa cấu hình hoặc tắt proxy để dùng mạng trực tiếp. Tải qua proxy cần giữ QuangTV đang chạy.'),
    ])),
  );
}

/// Replaces the old Sort action on the outer IPTV screen.
class QuangProxyToggle extends StatefulWidget {
  const QuangProxyToggle({super.key, this.compact = false});
  final bool compact;
  @override
  State<QuangProxyToggle> createState() => _QuangProxyToggleState();
}
class _QuangProxyToggleState extends State<QuangProxyToggle> with WidgetsBindingObserver {
  bool busy = false;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _refresh(); }
  Future<void> _refresh() async { try { await QuangNetwork.refresh(); } on PlatformException { /* The toggle offers configuration recovery. */ } on MissingPluginException { /* Non-Android preview. */ } }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed) _refresh(); }
  Future<void> _toggle() async {
    if (busy) return;
    setState(() => busy = true);
    try { await QuangNetwork.toggle(); }
    on PlatformException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Hãy lưu cấu hình trước khi bật'))); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Map<String, dynamic>>(
    valueListenable: QuangNetwork.state,
    builder: (context, value, _) {
      final on = value['enabled'] == true;
      return Tooltip(message: on ? 'Tắt VPN ứng dụng' : 'Bật VPN ứng dụng', triggerMode: TooltipTriggerMode.manual, child: GestureDetector(
        onLongPress: () async { await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const QuangProxyScreen())); await _refresh(); },
        child: IconButton(key: const ValueKey('quangtv-home-vpn'),
          iconSize: widget.compact ? 20 : null,
          padding: widget.compact ? EdgeInsets.zero : const EdgeInsets.all(8),
          constraints: widget.compact ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
          onPressed: busy ? null : _toggle,
          icon: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(on ? Icons.vpn_lock : Icons.vpn_lock_outlined, color: on ? Colors.green : null)),
      ));
    },
  );
}
