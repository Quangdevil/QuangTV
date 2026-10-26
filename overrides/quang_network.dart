import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One application transport state shared by home, settings and Dart HTTP clients.
class QuangNetwork {
  static const bridge = MethodChannel('quangtv/browser');
  static final state = ValueNotifier<Map<String, dynamic>>({'enabled': false});
  static bool get enabled => state.value['enabled'] == true;
  static void update(Map<String, dynamic>? value) { if (value != null) state.value = Map.of(value); }
  static Future<void> refresh() async { update(await bridge.invokeMapMethod<String, dynamic>('proxyGet')); }
  static Future<void> install() async {
    HttpOverrides.global = _AppHttpOverrides();
    bridge.setMethodCallHandler((call) async {
      if (call.method == 'proxyChanged') update(Map<String, dynamic>.from(call.arguments as Map));
    });
    try { await refresh(); }
    on MissingPluginException { /* Other platforms use the normal direct transport. */ }
    on PlatformException { update({'enabled': true, 'localPort': 9, 'error': true}); }
  }
  static Future<void> toggle() async {
    await refresh();
    update(await bridge.invokeMapMethod<String, dynamic>('proxyToggle', {'enabled': !enabled}));
  }
  static String route(Uri url) {
    if (!enabled || ['localhost', '127.0.0.1', '::1', '[::1]'].contains(url.host)) return 'DIRECT';
    final port = state.value['localPort'] as int? ?? 9;
    return 'PROXY 127.0.0.1:${port > 0 ? port : 9}';
  }
}
class _AppHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => super.createHttpClient(context)..findProxy = QuangNetwork.route;
}
