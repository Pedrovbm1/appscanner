import 'dart:io';

import 'package:flutter/material.dart';

import '../services/image_filters.dart';

class FilterScreen extends StatefulWidget {
  const FilterScreen({super.key, required this.source});

  final File source;

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
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Image.file(File(path), fit: BoxFit.contain, gaplessPlayback: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Filtros'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(child: _preview()),
                if (_processing || _saving)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
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
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: ScanFilter.values.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final filter = ScanFilter.values[index];
                      final isSelected = filter == _selected;
                      return Center(
                        child: GestureDetector(
                          onTap: () => _select(filter),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF00796B)
                                  : Colors.white10,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF69F0AE)
                                    : Colors.white24,
                              ),
                            ),
                            child: Text(
                              filter.label,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontWeight:
                                    isSelected ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
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
    );
  }
}
