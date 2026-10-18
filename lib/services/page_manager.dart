import 'dart:async';
import 'dart:io';

import '../models/scan_session.dart';
import 'page_editor.dart';
import 'session_store.dart';

class PageManager {
  static final _numberPattern = RegExp(r'page_(\d+)');
  static final _extensionPattern = RegExp(r'\.[A-Za-z0-9]+$');

  static String _join(String dir, String name) =>
      '$dir${Platform.pathSeparator}$name';

  static String _name(String path) => path.split(RegExp(r'[/\\]')).last;

  static int nextPageNumber(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      return 1;
    }
    var max = 0;
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      for (final match in _numberPattern.allMatches(_name(entity.path))) {
        final number = int.tryParse(match.group(1)!) ?? 0;
        if (number > max) {
          max = number;
        }
      }
    }
    return max + 1;
  }

  static Future<void> duplicate(
    ScanSession session,
    List<ScanPage> pages,
  ) async {
    final selected = _ordered(session, pages);
    var number = nextPageNumber(session.dirPath);
    try {
      for (final page in selected) {
        final copy = await _copyPage(page, session.dirPath, number);
        number += 1;
        session.pages.insert(session.pages.indexOf(page) + 1, copy);
      }
    } finally {
      await SessionStore.save(session);
    }
  }

  static Future<void> copyTo(
    ScanSession source,
    List<ScanPage> pages,
    ScanSession target,
  ) async {
    final selected = _ordered(source, pages);
    await Directory(target.dirPath).create(recursive: true);
    var number = nextPageNumber(target.dirPath);
    try {
      for (final page in selected) {
        target.pages.add(await _copyPage(page, target.dirPath, number));
        number += 1;
      }
    } finally {
      await SessionStore.save(target);
    }
  }

  static Future<void> moveTo(
    ScanSession source,
    List<ScanPage> pages,
    ScanSession target,
  ) async {
    if (_samePath(source.dirPath, target.dirPath)) {
      throw ArgumentError.value(target.dirPath, 'target');
    }
    final selected = _ordered(source, pages);
    await copyTo(source, selected, target);
    await _removePages(source, selected);
  }

  static Future<ScanSession> copyToNew(
    ScanSession source,
    List<ScanPage> pages,
  ) {
    return _intoNew((target) => copyTo(source, pages, target));
  }

  static Future<ScanSession> extractToNew(
    ScanSession source,
    List<ScanPage> pages,
  ) {
    return _intoNew((target) => moveTo(source, pages, target));
  }

  static Future<void> deletePages(
    ScanSession session,
    List<ScanPage> pages,
  ) {
    return _removePages(session, _ordered(session, pages));
  }

  static Future<ScanSession> _intoNew(
    Future<void> Function(ScanSession target) action,
  ) async {
    final target = await SessionStore.create();
    try {
      await action(target);
    } catch (_) {
      if (target.pages.isEmpty) {
        try {
          await SessionStore.delete(target);
        } catch (_) {}
      }
      rethrow;
    }
    return target;
  }

  static List<ScanPage> _ordered(ScanSession session, List<ScanPage> pages) {
    final wanted = Set<ScanPage>.identity()..addAll(pages);
    return [
      for (final page in session.pages)
        if (wanted.contains(page)) page,
    ];
  }

  static Future<ScanPage> _copyPage(
    ScanPage page,
    String dirPath,
    int number,
  ) async {
    final targetPath = _join(
      dirPath,
      'page_$number${_extension(page.currentPath)}',
    );
    await File(page.currentPath).copy(targetPath);
    final sourceOcr = _ocrPath(page.currentPath);
    final targetOcr = _ocrPath(targetPath);
    if (sourceOcr != null &&
        targetOcr != null &&
        await File(sourceOcr).exists()) {
      await File(sourceOcr).copy(targetOcr);
    }
    final sourceJson = PageEditor.ocrJsonPath(page.currentPath);
    final targetJson = PageEditor.ocrJsonPath(targetPath);
    if (sourceJson != page.currentPath &&
        targetJson != targetPath &&
        await File(sourceJson).exists()) {
      await File(sourceJson).copy(targetJson);
    }
    return ScanPage(originalPath: targetPath, currentPath: targetPath);
  }

  static Future<void> _removePages(
    ScanSession session,
    List<ScanPage> selected,
  ) async {
    if (selected.isEmpty) {
      return;
    }
    final removed = Set<ScanPage>.identity()..addAll(selected);
    session.pages.removeWhere(removed.contains);
    if (session.pages.isEmpty) {
      await SessionStore.delete(session);
      return;
    }
    await SessionStore.save(session);
    final keptPaths = {
      for (final page in session.pages) ...[
        page.originalPath,
        page.currentPath,
        ?_ocrPath(page.currentPath),
      ],
    };
    final keptNumbers = {
      for (final page in session.pages) ?_number(page),
    };
    final numbers = {
      for (final page in selected) ?_number(page),
    }.difference(keptNumbers);
    final paths = {
      for (final page in selected) ...[
        page.originalPath,
        page.currentPath,
        ?_ocrPath(page.currentPath),
      ],
    }.difference(keptPaths);
    await _deleteFiles(session.dirPath, numbers, paths, keptPaths);
    unawaited(SessionStore.cleanup(session));
  }

  static Future<void> _deleteFiles(
    String dirPath,
    Set<int> numbers,
    Set<String> paths,
    Set<String> keptPaths,
  ) async {
    final keptNames = {for (final path in keptPaths) _name(path)};
    final patterns = [
      for (final number in numbers) RegExp('^(preview_)?page_$number[._]'),
    ];
    final doomed = {for (final path in paths) _name(path)};
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return;
    }
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = _name(entity.path);
      if (keptNames.contains(name)) {
        continue;
      }
      if (doomed.contains(name) ||
          patterns.any((pattern) => pattern.hasMatch(name))) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  static int? _number(ScanPage page) {
    final match = _numberPattern.firstMatch(_name(page.originalPath));
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  static String _extension(String path) {
    final match = _extensionPattern.firstMatch(_name(path));
    return match?.group(0)?.toLowerCase() ?? '.jpg';
  }

  static String? _ocrPath(String imagePath) {
    if (!_extensionPattern.hasMatch(_name(imagePath))) {
      return null;
    }
    return imagePath.replaceFirst(_extensionPattern, '_ocr.txt');
  }

  static bool _samePath(String a, String b) =>
      _normalize(a) == _normalize(b);

  static String _normalize(String path) =>
      path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
}
