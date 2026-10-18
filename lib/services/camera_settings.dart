import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class CameraSettings {
  const CameraSettings({this.autoCapture = false, this.batchMode = false});

  final bool autoCapture;
  final bool batchMode;

  static const _fileName = 'camera_settings.json';
  static Future<void> _pending = Future.value();

  static Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<CameraSettings> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return const CameraSettings();
      }
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) {
        return const CameraSettings();
      }
      return CameraSettings(
        autoCapture: data['autoCapture'] == true,
        batchMode: data['batchMode'] == true,
      );
    } catch (_) {
      return const CameraSettings();
    }
  }

  static Future<void> save({
    required bool autoCapture,
    required bool batchMode,
  }) {
    final next = _pending.then(
      (_) => _write(autoCapture: autoCapture, batchMode: batchMode),
    );
    _pending = next;
    return next;
  }

  static Future<void> _write({
    required bool autoCapture,
    required bool batchMode,
  }) async {
    try {
      final file = await _file();
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({'autoCapture': autoCapture, 'batchMode': batchMode}),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (_) {}
  }
}
