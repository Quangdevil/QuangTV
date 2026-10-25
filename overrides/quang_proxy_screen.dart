import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  String type = 'http';
  bool enabled = false, busy = true, hasPassword = false;
  String message = '';
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final value = await bridge.invokeMapMethod<String, dynamic>('proxyGet') ?? {};
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
      if (!mounted) return false;
      setState(() { hasPassword = value?['hasPassword'] == true; message = enabled ? 'Đã bật proxy cho trình duyệt và player native. Mở lại trang/video để áp dụng.' : 'Đã tắt proxy của QuangTV.'; });
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
    setState(() => message = 'Đã nhập từ bộ nhớ tạm. Chọn đúng loại proxy, bật và kiểm tra kết nối.');
  }
  @override
  void dispose() { for (final c in [host, port, user, password]) { c.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Proxy QuangTV')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Áp dụng cho HTTP/HTTPS trong trình duyệt, QuangTube, player Media3/VLC và tải video. Không phải VPN toàn điện thoại; không chuyển các ứng dụng khác hoặc UDP/WebRTC qua proxy.'),
      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Bật/tắt bằng biểu tượng proxy trên trang chính hoặc thanh trình duyệt. Màn hình này lưu cấu hình.')),
      OutlinedButton.icon(onPressed: busy ? null : _paste, icon: const Icon(Icons.content_paste), label: const Text('Dán IP:cổng:tài khoản:mật khẩu')),
      DropdownButtonFormField<String>(initialValue: type, key: ValueKey(type), decoration: const InputDecoration(labelText: 'Loại proxy'), items: const [DropdownMenuItem(value: 'http', child: Text('HTTP (hỗ trợ web HTTPS)')), DropdownMenuItem(value: 'https', child: Text('HTTPS (TLS tới proxy)')), DropdownMenuItem(value: 'socks5', child: Text('SOCKS5 (DNS qua proxy)'))], onChanged: busy ? null : (value) => setState(() => type = value ?? 'http')),
      TextField(controller: host, enabled: !busy, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'Máy chủ / IP')),
      TextField(controller: port, enabled: !busy, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cổng')),
      TextField(controller: user, enabled: !busy, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'Tài khoản')),
      TextField(controller: password, enabled: !busy, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: 'Mật khẩu', hintText: hasPassword ? 'Để trống để giữ mật khẩu đã lưu' : null)),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : _save, child: const Text('Lưu cấu hình')),
      if (busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      if (message.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(message)),
      const Text('Tài khoản/mật khẩu lưu mã hóa bằng khóa Android Keystore trên máy này. Kiểm tra IP gửi yêu cầu HTTPS tới api.ipify.org qua proxy; không gửi mật khẩu tới dịch vụ kiểm tra. Khi proxy lỗi, hãy sửa cấu hình hoặc tắt proxy để dùng mạng trực tiếp. Tải qua proxy cần giữ QuangTV đang chạy.'),
    ])),
  );
}
