import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scan_session.dart';

class ExportService {
  static const maxSharedImages = 30;

  static Future<bool> savePdf(File pdf) async {
    final bytes = await pdf.readAsBytes();
    final result = await FilePicker.saveFile(
      dialogTitle: 'Guardar PDF',
      fileName: pdf.uri.pathSegments.last,
      bytes: bytes,
      mimeType: 'application/pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    return result != null;
  }

  static Future<int> shareImages(List<ScanPage> pages, {String? title}) async {
    final shared = pages.take(maxSharedImages).toList();
    if (shared.isEmpty) {
      return 0;
    }
    final text = title == null || title.trim().isEmpty ? null : title.trim();
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final page in shared) XFile(page.currentPath)],
        text: text,
        subject: text,
      ),
    );
    return shared.length;
  }
}
