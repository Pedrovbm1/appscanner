import 'dart:io';

import 'package:flutter/material.dart';

import '../services/image_filters.dart';
import '../theme/app_theme.dart';

const _offLabel = Color(0xFFC9D8D4);

class FilterScreen extends StatefulWidget {
  const FilterScreen({super.key, required this.source, this.pageLabel});

  final File source;
  final String? pageLabel;

  static final ValueNotifier<ScanFilter> lastUsed =
      ValueNotifier(ScanFilter.enhance);

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  final Map<ScanFilter, String> _previews = {};
  ScanFilter _selected = ScanFilter.original;
  bool _processing = false;
  bool _saving = false;

  String _previewPathFor(ScanFilter filter) {
    final name = widget.source.path
        .split(Platform.pathSeparator)
        .last
        .replaceFirst(RegExp(r'\.jpg$', caseSensitive: false), '');
    final dir = widget.source.parent.path;
    return '$dir${Platform.pathSeparator}preview_${name}_${filter.name}.jpg';
  }

  Future<void> _select(ScanFilter filter) async {
    if (_processing || _saving) {
      return;
    }
    if (filter == ScanFilter.original || _previews.containsKey(filter)) {
      setState(() => _selected = filter);
      return;
    }
    setState(() {
      _selected = filter;
      _processing = true;
    });
    try {
      final path = await ImageFilters.buildPreview(
        sourcePath: widget.source.path,
        previewPath: _previewPathFor(filter),
        filter: filter,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _previews[filter] = path;
        _processing = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _processing = false;
        _selected = ScanFilter.original;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo aplicar el filtro.')),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    if (_selected == ScanFilter.original) {
      FilterScreen.lastUsed.value = ScanFilter.original;
      Navigator.of(context).pop(widget.source.path);
      return;
    }
    setState(() => _saving = true);
    try {
      final outPath = widget.source.path.replaceFirst(
        RegExp(r'\.jpg$', caseSensitive: false),
        '_${_selected.name}.jpg',
      );
      final saved = await ImageFilters.export(
        sourcePath: widget.source.path,
        outPath: outPath,
        filter: _selected,
      );
      if (!mounted) {
        return;
      }
      FilterScreen.lastUsed.value = _selected;
      Navigator.of(context).pop(saved);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el filtro.')),
      );
    }
  }

  Widget _preview() {
    final path = _selected == ScanFilter.original
        ? widget.source.path
        : _previews[_selected];
    if (path == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.mint));
    }
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Image.file(File(path), fit: BoxFit.contain, gaplessPlayback: true),
      ),
    );
  }

  Widget _filterItem(ScanFilter filter) {
    final isSelected = filter == _selected;
    final look = _thumbLook(filter);
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(filter),
        child: SizedBox(
          width: 66,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 60,
                height: 72,
                padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
                decoration: BoxDecoration(
                  color: look.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppColors.mint : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _thumbLine(0.75, 5, look.ink),
                    for (final w in const [1.0, 0.9, 1.0, 0.65]) ...[
                      const SizedBox(height: 4),
                      _thumbLine(w, 3, look.line),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                filter.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? Colors.white : _offLabel,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbLine(double widthFactor, double height, Color color) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(height: height, color: color),
    );
  }

  ({Color bg, Color ink, Color line}) _thumbLook(ScanFilter filter) => switch (filter) {
        ScanFilter.original => (bg: const Color(0xFFE4DFD4), ink: const Color(0xFF3B3833), line: const Color(0xFF9E998F)),
        ScanFilter.enhance => (bg: const Color(0xFFFBFAF6), ink: const Color(0xFF1C1C1C), line: const Color(0xFF8F8F8F)),
        ScanFilter.grayscale => (bg: const Color(0xFFE2E2E2), ink: const Color(0xFF333333), line: const Color(0xFF9A9A9A)),
        ScanFilter.bw => (bg: Colors.white, ink: Colors.black, line: Colors.black),
        ScanFilter.lighten => (bg: Colors.white, ink: const Color(0xFF5A5A5A), line: const Color(0xFFC4C4C4)),
        ScanFilter.invert => (bg: const Color(0xFF111111), ink: Colors.white, line: const Color(0xFF9A9A9A)),
        ScanFilter.noShadow => (bg: const Color(0xFFF6F6F4), ink: const Color(0xFF202020), line: const Color(0xFF9C9C9C)),
      };

  @override
  Widget build(BuildContext context) {
    final pageLabel = widget.pageLabel;
    return Theme(
      data: AppTheme.camera(Theme.of(context)),
      child: Scaffold(
        backgroundColor: AppColors.camBg,
        appBar: AppBar(
          toolbarHeight: 64,
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Volver al recorte',
          ),
          titleSpacing: 4,
          title: const Text('Filtros'),
          actions: [
            if (pageLabel != null)
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Center(
                  child: Text(
                    pageLabel,
                    style: const TextStyle(fontSize: 14, color: AppColors.camMuted),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                    child: _preview(),
                  ),
                  if (_processing || _saving)
                    Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: const Center(
                        child: CircularProgressIndicator(color: AppColors.mint),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Column(
                children: [
                  SizedBox(
                    height: 92 + MediaQuery.textScalerOf(context).scale(18),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      itemCount: ScanFilter.values.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) =>
                          _filterItem(ScanFilter.values[index]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.check),
                        label: const Text('Guardar página'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
