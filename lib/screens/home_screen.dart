import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/scan_session.dart';
import '../services/import_service.dart';
import '../services/search_service.dart';
import '../services/session_store.dart';
import '../widgets/rename_session_dialog.dart';
import 'camera_screen.dart';
import 'pages_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ScanSession> _sessions = [];
  bool _loading = true;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  List<SearchHit>? _hits;
  bool _hasOcrText = true;
  int? _storageBytes;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _recoverLostPhotos();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _searchActive => _searchController.text.trim().isNotEmpty;

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _searchGeneration++;
      setState(() {
        _hits = null;
        _hasOcrText = true;
      });
      return;
    }
    setState(() {});
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(query),
    );
  }

  void _onQuerySubmitted(String value) {
    final query = value.trim();
    if (query.isEmpty) {
      return;
    }
    _searchDebounce?.cancel();
    _runSearch(query);
  }

  void _clearSearch() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    _onQueryChanged('');
  }

  Future<void> _runSearch(String query) async {
    final generation = ++_searchGeneration;
    final sessions = _sessions;
    List<SearchHit> hits;
    bool hasOcrText;
    try {
      (hits, hasOcrText) = await (
        SearchService.search(sessions, query),
        SearchService.hasOcrText(sessions),
      ).wait;
    } catch (_) {
      hits = [];
      hasOcrText = true;
    }
    if (!mounted || generation != _searchGeneration) {
      return;
    }
    setState(() {
      _hits = hits;
      _hasOcrText = hasOcrText;
    });
  }

  Future<void> _loadStorage() async {
    int? bytes;
    try {
      bytes = await SessionStore.storageBytes();
    } catch (_) {
      bytes = null;
    }
    if (!mounted) {
      return;
    }
    setState(() => _storageBytes = bytes);
  }

  String _formatBytes(int bytes) {
    const megabyte = 1024 * 1024;
    if (bytes < megabyte) {
      return '${(bytes / 1024).ceil()} KB';
    }
    return '${(bytes / megabyte).toStringAsFixed(1)} MB';
  }

  Future<void> _recoverLostPhotos() async {
    final List<XFile> files;
    try {
      final lost = await ImagePicker().retrieveLostData();
      final lostFiles = lost.files;
      if (lost.isEmpty || lostFiles == null || lostFiles.isEmpty) {
        return;
      }
      files = lostFiles;
    } catch (_) {
      return;
    }
    final ScanSession session;
    try {
      final sessionDir = await ImportService.createSessionDir();
      session = ScanSession(dirPath: sessionDir.path);
      for (final file in files) {
        final number = session.pages.length + 1;
        try {
          final imported = await ImportService.importImage(
            file.path,
            ImportService.pagePath(sessionDir, number),
          );
          session.pages.add(
            ScanPage(originalPath: imported.path, currentPath: imported.path),
          );
        } catch (_) {}
      }
      if (session.pages.isEmpty) {
        try {
          await sessionDir.delete(recursive: true);
        } catch (_) {}
        return;
      }
      await SessionStore.save(session);
    } catch (_) {
      return;
    }
    if (!mounted) {
      return;
    }
    await _loadSessions();
    if (!mounted) {
      return;
    }
    final count = session.pages.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 1 ? 'Se recuperó 1 foto.' : 'Se recuperaron $count fotos.',
        ),
      ),
    );
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await SessionStore.loadAll();
      if (!mounted) {
        return;
      }
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } on MissingPluginException {
      if (!mounted) {
        return;
      }
      setState(() {
        _sessions = [];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sessions = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar los escaneos.')),
      );
    }
    if (!mounted) {
      return;
    }
    _loadStorage();
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _searchDebounce?.cancel();
      _runSearch(query);
    }
  }

  Future<void> _startScan() async {
    final pages = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
    if (!mounted) {
      return;
    }
    if (pages != null && pages > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pages == 1 ? 'Se guardó 1 página.' : 'Se guardaron $pages páginas.',
          ),
        ),
      );
    }
    await _loadSessions();
  }

  Future<void> _openSession(ScanSession session) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PagesScreen(session: session, allowPageManagement: true),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadSessions();
  }

  Future<void> _rename(ScanSession session) async {
    final changed = await showRenameSessionDialog(context, session);
    if (!changed || !mounted) {
      return;
    }
    await _loadSessions();
  }

  Future<void> _confirmDelete(ScanSession session) async {
    final count = session.pages.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar este escaneo?'),
        content: Text(
          count == 1 ? 'Se borrará su página.' : 'Se borrarán sus $count páginas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await SessionStore.delete(session);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo eliminar el escaneo.')),
        );
      }
    }
    if (!mounted) {
      return;
    }
    await _loadSessions();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AppScanner')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
            sliver: SliverToBoxAdapter(child: _buildHeader(context)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
            sliver: SliverToBoxAdapter(child: _buildSearchField(context)),
          ),
          if (_searchActive)
            ..._buildResults(context)
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text('Escaneos anteriores', style: textTheme.titleMedium),
              ),
            ),
            ..._buildHistory(context),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(Icons.document_scanner_outlined, size: 96, color: colors.primary),
        const SizedBox(height: 24),
        Text('Escanea tus documentos', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          'Toma una foto con la guía y guárdala como página de tu documento.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _startScan,
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Nuevo escaneo'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildHistory(BuildContext context) {
    if (_loading) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
      ];
    }
    if (_sessions.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Text(
              'Tus escaneos guardados aparecerán aquí.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ];
    }
    final bytes = _storageBytes;
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bytes == null ? 24 : 8),
        sliver: SliverList.builder(
          itemCount: _sessions.length,
          itemBuilder: (context, index) => _buildTile(context, _sessions[index]),
        ),
      ),
      if (bytes != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Espacio usado: ${_formatBytes(bytes)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildSearchField(BuildContext context) {
    final showOcrHint = _hits != null && !_hasOcrText && _searchActive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SearchBar(
          controller: _searchController,
          hintText: 'Buscar en el texto de tus escaneos',
          leading: const Icon(Icons.search),
          trailing: [
            if (_searchController.text.isNotEmpty)
              IconButton(
                tooltip: 'Borrar búsqueda',
                icon: const Icon(Icons.close),
                onPressed: _clearSearch,
              ),
          ],
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          onSubmitted: _onQuerySubmitted,
        ),
        if (showOcrHint)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Extrae texto de tus páginas para poder buscarlas.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildResults(BuildContext context) {
    final hits = _hits;
    final String heading;
    if (hits == null || hits.isEmpty) {
      heading = 'Resultados';
    } else if (hits.length == 1) {
      heading = '1 coincidencia';
    } else {
      heading = '${hits.length} coincidencias';
    }
    final header = SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      sliver: SliverToBoxAdapter(
        child: Text(heading, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
    if (hits == null || _loading) {
      return [
        header,
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
      ];
    }
    if (hits.isEmpty) {
      return [
        header,
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Text(
              'Sin coincidencias.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ];
    }
    return [
      header,
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        sliver: SliverList.builder(
          itemCount: hits.length,
          itemBuilder: (context, index) => _buildHitTile(context, hits[index]),
        ),
      ),
    ];
  }

  Widget _buildHitTile(BuildContext context, SearchHit hit) {
    final session = hit.session;
    final pages = session.pages;
    final count = pages.length;
    final pageIndex = hit.isTitle ? 0 : hit.pageIndex;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        leading: _buildThumbnail(
          context,
          pageIndex < count ? pages[pageIndex].currentPath : '',
        ),
        title: hit.isTitle
            ? _buildHighlighted(hit, 1)
            : Text(
                '${session.title} · Página ${hit.pageIndex + 1}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        subtitle: hit.isTitle
            ? Text(count == 1 ? '1 página' : '$count páginas')
            : _buildHighlighted(hit, 3),
        onTap: () => _openSession(session),
      ),
    );
  }

  Widget _buildHighlighted(SearchHit hit, int maxLines) {
    final text = hit.snippet;
    final start = min(max(0, hit.matchStart), text.length);
    final end = min(max(start, hit.matchStart + hit.matchLength), text.length);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildThumbnail(BuildContext context, String path) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        File(path),
        width: 40,
        height: 52,
        cacheWidth: 120,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => SizedBox(
          width: 40,
          height: 52,
          child: Icon(Icons.broken_image_outlined, color: colors.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context, ScanSession session) {
    final count = session.pages.length;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        leading: _buildThumbnail(context, session.pages.first.currentPath),
        title: Text(session.title),
        subtitle: Text(count == 1 ? '1 página' : '$count páginas'),
        trailing: PopupMenuButton<String>(
          tooltip: 'Opciones',
          onSelected: (value) {
            if (value == 'rename') {
              _rename(session);
            } else if (value == 'delete') {
              _confirmDelete(session);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Renombrar')),
            PopupMenuItem(value: 'delete', child: Text('Eliminar')),
          ],
        ),
        onTap: () => _openSession(session),
        onLongPress: () => _confirmDelete(session),
      ),
    );
  }
}
