import 'dart:io' show Platform;
import 'dart:ui' show Size;
import 'package:flutter/services.dart';

class PipService {
  static final PipService _instance = PipService._internal();
  factory PipService() => _instance;
  PipService._internal();
  static const _channel = MethodChannel('quangtv/pip');
  bool _isSupported = false;
  bool _isPipActive = false;
  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    try { _isSupported = await _channel.invokeMethod<bool>('supported') ?? false; }
    on PlatformException { _isSupported = false; }
  }
  bool get isSupported => _isSupported;
  bool get isPipActive => _isPipActive;
  Future<bool> enablePip({Rational aspectRatio = const Rational(16, 9)}) async {
    if (!_isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('enter', {'numerator': aspectRatio.numerator, 'denominator': aspectRatio.denominator}) ?? false;
      _isPipActive = result;
      return result;
    } on PlatformException { return false; }
  }
  Future<void> disablePip() async { _isPipActive = false; }
  Future<PiPStatus>? get pipStatusFuture => null;
  Future<bool> togglePip({Rational aspectRatio = const Rational(16, 9)}) async => enablePip(aspectRatio: aspectRatio);
  Rational calculateAspectRatio(Size size) {
    if (size.width <= 0 || size.height <= 0) return const Rational(16, 9);
    final ratio = (size.width / size.height).clamp(0.42, 2.39);
    return Rational((ratio * 1000).round(), 1000);
  }
  Future<void> updatePipParams(Rational aspectRatio) async {}
  void dispose() {}
}
enum PiPStatus { enabled, disabled, unavailable }
class Rational {
  final int numerator;
  final int denominator;
  const Rational(this.numerator, this.denominator);
}
