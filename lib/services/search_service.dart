import 'dart:io';
import 'dart:math';

import '../models/scan_session.dart';
import 'page_editor.dart';

class SearchHit {
  const SearchHit({
    required this.session,
    required this.pageIndex,
    required this.snippet,
    required this.matchStart,
    required this.matchLength,
  });

  final ScanSession session;
  final int pageIndex;
  final String snippet;
  final int matchStart;
  final int matchLength;

  bool get isTitle => pageIndex < 0;
}

class _PageRef {
  const _PageRef(this.session, this.pageIndex, this.ocrPath);

  final ScanSession session;
  final int pageIndex;
  final String ocrPath;
}

class SearchService {
  static const _batchSize = 16;
  static const _snippetLength = 80;
  static const _accented = 'áàâäãéèêëíìîïóòôöõúùûü';
  static const _plain = 'aaaaaeeeeiiiiooooouuuu';
  static final _whitespace = RegExp(r'\s+');
  static final Map<String, String> _texts = {};
  static final Map<String, String> _normalized = {};
  static final Map<String, String> _keys = {};

  static String normalize(String input) {
    final lower = input.toLowerCase();
    final source = lower.length == input.length ? lower : _lowerEach(input);
    final buffer = StringBuffer();
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      final index = _accented.indexOf(char);
      buffer.write(index < 0 ? char : _plain[index]);
    }
    return buffer.toString();
  }

  static String _lowerEach(String input) {
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      final lower = char.toLowerCase();
      buffer.write(lower.length == 1 ? lower : char);
    }
    return buffer.toString();
  }

  static String _collapse(String text) =>
      text.replaceAll(_whitespace, ' ').trim();

  static List<_PageRef> _pageRefs(List<ScanSession> sessions) => [
    for (final session in sessions)
      for (var i = 0; i < session.pages.length; i++)
        if (PageEditor.ocrTextPath(session.pages[i].currentPath) !=
            session.pages[i].currentPath)
          _PageRef(
            session,
            i,
            PageEditor.ocrTextPath(session.pages[i].currentPath),
          ),
  ];

  static Future<String?> _read(String path) async {
    try {
      final file = File(path);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        return null;
      }
      final key = '$path|${stat.modified.microsecondsSinceEpoch}';
      if (_texts.containsKey(key)) {
        return key;
      }
      final text = _collapse(await file.readAsString());
      final previous = _keys[path];
      if (previous != null) {
        _texts.remove(previous);
        _normalized.remove(previous);
      }
      _keys[path] = key;
      _texts[key] = text;
      _normalized[key] = normalize(text);
      return key;
    } catch (_) {
      return null;
    }
  }

  static Future<List<String?>> _readAll(List<_PageRef> refs) async {
    final keys = <String?>[];
    for (var i = 0; i < refs.length; i += _batchSize) {
      final batch = refs.skip(i).take(_batchSize);
      keys.addAll(await Future.wait(batch.map((ref) => _read(ref.ocrPath))));
    }
    return keys;
  }

  static Future<bool> hasOcrText(List<ScanSession> sessions) async {
    final refs = _pageRefs(sessions);
    for (var i = 0; i < refs.length; i += _batchSize) {
      final batch = refs.skip(i).take(_batchSize);
      final found = await Future.wait(
        batch.map((ref) async {
          try {
            return await File(ref.ocrPath).exists();
          } catch (_) {
            return false;
          }
        }),
      );
      if (found.contains(true)) {
        return true;
      }
    }
    return false;
  }

  static Future<List<SearchHit>> search(
    List<ScanSession> sessions,
    String query,
  ) async {
    final needle = normalize(_collapse(query));
    if (needle.isEmpty) {
      return [];
    }
    final refs = _pageRefs(sessions);
    final keys = await _readAll(refs);
    final pageHits = <ScanSession, List<SearchHit>>{};
    for (var i = 0; i < refs.length; i++) {
      final key = keys[i];
      if (key == null) {
        continue;
      }
      final index = _normalized[key]!.indexOf(needle);
      if (index < 0) {
        continue;
      }
      final ref = refs[i];
      pageHits
          .putIfAbsent(ref.session, () => [])
          .add(
            _snippetHit(
              ref.session,
              ref.pageIndex,
              _texts[key]!,
              index,
              needle.length,
            ),
          );
    }
    final hits = <SearchHit>[];
    for (final session in sessions) {
      final title = _collapse(session.title);
      final titleIndex = normalize(title).indexOf(needle);
      if (titleIndex >= 0) {
        hits.add(
          SearchHit(
            session: session,
            pageIndex: -1,
            snippet: title,
            matchStart: titleIndex,
            matchLength: needle.length,
          ),
        );
      }
      hits.addAll(pageHits[session] ?? const []);
    }
    return hits;
  }

  static SearchHit _snippetHit(
    ScanSession session,
    int pageIndex,
    String text,
    int index,
    int length,
  ) {
    final matchEnd = index + length;
    final context = max(0, (_snippetLength - length) ~/ 2);
    var start = max(0, index - context);
    var end = min(text.length, start + _snippetLength);
    start = max(0, end - _snippetLength);
    end = max(end, matchEnd);
    if (start > 0) {
      final space = text.indexOf(' ', start);
      if (space >= 0 && space < index) {
        start = space + 1;
      }
    }
    if (end < text.length) {
      final space = text.lastIndexOf(' ', end);
      if (space >= matchEnd) {
        end = space;
      }
    }
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return SearchHit(
      session: session,
      pageIndex: pageIndex,
      snippet: '$prefix${text.substring(start, end)}$suffix',
      matchStart: prefix.length + index - start,
      matchLength: length,
    );
  }
}
