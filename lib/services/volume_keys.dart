import 'package:flutter/services.dart';

class VolumeKeys {
  static const _channel = MethodChannel('escaner/volume_keys');
  static VoidCallback? _onPressed;

  static Future<void> enable(VoidCallback onPressed) async {
    _onPressed = onPressed;
    _channel.setMethodCallHandler(_handle);
    await _setEnabled(true);
  }

  static Future<void> disable() async {
    _onPressed = null;
    await _setEnabled(false);
  }

  static Future<void> _setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } catch (_) {}
  }

  static Future<void> _handle(MethodCall call) async {
    if (call.method == 'pressed') {
      _onPressed?.call();
    }
  }
}
