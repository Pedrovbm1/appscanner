import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/scan_session.dart';
import '../services/page_editor.dart';
import '../services/session_store.dart';
import 'annotate_screen.dart';
import 'ocr_screen.dart';

class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.session,
    required this.initialIndex,
  });

  final ScanSession session;
  final int initialIndex;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _pageController;
  final Map<int, TransformationController> _transforms = {};
  final Map<int, int> _versions = {};
  late int _index;
  bool _rotating = false;
  bool _zoomed = false;
  bool _popScheduled = false;
  int _dragStartIndex = 0;

  List<ScanPage> get _pages => widget.session.pages;

  @override
  void initState() {
    super.initState();
    final last = _pages.isEmpty ? 0 : _pages.length - 1;
    _index = widget.initialIndex.clamp(0, last);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _transforms.values) {
      controller.removeListener(_onTransformChanged);
      controller.dispose();
    }
    super.dispose();
  }

  TransformationController _transformFor(int index) {
    return _transforms.putIfAbsent(index, () {
      final controller = TransformationController();
      controller.addListener(_onTransformChanged);
      return controller;
    });
  }

  void _onTransformChanged() {
    final controller = _transforms[_index];
    final zoomed =
        controller != null && controller.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed && mounted) {
      setState(() => _zoomed = zoomed);
    }
  }

  void _onInteractionStart(ScaleStartDetails details) {
    _dragStartIndex = _index;
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    if (_zoomed || _rotating || details.pointerCount != 1) {
      return;
    }
    if (!_pageController.hasClients) {
      return;
    }
    final position = _pageController.position;
    final next = (position.pixels - details.focalPointDelta.dx).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _pageController.jumpTo(next);
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    if (_zoomed || _rotating || !_pageController.hasClients) {
      return;
    }
    final current = _pageController.page ?? _index.toDouble();
    final velocity = details.velocity.pixelsPerSecond.dx;
    var target = current.round();
    if (velocity < -300) {
      target = _dragStartIndex + 1;
    } else if (velocity > 300) {
      target = _dragStartIndex - 1;
    }
    target = target.clamp(0, _pages.length - 1);
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _onPageChanged(int index) {
    _transforms[_index]?.value = Matrix4.identity();
    _transforms[index]?.value = Matrix4.identity();
    setState(() {
      _index = index;
      _zoomed = false;
    });
  }

  Future<void> _refreshPage(int index, ScanPage page) async {
    await FileImage(File(page.currentPath)).evict();
    if (!mounted) {
      return;
    }
    _transforms[index]?.value = Matrix4.identity();
    setState(() => _versions[index] = (_versions[index] ?? 0) + 1);
  }

  Future<void> _rotate() async {
    final index = _index;
    final page = _pages[index];
    final previous = page.currentPath;
    setState(() => _rotating = true);
    try {
      final newPath = await PageEditor.rotateClockwise(page);
      page.currentPath = newPath;
      await SessionStore.save(widget.session);
      await PageEditor.deleteOcrSidecars(previous);
      await PageEditor.deleteOcrSidecars(newPath);
      unawaited(SessionStore.cleanup(widget.session));
      await _refreshPage(index, page);
    } catch (_) {
      page.currentPath = previous;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo rotar la página.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _rotating = false);
      }
    }
  }

  Future<void> _openAnnotate() async {
    final index = _index;
    final page = _pages[index];
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AnnotateScreen(
          session: widget.session,
          page: page,
        ),
      ),
    );
    if (saved == true && mounted) {
      await _refreshPage(index, page);
    }
  }

  void _openOcr() {
    final page = _pages[_index];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OcrScreen(image: File(page.currentPath)),
      ),
    );
  }

  Widget _buildPage(BuildContext context, int index) {
    final path = _pages[index].currentPath;
    return InteractiveViewer(
      transformationController: _transformFor(index),
      panEnabled: _zoomed,
      minScale: 1,
      maxScale: 5,
      onInteractionStart: _onInteractionStart,
      onInteractionUpdate: _onInteractionUpdate,
      onInteractionEnd: _onInteractionEnd,
      child: Center(
        child: Image.file(
          File(path),
          key: ValueKey('$path#${_versions[index] ?? 0}'),
          gaplessPlayback: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      if (!_popScheduled) {
        _popScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
      return const Scaffold(backgroundColor: Colors.black);
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Página ${_index + 1} de ${_pages.length}'),
        actions: [
          IconButton(
            onPressed: _rotating ? null : _rotate,
            tooltip: 'Rotar',
            icon: _rotating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.rotate_right),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _pages.length,
              onPageChanged: _onPageChanged,
              itemBuilder: _buildPage,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _rotating ? null : _openAnnotate,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white38,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.draw_outlined),
                      label: const Text('Anotar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _rotating ? null : _openOcr,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.text_snippet_outlined),
                      label: const Text('Extraer texto'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
