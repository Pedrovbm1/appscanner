import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/scan_session.dart';

class SessionStore {
  static const _fileName = 'session.json';
  static const _schemaVersion = 1;
  static const _cleanupGrace = Duration(seconds: 30);
  static final _sourcePattern = RegExp(
    r'^page_(\d+)(_id)?\.(jpe?g|png)$',
    caseSensitive: false,
  );
  static final _protectedPattern = RegExp(
    r'^page_\d+(_crop|_id)?\.(jpe?g|png)$',
    caseSensitive: false,
  );
  static final _disposablePattern = RegExp(r'^(preview_|page_\d+_)');
  static final _imagePattern = RegExp(r'\.(jpe?g|png)$', caseSensitive: false);
  static Future<void> _pending = Future.value();

  static String _join(String dir, String name) =>
      '$dir${Platform.pathSeparator}$name';

  static String _name(String path) => path.split(RegExp(r'[/\\]')).last;

  static Future<Directory> _scansDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(_join(docs.path, 'scans'));
  }

  static Future<void> save(ScanSession session) {
    final title = session.customTitle;
    final data = <String, Object>{
      'version': _schemaVersion,
      'title': ?title,
      'pages': [
        for (final page in session.pages)
          {
            'original': _name(page.originalPath),
            'current': _name(page.currentPath),
          },
      ],
    };
    final next = _pending.then((_) => _write(session.dirPath, data));
    _pending = next.catchError((_) {});
    return next;
  }

  static Future<void> _write(String dirPath, Map<String, Object> data) async {
    final file = File(_join(dirPath, _fileName));
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(data), flush: true);
    await temp.rename(file.path);
  }

  static Future<List<ScanSession>> loadAll() async {
    final root = await _scansDir();
    if (!await root.exists()) {
      return [];
    }
    final keys = <Directory, int>{};
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory) {
        keys[entity] = int.tryParse(_name(entity.path)) ??
            (await entity.stat()).modified.millisecondsSinceEpoch;
      }
    }
    final dirs = keys.keys.toList()
      ..sort((a, b) => keys[b]!.compareTo(keys[a]!));
    final sessions = <ScanSession>[];
    for (final dir in dirs) {
      try {
        final session = await _load(dir);
        if (session.pages.isNotEmpty) {
          sessions.add(session);
        }
      } catch (_) {}
    }
    return sessions;
  }

  static Future<ScanSession> create() async {
    final root = await _scansDir();
    var stamp = DateTime.now().millisecondsSinceEpoch;
    while (true) {
      final dir = Directory(_join(root.path, '$stamp'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        return ScanSession(dirPath: dir.path);
      }
      stamp += 1;
    }
  }

  static Future<void> delete(ScanSession session) async {
    await _pending;
    final dir = Directory(session.dirPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  static Future<ScanSession> _load(Directory dir) async {
    final file = File(_join(dir.path, _fileName));
    if (await file.exists()) {
      try {
        return await _fromJson(dir.path, file);
      } catch (_) {}
    }
    return _fromFiles(dir);
  }

  static Future<ScanSession> _fromJson(String dirPath, File file) async {
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final entries = data['pages'] as List<dynamic>;
    final session = ScanSession(dirPath: dirPath);
    final title = data['title'];
    if (title is String && title.trim().isNotEmpty) {
      session.customTitle = title;
    }
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final original = entry['original'];
      final current = entry['current'];
      if (original is! String || current is! String) {
        continue;
      }
      final currentPath = _join(dirPath, _name(current));
      if (!await File(currentPath).exists()) {
        continue;
      }
      session.pages.add(
        ScanPage(
          originalPath: _join(dirPath, _name(original)),
          currentPath: currentPath,
        ),
      );
    }
    return session;
  }

  static Future<ScanSession> _fromFiles(Directory dir) async {
    final files = <String, File>{};
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        files[_name(entity.path)] = entity;
      }
    }
    final originals = <int, File>{};
    final composites = <int, File>{};
    for (final entry in files.entries) {
      final match = _sourcePattern.firstMatch(entry.key);
      if (match == null) {
        continue;
      }
      final n = int.parse(match.group(1)!);
      if (match.group(2) != null) {
        composites[n] = entry.value;
      } else if (!originals.containsKey(n) ||
          entry.key.toLowerCase().endsWith('.jpg')) {
        originals[n] = entry.value;
      }
    }
    final numbers = {...originals.keys, ...composites.keys}.toList()..sort();
    final session = ScanSession(dirPath: dir.path);
    for (final n in numbers) {
      final composite = composites[n];
      final prefix = composite == null ? 'page_${n}_' : 'page_${n}_id_';
      final derived = [
        for (final entry in files.entries)
          if (entry.key.startsWith(prefix) &&
              (composite != null || !entry.key.startsWith('page_${n}_id')) &&
              _imagePattern.hasMatch(entry.key))
            entry.value,
      ];
      if (composite == null &&
          composites.containsKey(n - 1) &&
          derived.every(
            (file) => _name(file.path).toLowerCase() == 'page_${n}_crop.jpg',
          )) {
        continue;
      }
      final original = composite ?? originals[n]!;
      final current = derived.isEmpty ? original : await _newest(derived);
      session.pages.add(
        ScanPage(originalPath: original.path, currentPath: current.path),
      );
    }
    return session;
  }

  static Future<void> cleanup(ScanSession session) async {
    try {
      await _cleanup(session);
    } catch (_) {}
  }

  static Future<void> _cleanup(ScanSession session) async {
    if (session.pages.isEmpty) {
      return;
    }
    final dir = Directory(session.dirPath);
    if (!await dir.exists()) {
      return;
    }
    final candidates = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && _isDisposable(_name(entity.path))) {
        candidates.add(entity);
      }
    }
    for (final file in candidates) {
      try {
        final modified = await file.lastModified();
        if (DateTime.now().difference(modified) < _cleanupGrace) {
          continue;
        }
        if (_referencedNames(session).contains(_name(file.path))) {
          continue;
        }
        await file.delete();
      } catch (_) {}
    }
  }

  static bool _isDisposable(String name) {
    if (name == _fileName || name.endsWith('.tmp')) {
      return false;
    }
    if (_protectedPattern.hasMatch(name)) {
      return false;
    }
    return _disposablePattern.hasMatch(name);
  }

  static Set<String> _referencedNames(ScanSession session) {
    final names = <String>{_fileName};
    for (final page in session.pages) {
      for (final path in [page.originalPath, page.currentPath]) {
        final name = _name(path);
        names
          ..add(name)
          ..add(name.replaceFirst(_imagePattern, '_ocr.txt'))
          ..add(name.replaceFirst(_imagePattern, '_ocr.json'));
      }
    }
    return names;
  }

  static Future<int> storageBytes() async {
    final root = await _scansDir();
    if (!await root.exists()) {
      return 0;
    }
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  static Future<File> _newest(List<File> files) async {
    var best = files.first;
    var bestTime = (await best.stat()).modified;
    for (final file in files.skip(1)) {
      final time = (await file.stat()).modified;
      if (time.isAfter(bestTime) ||
          (time.isAtSameMomentAs(bestTime) &&
              _name(file.path).length > _name(best.path).length)) {
        best = file;
        bestTime = time;
      }
    }
    return best;
  }
}
