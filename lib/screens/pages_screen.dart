import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/pdf_options.dart';
import '../models/scan_session.dart';
import '../services/export_service.dart';
import '../services/page_manager.dart';
import '../services/pdf_service.dart';
import '../services/session_store.dart';
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
    final options = await showPdfOptionsDialog(context);
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
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting && !_working,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting && !_working) {
          _exitSelection();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: _selecting ? _buildSelectionBar() : _buildAppBar(),
        body: _pages.isEmpty ? _buildEmpty() : _buildList(),
        bottomNavigationBar: _selecting
            ? _buildActionBar()
            : _buildPdfButton(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF121212),
      foregroundColor: Colors.white,
      title: Text(widget.session.title, overflow: TextOverflow.ellipsis),
      actions: [
        if (widget.allowPageManagement && _pages.isNotEmpty)
          IconButton(
            onPressed: _startSelection,
            tooltip: 'Seleccionar',
            icon: const Icon(Icons.checklist),
          ),
        IconButton(
          onPressed: _rename,
          tooltip: 'Renombrar',
          icon: const Icon(Icons.edit_outlined),
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
      ],
    );
  }

  PreferredSizeWidget _buildSelectionBar() {
    final count = _selected.length;
    final allSelected = _pages.isNotEmpty && count == _pages.length;
    return AppBar(
      backgroundColor: const Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      leading: IconButton(
        onPressed: _working ? null : _exitSelection,
        tooltip: 'Cerrar',
        icon: const Icon(Icons.close),
      ),
      title: Text(count == 1 ? '1 seleccionada' : '$count seleccionadas'),
      actions: [
        IconButton(
          onPressed: _working ? null : _toggleAll,
          tooltip: allSelected ? 'Quitar selección' : 'Seleccionar todo',
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
        ),
      ],
      bottom: _working
          ? const PreferredSize(
              preferredSize: Size.fromHeight(2),
              child: LinearProgressIndicator(minHeight: 2),
            )
          : null,
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
      _buildAction(Icons.delete_outline, 'Eliminar', enabled ? _delete : null),
      _buildAction(
        Icons.share,
        'Compartir',
        enabled ? () => _shareImages(_selectedPages) : null,
      ),
    ];
    return Material(
      color: const Color(0xFF1E1E1E),
      child: SafeArea(
        child: Padding(
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
        ),
      ),
    );
  }

  Widget _buildAction(IconData icon, String label, VoidCallback? onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white38,
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _pages.isEmpty || _creatingPdf ? null : _createPdf,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          icon: _creatingPdf
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text(_creatingPdf ? 'Generando PDF…' : 'Crear PDF'),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Aún no hay páginas en esta sesión.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildList() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      buildDefaultDragHandles: false,
      itemCount: _pages.length,
      onReorderItem: _onReorder,
      proxyDecorator: (child, index, animation) =>
          Material(color: Colors.transparent, child: child),
      itemBuilder: (context, index) {
        final page = _pages[index];
        final selected = _selected.contains(page);
        return Padding(
          key: ObjectKey(page),
          padding: EdgeInsets.only(bottom: index == _pages.length - 1 ? 0 : 12),
          child: ListTile(
            tileColor: selected ? Colors.white24 : Colors.white10,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(page.currentPath),
                key: ValueKey(page.currentPath),
                width: 52,
                height: 68,
                cacheWidth: 156,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 52,
                  height: 68,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white38,
                  ),
                ),
              ),
            ),
            title: Text(
              'Página ${index + 1}',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _selecting
                  ? 'Toca para seleccionar'
                  : 'Toca para ver o extraer texto',
              style: const TextStyle(color: Colors.white54),
            ),
            trailing: _selecting
                ? Checkbox(
                    value: selected,
                    onChanged: _working ? null : (_) => _toggle(page),
                    side: const BorderSide(color: Colors.white54, width: 2),
                  )
                : ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle, color: Colors.white54),
                    ),
                  ),
            onTap: _selecting
                ? (_working ? null : () => _toggle(page))
                : () => _openPage(index),
            onLongPress: widget.allowPageManagement && !_selecting
                ? () => _startSelection(page)
                : null,
          ),
        );
      },
    );
  }
}
