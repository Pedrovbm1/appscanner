import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/capture_mode.dart';
import '../models/scan_session.dart';
import '../services/import_service.dart';
import '../services/search_service.dart';
import '../services/session_store.dart';
import '../theme/app_theme.dart';
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

  Future<void> _startScan({
    CaptureMode mode = CaptureMode.docs,
    bool openImport = false,
  }) async {
    final pages = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => CameraScreen(initialMode: mode, openImport: openImport),
      ),
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
          count == 1
              ? 'Se borrará su página.'
              : 'Se borrarán sus $count páginas.',
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
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              sliver: SliverToBoxAdapter(child: _buildBrand()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              sliver: SliverToBoxAdapter(child: _buildSearchField(context)),
            ),
            if (!_searchActive)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                sliver: SliverToBoxAdapter(child: _buildModeShortcuts()),
              ),
            if (_searchActive)
              ..._buildResults(context)
            else
              ..._buildHistory(context),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBrand() {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'assets/icon/icon.png',
            width: 36,
            height: 36,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              'AppScanner',
              style: AppTheme.display(24, color: AppColors.ink),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _startScan(openImport: true),
                icon: const Icon(Icons.image_outlined, size: 20),
                label: const Text('Importar'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _startScan,
                  icon: const Icon(Icons.photo_camera_outlined, size: 22),
                  label: const Text('Escanear'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeShortcuts() {
    const icons = {
      CaptureMode.docs: Icons.description_outlined,
      CaptureMode.id: Icons.badge_outlined,
      CaptureMode.card: Icons.credit_card_outlined,
      CaptureMode.slides: Icons.co_present_outlined,
    };
    return Row(
      children: [
        for (final mode in CaptureMode.values) ...[
          if (mode != CaptureMode.values.first) const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: AppColors.chip,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _startScan(mode: mode),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          icons[mode],
                          size: 22,
                          color: AppColors.teal,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          mode.label,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, String? trailing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: AppTheme.display(20, color: AppColors.ink),
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: const TextStyle(fontSize: 14, color: AppColors.muted),
            ),
        ],
      ),
    );
  }

  Widget _buildSpinner() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  List<Widget> _buildHistory(BuildContext context) {
    if (_loading) {
      return [SliverToBoxAdapter(child: _buildSpinner())];
    }
    if (_sessions.isEmpty) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState()),
      ];
    }
    final count = _sessions.length;
    final bytes = _storageBytes;
    return [
      SliverToBoxAdapter(
        child: _buildSectionHeader(
          'Recientes',
          count == 1 ? '1 escaneo' : '$count escaneos',
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, bytes == null ? 24 : 4),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 174,
          ),
          itemCount: count,
          itemBuilder: (context, index) =>
              _buildTile(context, _sessions[index]),
        ),
      ),
      if (bytes != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Espacio usado: ${_formatBytes(bytes)} · '
              'Todo se queda en tu teléfono',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
        ),
    ];
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.chip,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.document_scanner_outlined,
              size: 48,
              color: AppColors.teal,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Escanea tus documentos',
            textAlign: TextAlign.center,
            style: AppTheme.display(24, color: AppColors.ink),
          ),
          const SizedBox(height: 12),
          const Text(
            'Toma una foto con la guía y guárdala como página de tu documento.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tus escaneos guardados aparecerán aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final showOcrHint = _hits != null && !_hasOcrText && _searchActive;
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(26),
      borderSide: const BorderSide(color: _searchBorder, width: 1.5),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          onSubmitted: _onQuerySubmitted,
          style: const TextStyle(fontSize: 16, color: AppColors.ink),
          decoration: InputDecoration(
            hintText: 'Busca por el texto de tus escaneos',
            hintStyle: const TextStyle(fontSize: 16, color: _searchHint),
            filled: true,
            fillColor: Colors.white,
            constraints: const BoxConstraints(minHeight: 52, maxHeight: 52),
            contentPadding: const EdgeInsets.fromLTRB(0, 14, 8, 14),
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 16, right: 10),
              child: Icon(Icons.search, size: 22, color: AppColors.inkSoft),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 48,
              minHeight: 48,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Borrar búsqueda',
                    icon: const Icon(Icons.close, color: AppColors.inkSoft),
                    onPressed: _clearSearch,
                  )
                : null,
            border: pill,
            enabledBorder: pill,
            focusedBorder: pill.copyWith(
              borderSide: const BorderSide(color: AppColors.teal, width: 2),
            ),
          ),
        ),
        if (showOcrHint)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Extrae texto de tus páginas para poder buscarlas.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
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
    final header = SliverToBoxAdapter(
      child: _buildSectionHeader(heading, null),
    );
    if (hits == null || _loading) {
      return [header, SliverToBoxAdapter(child: _buildSpinner())];
    }
    if (hits.isEmpty) {
      return [
        header,
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Sin coincidencias.',
              style: TextStyle(fontSize: 15, color: AppColors.muted),
            ),
          ),
        ),
      ];
    }
    return [
      header,
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        sliver: SliverList.separated(
          itemCount: hits.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openSession(session),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSmallThumbnail(
                pageIndex < count ? pages[pageIndex].currentPath : '',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    DefaultTextStyle.merge(
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                      child: hit.isTitle
                          ? _buildHighlighted(hit, 1)
                          : Text(
                              '${session.title} · Página ${hit.pageIndex + 1}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                    const SizedBox(height: 4),
                    DefaultTextStyle.merge(
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.muted,
                      ),
                      child: hit.isTitle
                          ? Text(count == 1 ? '1 página' : '$count páginas')
                          : _buildHighlighted(hit, 3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.ink,
              backgroundColor: AppColors.mintSoft,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildSmallThumbnail(String path) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 62,
        color: AppColors.tile,
        child: Image.file(
          File(path),
          width: 48,
          height: 62,
          cacheWidth: 144,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.broken_image_outlined, color: AppColors.muted),
        ),
      ),
    );
  }

  Widget _buildPageThumbnail(String path) {
    return Container(
      color: AppColors.tile,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      alignment: Alignment.center,
      child: Image.file(
        File(path),
        cacheWidth: 300,
        fit: BoxFit.contain,
        frameBuilder: (context, child, frame, _) => DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: frame == null ? null : _paperShadow,
          ),
          child: child,
        ),
        errorBuilder: (_, _, _) => const Icon(
          Icons.broken_image_outlined,
          size: 32,
          color: AppColors.muted,
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context, ScanSession session) {
    final count = session.pages.length;
    final pagesLabel = count == 1 ? '1 página' : '$count páginas';
    final when = _formatWhen(session.createdAt);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openSession(session),
        onLongPress: () => _confirmDelete(session),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 112,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPageThumbnail(session.pages.first.currentPath),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Semantics(
                      label: pagesLabel,
                      excludeSemantics: true,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            when ?? pagesLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Opciones',
                      icon: const Icon(
                        Icons.more_vert,
                        size: 20,
                        color: AppColors.inkSoft,
                      ),
                      onSelected: (value) {
                        if (value == 'rename') {
                          _rename(session);
                        } else if (value == 'delete') {
                          _confirmDelete(session);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('Renombrar'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String? _formatWhen(DateTime? date) {
    if (date == null) {
      return null;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final difference = today.difference(day).inDays;
    if (difference == 0) {
      return 'Hoy, $hour:$minute';
    }
    if (difference == 1) {
      return 'Ayer, $hour:$minute';
    }
    final label = '${date.day} ${_months[date.month - 1]}';
    return date.year == now.year ? label : '$label ${date.year}';
  }
}

const _searchBorder = Color(0xFFD3E2DE);
const _searchHint = Color(0xFF5A706C);
const _paperShadow = [
  BoxShadow(color: Color(0x2E0E2522), blurRadius: 6, offset: Offset(0, 2)),
];
const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];
