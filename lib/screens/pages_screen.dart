import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../models/pdf_options.dart';
import '../models/scan_session.dart';
import '../services/export_service.dart';
import '../services/page_manager.dart';
import '../services/pdf_service.dart';
import '../services/session_store.dart';
import '../theme/app_theme.dart';
import '../widgets/move_copy_target_sheet.dart';
import '../widgets/pdf_options_dialog.dart';
import '../widgets/rename_session_dialog.dart';
import 'photo_viewer_screen.dart';

enum _MenuAction { shareImages }

class PagesScreen extends StatefulWidget {
  const PagesScreen({
    super.key,
    required this.session,
    this.allowPageManagement = false,
  });

  final ScanSession session;
  final bool allowPageManagement;

  @override
  State<PagesScreen> createState() => _PagesScreenState();
}

class _PagesScreenState extends State<PagesScreen> {
  bool _creatingPdf = false;
  bool _selecting = false;
  bool _working = false;
  final Set<ScanPage> _selected = Set.identity();
  final _scrollController = ScrollController();
  final _gridKey = GlobalKey();
  ScanPage? _dragging;
  Offset? _dragPointer;
  Timer? _autoScrollTimer;

  List<ScanPage> get _pages => widget.session.pages;

  List<ScanPage> get _selectedPages => [
    for (final page in _pages)
      if (_selected.contains(page)) page,
  ];

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final page = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, page);
    });
    unawaited(_saveSession());
  }

  Future<void> _saveSession() async {
    try {
      await SessionStore.save(widget.session);
    } catch (_) {}
  }

  Future<void> _openPage(int index) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PhotoViewerScreen(session: widget.session, initialIndex: index),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _rename() async {
    final changed = await showRenameSessionDialog(context, widget.session);
    if (changed && mounted) {
      setState(() {});
    }
  }

  Future<void> _createPdf() async {
    final options = await showPdfOptionsSheet(context);
    if (options == null || !mounted) {
      return;
    }
    setState(() => _creatingPdf = true);
    final save = options.destination == PdfDestination.save;
    var built = false;
    try {
      final file = await PdfService.buildPdf(
        List.of(_pages),
        options: options,
        title: widget.session.customTitle,
      );
      built = true;
      if (save) {
        final saved = await ExportService.savePdf(file);
        if (saved && mounted) {
          _showMessage('PDF guardado.');
        }
      } else {
        final bytes = await file.readAsBytes();
        await Printing.sharePdf(
          bytes: bytes,
          filename: file.uri.pathSegments.last,
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage(
        save && built
            ? 'No se pudo guardar el PDF.'
            : 'No se pudo crear el PDF.',
      );
    } finally {
      if (mounted) {
        setState(() => _creatingPdf = false);
      }
    }
  }

  Future<void> _shareImages(List<ScanPage> pages) async {
    if (_working || pages.isEmpty) {
      return;
    }
    setState(() => _working = true);
    try {
      final count = await ExportService.shareImages(
        pages,
        title: widget.session.title,
      );
      if (mounted && count < pages.length) {
        _showMessage(
          'Se compartieron las primeras ${ExportService.maxSharedImages} '
          'páginas.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage('No se pudo compartir.');
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  void _startSelection([ScanPage? page]) {
    setState(() {
      _selecting = true;
      _selected.clear();
      if (page != null) {
        _selected.add(page);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggle(ScanPage page) {
    setState(() {
      if (!_selected.remove(page)) {
        _selected.add(page);
      }
    });
  }

  void _toggleAll() {
    setState(() {
      if (_selected.length == _pages.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_pages);
      }
    });
  }

  static String _pagesLabel(int count) =>
      count == 1 ? '1 página' : '$count páginas';

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _runAction(Future<String> Function() action) async {
    if (_working) {
      return;
    }
    setState(() => _working = true);
    String? message;
    try {
      message = await action();
    } catch (_) {
      message = null;
    }
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    if (!mounted) {
      return;
    }
    setState(() {
      _working = false;
      _selecting = false;
      _selected.clear();
    });
    _showMessage(message ?? 'No se pudo completar la acción.');
    if (_pages.isEmpty) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _duplicate() async {
    final pages = _selectedPages;
    await _runAction(() async {
      await PageManager.duplicate(widget.session, pages);
      return pages.length == 1
          ? 'Se duplicó 1 página.'
          : 'Se duplicaron ${pages.length} páginas.';
    });
  }

  Future<void> _transfer({required bool move}) async {
    final pages = _selectedPages;
    final label = _pagesLabel(pages.length);
    final target = await showMoveCopyTargetSheet(
      context,
      current: widget.session,
      title: move ? 'Mover $label a…' : 'Copiar $label a…',
    );
    if (target == null || !mounted) {
      return;
    }
    await _runAction(() async {
      final existing = target.session;
      final ScanSession destination;
      if (existing == null) {
        destination = move
            ? await PageManager.extractToNew(widget.session, pages)
            : await PageManager.copyToNew(widget.session, pages);
      } else {
        destination = existing;
        if (move) {
          await PageManager.moveTo(widget.session, pages, destination);
        } else {
          await PageManager.copyTo(widget.session, pages, destination);
        }
      }
      final title = destination.title;
      if (move) {
        return pages.length == 1
            ? 'Se movió 1 página a «$title».'
            : 'Se movieron ${pages.length} páginas a «$title».';
      }
      return pages.length == 1
          ? 'Se copió 1 página a «$title».'
          : 'Se copiaron ${pages.length} páginas a «$title».';
    });
  }

  Future<void> _extract() async {
    final pages = _selectedPages;
    await _runAction(() async {
      await PageManager.extractToNew(widget.session, pages);
      return pages.length == 1
          ? 'Se extrajo 1 página a un documento nuevo.'
          : 'Se extrajeron ${pages.length} páginas a un documento nuevo.';
    });
  }

  Future<void> _delete() async {
    final pages = _selectedPages;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Eliminar ${_pagesLabel(pages.length)}?'),
        content: const Text('Se borrarán sus archivos.'),
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
    await _runAction(() async {
      await PageManager.deletePages(widget.session, pages);
      return pages.length == 1
          ? 'Se eliminó 1 página.'
          : 'Se eliminaron ${pages.length} páginas.';
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _movePage(ScanPage page, int targetIndex) {
    final oldIndex = _pages.indexOf(page);
    if (oldIndex < 0 || oldIndex == targetIndex) {
      return;
    }
    _onReorder(oldIndex, targetIndex);
  }

  void _onDragStarted(ScanPage page) {
    HapticFeedback.selectionClick();
    setState(() => _dragging = page);
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _autoScroll(),
    );
  }

  void _onDragFinished() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _dragPointer = null;
    if (mounted) {
      setState(() => _dragging = null);
    }
  }

  void _autoScroll() {
    final pointer = _dragPointer;
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (pointer == null ||
        box == null ||
        !box.hasSize ||
        !_scrollController.hasClients) {
      return;
    }
    final local = box.globalToLocal(pointer);
    const edge = 72.0;
    const maxStep = 14.0;
    double step = 0;
    if (local.dy < edge) {
      step = -maxStep * (1 - (local.dy.clamp(0, edge) / edge));
    } else if (local.dy > box.size.height - edge) {
      final inside = (box.size.height - local.dy).clamp(0, edge);
      step = maxStep * (1 - inside / edge);
    }
    if (step == 0) {
      return;
    }
    final position = _scrollController.position;
    final next = (position.pixels + step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next != position.pixels) {
      _scrollController.jumpTo(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting && !_working,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting && !_working) {
          _exitSelection();
        }
      },
      child: Scaffold(
        appBar: _selecting ? _buildSelectionBar() : _buildAppBar(),
        body: _pages.isEmpty ? _buildEmpty() : _buildGrid(),
        bottomNavigationBar: _selecting
            ? _buildActionBar()
            : _buildBottomBar(),
      ),
    );
  }

  String _subtitle() {
    final label = _pagesLabel(_pages.length);
    final when = _formatWhen(widget.session.createdAt);
    return when == null ? label : '$label · $when';
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      toolbarHeight: 64,
      titleSpacing: 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.session.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.display(20, color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            _subtitle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
              height: 1.25,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _rename,
          tooltip: 'Renombrar',
          icon: const Icon(Icons.edit_outlined),
        ),
        if (widget.allowPageManagement && _pages.isNotEmpty)
          IconButton(
            onPressed: _startSelection,
            tooltip: 'Seleccionar páginas',
            icon: const Icon(Icons.check_box_outlined),
          ),
        PopupMenuButton<_MenuAction>(
          tooltip: 'Más opciones',
          enabled: _pages.isNotEmpty && !_working && !_creatingPdf,
          onSelected: (action) {
            switch (action) {
              case _MenuAction.shareImages:
                _shareImages(List.of(_pages));
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _MenuAction.shareImages,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.image_outlined),
                title: Text('Compartir como imágenes'),
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionBar() {
    final count = _selected.length;
    final allSelected = _pages.isNotEmpty && count == _pages.length;
    return AppBar(
      toolbarHeight: 64,
      backgroundColor: AppColors.chip,
      leading: IconButton(
        onPressed: _working ? null : _exitSelection,
        tooltip: 'Cerrar',
        icon: const Icon(Icons.close),
      ),
      titleSpacing: 4,
      title: Text(
        count == 1 ? '1 seleccionada' : '$count seleccionadas',
        style: AppTheme.display(20, color: AppColors.ink),
      ),
      actions: [
        IconButton(
          onPressed: _working ? null : _toggleAll,
          tooltip: allSelected ? 'Quitar selección' : 'Seleccionar todo',
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
        ),
        const SizedBox(width: 4),
      ],
      bottom: _working
          ? const PreferredSize(
              preferredSize: Size.fromHeight(2),
              child: LinearProgressIndicator(minHeight: 2),
            )
          : null,
    );
  }

  Widget _buildBarFrame({required Widget child, EdgeInsets? padding}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: padding ?? const EdgeInsets.fromLTRB(12, 10, 20, 12),
          child: child,
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    final enabled = _selected.isNotEmpty && !_working;
    final actions = [
      _buildAction(
        Icons.copy_outlined,
        'Duplicar',
        enabled ? _duplicate : null,
      ),
      _buildAction(
        Icons.drive_file_move_outlined,
        'Mover',
        enabled ? () => _transfer(move: true) : null,
      ),
      _buildAction(
        Icons.file_copy_outlined,
        'Copiar',
        enabled ? () => _transfer(move: false) : null,
      ),
      _buildAction(Icons.call_split, 'Extraer', enabled ? _extract : null),
      _buildAction(
        Icons.delete_outline,
        'Eliminar',
        enabled ? _delete : null,
        destructive: true,
      ),
      _buildAction(
        Icons.share_outlined,
        'Compartir',
        enabled ? () => _shareImages(_selectedPages) : null,
      ),
    ];
    return _buildBarFrame(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / actions.length;
          final itemWidth = width < 64 ? 64.0 : width;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final action in actions)
                  SizedBox(width: itemWidth, child: action),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAction(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    bool destructive = false,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: destructive
            ? Theme.of(context).colorScheme.error
            : AppColors.ink,
        disabledForegroundColor: AppColors.outline,
        minimumSize: const Size(56, 56),
        padding: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final canShare = _pages.isNotEmpty && !_working && !_creatingPdf;
    return _buildBarFrame(
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: _buildAction(
              Icons.share_outlined,
              'Imágenes',
              canShare ? () => _shareImages(List.of(_pages)) : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: _pages.isEmpty || _creatingPdf ? null : _createPdf,
              icon: _creatingPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, size: 20),
              label: Text(_creatingPdf ? 'Generando PDF…' : 'Crear PDF'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 48,
              color: AppColors.outline,
            ),
            SizedBox(height: 16),
            Text(
              'Aún no hay páginas en esta sesión.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return Listener(
      onPointerUp: (_) {
        if (_dragging != null) {
          _onDragFinished();
        }
      },
      onPointerCancel: (_) {
        if (_dragging != null) {
          _onDragFinished();
        }
      },
      child: GridView.builder(
        key: _gridKey,
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 172,
        ),
        itemCount: _pages.length,
        itemBuilder: (context, index) {
          final page = _pages[index];
          return DragTarget<ScanPage>(
            key: ObjectKey(page),
            onWillAcceptWithDetails: (details) => details.data != page,
            onAcceptWithDetails: (details) => _movePage(details.data, index),
            builder: (context, candidates, _) => LayoutBuilder(
              builder: (context, constraints) => _buildPageTile(
                page,
                index,
                Size(constraints.maxWidth, constraints.maxHeight),
                hovered: candidates.isNotEmpty,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPageTile(
    ScanPage page,
    int index,
    Size size, {
    required bool hovered,
  }) {
    final selected = _selected.contains(page);
    final dragging = identical(_dragging, page);
    final highlighted = selected || hovered;
    final last = _pages.length - 1;
    final tile = Material(
      color: AppColors.tile,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: highlighted ? AppColors.teal : AppColors.border,
          width: highlighted ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _selecting
            ? (_working ? null : () => _toggle(page))
            : () => _openPage(index),
        onLongPress: widget.allowPageManagement && !_selecting
            ? () => _startSelection(page)
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildPageImage(page),
            Positioned(left: 10, bottom: 10, child: _buildNumberBadge(index)),
            if (_selecting)
              Positioned(
                top: 2,
                right: 2,
                child: Checkbox(
                  value: selected,
                  onChanged: _working ? null : (_) => _toggle(page),
                  side: const BorderSide(color: AppColors.outline, width: 2),
                  fillColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? AppColors.teal
                        : Colors.white,
                  ),
                ),
              )
            else
              Positioned(top: 4, right: 4, child: _buildDragHandle(page, size)),
          ],
        ),
      ),
    );
    return Semantics(
      label: 'Página ${index + 1}',
      selected: _selecting ? selected : null,
      customSemanticsActions: _selecting
          ? null
          : {
              if (index > 0)
                const CustomSemanticsAction(label: 'Mover antes'): () =>
                    _movePage(page, index - 1),
              if (index < last)
                const CustomSemanticsAction(label: 'Mover después'): () =>
                    _movePage(page, index + 1),
            },
      child: AnimatedOpacity(
        opacity: dragging ? 0.35 : 1,
        duration: const Duration(milliseconds: 150),
        child: tile,
      ),
    );
  }

  Widget _buildPageImage(ScanPage page) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Center(
        child: Image.file(
          File(page.currentPath),
          key: ValueKey(page.currentPath),
          cacheWidth: 360,
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
      ),
    );
  }

  Widget _buildNumberBadge(int index) {
    return ExcludeSemantics(
      child: Container(
        constraints: const BoxConstraints(minWidth: 26),
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle(ScanPage page, Size size) {
    const handle = SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: _paperShadow,
          ),
          child: Padding(
            padding: EdgeInsets.all(5),
            child: Icon(
              Icons.drag_indicator,
              size: 20,
              color: AppColors.inkSoft,
            ),
          ),
        ),
      ),
    );
    return Tooltip(
      message: 'Arrastra para mover la página',
      child: Draggable<ScanPage>(
        data: page,
        maxSimultaneousDrags: _working ? 0 : 1,
        dragAnchorStrategy: (draggable, context, position) =>
            Offset(size.width - 26, 26),
        onDragStarted: () => _onDragStarted(page),
        onDragUpdate: (details) => _dragPointer = details.globalPosition,
        onDragEnd: (_) => _onDragFinished(),
        feedback: _buildDragFeedback(page, size),
        child: handle,
      ),
    );
  }

  Widget _buildDragFeedback(ScanPage page, Size size) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Material(
        color: AppColors.tile,
        elevation: 8,
        shadowColor: const Color(0x660E2522),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.teal, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildPageImage(page),
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
