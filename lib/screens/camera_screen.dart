import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfx/pdfx.dart';

import '../main.dart';
import '../models/capture_mode.dart';
import '../models/scan_session.dart';
import '../services/camera_settings.dart';
import '../services/document_detector.dart';
import '../services/id_composer.dart';
import '../services/image_filters.dart';
import '../services/import_service.dart';
import '../services/session_store.dart';
import '../services/volume_keys.dart';
import '../theme/app_theme.dart';
import '../widgets/document_guide_painter.dart';
import '../widgets/import_progress_dialog.dart';
import '../widgets/live_quad_painter.dart';
import 'crop_screen.dart';
import 'filter_screen.dart';
import 'pages_screen.dart';

enum _ImportSource { photos, pdf }

const _statusBg = Color(0xD1070B0A);
const _stackBack = Color(0xFF9FB2AD);

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.initialMode = CaptureMode.docs,
    this.openImport = false,
  });

  final CaptureMode initialMode;
  final bool openImport;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, RouteAware {
  static const double _topBarHeight = 48;
  static const double _bottomControlsHeight = 200;
  static const double _previewSideMargin = 12;

  CameraController? _controller;
  Future<void>? _initFuture;
  String? _error;
  bool _flashOn = false;
  bool _busy = false;
  bool _initializing = false;
  File? _lastShot;
  int _pageCount = 0;
  String? _sessionStamp;
  ScanSession? _session;
  CaptureMode _mode = CaptureMode.docs;
  String? _idFrontCropPath;
  int? _idFrontNumber;
  bool _autoCapture = false;
  bool _analyzing = false;
  int _stableCount = 0;
  int _lastAnalysisMs = 0;
  List<Offset>? _lastQuad;
  List<Offset>? _lastShotQuad;
  Size? _lastFrameSize;
  bool _batchMode = false;
  ScanFilter _batchFilter = ScanFilter.enhance;
  bool _settingsTouched = false;

  bool get _waitingForBack => _idFrontCropPath != null;

  bool get _batchActive => _batchMode && _mode != CaptureMode.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mode = widget.initialMode;
    unawaited(_restoreSettings());
    _initFuture = _initCamera();
    if (widget.openImport) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_chooseImport());
        }
      });
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    unawaited(VolumeKeys.disable());
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(_releaseController(controller));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final controller = _controller;
      if (controller == null) {
        return;
      }
      _controller = null;
      _flashOn = false;
      _resetStability();
      unawaited(_releaseController(controller));
      setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      if (_controller != null || _initializing) {
        return;
      }
      setState(() {
        _initFuture = _initCamera();
      });
    }
  }

  Future<void> _restoreSettings() async {
    final settings = await CameraSettings.load();
    if (!mounted || _settingsTouched) {
      return;
    }
    setState(() {
      _autoCapture = settings.autoCapture;
      _batchMode = settings.batchMode;
    });
    if (settings.autoCapture) {
      await _startStream();
    }
  }

  void _saveSettings() {
    _settingsTouched = true;
    unawaited(
      CameraSettings.save(autoCapture: _autoCapture, batchMode: _batchMode),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPush() => unawaited(VolumeKeys.enable(_onVolumePressed));

  @override
  void didPopNext() => unawaited(VolumeKeys.enable(_onVolumePressed));

  @override
  void didPushNext() => unawaited(VolumeKeys.disable());

  void _onVolumePressed() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) {
      return;
    }
    _onShutterTap();
  }

  Future<void> _initCamera() async {
    _initializing = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(
          () => _error = 'No se encontró ninguna cámara en este dispositivo.',
        );
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
      unawaited(_startStream());
    } on CameraException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = switch (e.code) {
          'CameraAccessDenied' => 'Necesitamos permiso para usar la cámara. Actívalo en los Ajustes del sistema.',
          _ => 'No se pudo iniciar la cámara (${e.code}).',
        };
      });
    } finally {
      _initializing = false;
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) {
      return;
    }
    setState(() => _busy = true);
    await _stopStream(controller);
    if (mounted) {
      setState(_resetStability);
    }
    try {
      final shot = await controller.takePicture();
      final sessionDir = await _ensureSessionDir();
      _pageCount += 1;
      final savedPath = _pagePath(sessionDir, _pageCount);
      await shot.saveTo(savedPath);
      final saved = File(savedPath);
      if (!mounted) {
        return;
      }
      if (_mode == CaptureMode.id) {
        setState(() => _busy = false);
        await _handleIdShot(saved, _pageCount);
        return;
      }
      if (_batchActive) {
        final processed = await _processBatch(saved);
        if (!mounted) {
          return;
        }
        if (processed) {
          setState(() => _busy = false);
          return;
        }
      }
      setState(() {
        _lastShot = saved;
        _busy = false;
      });
      await _openCrop(saved);
    } on CameraException {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo tomar la foto. Intenta de nuevo.'),
        ),
      );
    } finally {
      if (mounted) {
        await _startStream();
      }
    }
  }

  Future<bool> _processBatch(File file) async {
    final String finalPath;
    try {
      final corners = await DocumentDetector.detectOrNull(file.path);
      if (corners == null) {
        return false;
      }
      final croppedPath = await DocumentDetector.applyWarp(file.path, corners);
      final filter = _batchFilter;
      finalPath = filter == ScanFilter.original
          ? croppedPath
          : await ImageFilters.export(
              sourcePath: croppedPath,
              outPath: croppedPath.replaceFirst(
                RegExp(r'\.jpg$', caseSensitive: false),
                '_${filter.name}.jpg',
              ),
              filter: filter,
            );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo procesar la página.')),
        );
      }
      return false;
    }
    final session = _session ??= ScanSession(dirPath: file.parent.path);
    session.pages.add(
      ScanPage(originalPath: file.path, currentPath: finalPath),
    );
    unawaited(_saveSession());
    if (!mounted) {
      return true;
    }
    setState(() => _lastShot = File(finalPath));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Página ${session.pages.length} lista'),
          duration: const Duration(milliseconds: 1200),
        ),
      );
    return true;
  }

  void _toggleBatch() {
    setState(() => _batchMode = !_batchMode);
    _saveSettings();
  }

  Future<void> _releaseController(CameraController controller) async {
    await _stopStream(controller);
    await controller.dispose();
  }

  Future<void> _stopStream(CameraController? controller) async {
    if (controller == null ||
        !controller.value.isInitialized ||
        !controller.value.isStreamingImages) {
      return;
    }
    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  Future<void> _startStream() async {
    if (!mounted) {
      return;
    }
    setState(_resetStability);
    final controller = _controller;
    if (!_autoCapture ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isStreamingImages) {
      return;
    }
    try {
      await controller.startImageStream(_onFrame);
    } on CameraException {
      if (!mounted) {
        return;
      }
      setState(() => _autoCapture = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo activar el disparo automático.'),
        ),
      );
    }
  }

  void _resetStability() {
    _stableCount = 0;
    _lastQuad = null;
  }

  Future<void> _toggleAutoCapture() async {
    final next = !_autoCapture;
    setState(() {
      _autoCapture = next;
      _resetStability();
    });
    _saveSettings();
    if (next) {
      await _startStream();
    } else {
      await _stopStream(_controller);
    }
  }

  void _onFrame(CameraImage image) {
    if (_analyzing || !mounted || !_autoCapture || _busy) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAnalysisMs < 700) {
      return;
    }
    _lastAnalysisMs = now;
    if (!(ModalRoute.of(context)?.isCurrent ?? false) || image.planes.isEmpty) {
      if (_stableCount > 0 || _lastQuad != null) {
        setState(_resetStability);
      }
      return;
    }
    _analyzing = true;
    List<Offset>? quad;
    try {
      final plane = image.planes.first;
      quad = DocumentDetector.detectNormalizedInLuma(
        plane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: plane.bytesPerRow,
        minAreaRatio: 0.2,
      );
    } catch (_) {
      quad = null;
    } finally {
      _analyzing = false;
    }
    _lastFrameSize = Size(image.width.toDouble(), image.height.toDouble());
    _updateStability(quad);
  }

  void _updateStability(List<Offset>? quad) {
    final shot = _lastShotQuad;
    if (shot != null) {
      if (quad != null && _isNear(shot, quad, tolerance: 0.08)) {
        if (_lastQuad != null || _stableCount != 0) {
          setState(_resetStability);
        }
        return;
      }
      _lastShotQuad = null;
    }
    final previous = _lastQuad;
    final previousCount = _stableCount;
    final next = quad == null
        ? 0
        : previous != null && _isNear(previous, quad)
        ? _stableCount + 1
        : 1;
    setState(() {
      _lastQuad = quad;
      _stableCount = next;
    });
    if (previousCount == 0 && next == 1) {
      unawaited(HapticFeedback.selectionClick());
    }
    if (next >= 3) {
      unawaited(_autoShoot());
    }
  }

  bool _isNear(List<Offset> a, List<Offset> b, {double tolerance = 0.04}) {
    for (var i = 0; i < a.length; i++) {
      if ((a[i].dx - b[i].dx).abs() > tolerance ||
          (a[i].dy - b[i].dy).abs() > tolerance) {
        return false;
      }
    }
    return true;
  }

  Future<void> _autoShoot() async {
    _analyzing = true;
    _lastShotQuad = _lastQuad;
    setState(_resetStability);
    try {
      await _stopStream(_controller);
    } finally {
      _analyzing = false;
    }
    if (!mounted) {
      return;
    }
    if (!_autoCapture ||
        _busy ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      await _startStream();
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    await _capture();
  }

  Future<Directory> _ensureSessionDir() {
    _sessionStamp ??= DateTime.now().millisecondsSinceEpoch.toString();
    return ImportService.createSessionDir(stamp: _sessionStamp);
  }

  String _pagePath(Directory sessionDir, int number) =>
      ImportService.pagePath(sessionDir, number);

  Future<void> _chooseImport() async {
    if (_busy) {
      return;
    }
    final source = await showModalBottomSheet<_ImportSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galería (fotos)'),
              onTap: () => Navigator.of(sheetContext).pop(_ImportSource.photos),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('PDF'),
              onTap: () => Navigator.of(sheetContext).pop(_ImportSource.pdf),
            ),
          ],
        ),
      ),
    );
    if (!mounted || source == null) {
      return;
    }
    switch (source) {
      case _ImportSource.photos:
        await _importPhotos();
      case _ImportSource.pdf:
        await _importPdf();
    }
  }

  Future<void> _importPhotos() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickMultiImage();
      if (!mounted || picked.isEmpty) {
        return;
      }
      final sessionDir = await _ensureSessionDir();
      for (final image in picked) {
        _pageCount += 1;
        final File file;
        try {
          file = await ImportService.importImage(
            image.path,
            _pagePath(sessionDir, _pageCount),
          );
        } catch (_) {
          _pageCount -= 1;
          rethrow;
        }
        if (!mounted) {
          return;
        }
        setState(() => _lastShot = file);
        await _openCrop(file);
        if (!mounted) {
          return;
        }
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron importar las fotos.')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _importPdf() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    PdfDocument? document;
    NavigatorState? dialogNavigator;
    final progress = ValueNotifier<int>(0);
    var failed = false;
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (!mounted || picked.isEmpty) {
        return;
      }
      final opened = await ImportService.openPdf(picked.first);
      document = opened;
      if (!mounted) {
        return;
      }
      if (opened.pagesCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El PDF no tiene páginas.')),
        );
        return;
      }
      final sessionDir = await _ensureSessionDir();
      if (!mounted) {
        return;
      }
      dialogNavigator = Navigator.of(context, rootNavigator: true);
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ImportProgressDialog(
            progress: progress,
            total: opened.pagesCount,
          ),
        ),
      );
      final firstNumber = _pageCount + 1;
      await ImportService.renderPdfPages(
        opened,
        pathFor: (pageNumber) =>
            _pagePath(sessionDir, firstNumber + pageNumber - 1),
        onPageSaved: (pageNumber, path) {
          progress.value = pageNumber;
          if (!mounted) {
            return;
          }
          setState(() {
            _pageCount = firstNumber + pageNumber - 1;
            _lastShot = File(path);
            _session ??= ScanSession(dirPath: sessionDir.path);
            _session!.pages.add(
              ScanPage(originalPath: path, currentPath: path),
            );
          });
        },
      );
    } catch (_) {
      failed = true;
    } finally {
      dialogNavigator?.pop();
      try {
        await document?.close();
      } catch (_) {}
      progress.dispose();
      unawaited(_saveSession());
      if (mounted) {
        setState(() => _busy = false);
        if (failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo importar el PDF.')),
          );
        }
      }
    }
  }

  String get _nextPageLabel => 'Página ${(_session?.pages.length ?? 0) + 1}';

  Future<void> _openCrop(File file) async {
    final pageLabel = _nextPageLabel;
    final croppedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CropScreen(file: file, pageLabel: pageLabel),
      ),
    );
    if (!mounted) {
      return;
    }
    if (croppedPath != null) {
      final filteredPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) =>
              FilterScreen(source: File(croppedPath), pageLabel: pageLabel),
        ),
      );
      if (!mounted) {
        return;
      }
      final finalPath = filteredPath ?? croppedPath;
      setState(() {
        if (filteredPath != null) {
          _batchFilter = FilterScreen.lastUsed.value;
        }
        _lastShot = File(finalPath);
        _session ??= ScanSession(dirPath: file.parent.path);
        _session!.pages.add(
          ScanPage(originalPath: file.path, currentPath: finalPath),
        );
      });
      unawaited(_saveSession());
      return;
    }
    setState(() {
      _lastShot = null;
      if (_pageCount > 0) {
        _pageCount -= 1;
      }
    });
    try {
      await file.delete();
    } catch (_) {}
  }

  Future<void> _handleIdShot(File file, int number) async {
    final sideLabel = _waitingForBack ? 'Reverso' : 'Frente';
    final croppedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CropScreen(file: file, pageLabel: sideLabel),
      ),
    );
    if (!mounted) {
      return;
    }
    if (croppedPath == null) {
      setState(() {
        if (_pageCount == number) {
          _pageCount -= 1;
        }
      });
      await _deleteFiles([file.path, _cropPathFor(file.path)]);
      return;
    }
    final frontCropPath = _idFrontCropPath;
    final frontNumber = _idFrontNumber;
    if (frontCropPath == null || frontNumber == null) {
      setState(() {
        _idFrontCropPath = croppedPath;
        _idFrontNumber = number;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Frente listo. Ahora captura el reverso.'),
        ),
      );
      return;
    }
    await _composeId(
      frontCropPath: frontCropPath,
      frontNumber: frontNumber,
      backCropPath: croppedPath,
      dirPath: file.parent.path,
    );
  }

  Future<void> _composeId({
    required String frontCropPath,
    required int frontNumber,
    required String backCropPath,
    required String dirPath,
  }) async {
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) {
      return;
    }
    final String composedPath;
    try {
      composedPath = await IdComposer.compose(
        frontPath: frontCropPath,
        backPath: backCropPath,
        outputPath:
            '$dirPath${Platform.pathSeparator}page_${frontNumber}_id.jpg',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _resetId();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo componer la identificación.')),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    final pageLabel = _nextPageLabel;
    final filteredPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            FilterScreen(source: File(composedPath), pageLabel: pageLabel),
      ),
    );
    if (!mounted) {
      return;
    }
    final finalPath = filteredPath ?? composedPath;
    setState(() {
      if (filteredPath != null) {
        _batchFilter = FilterScreen.lastUsed.value;
      }
      _lastShot = File(finalPath);
      _session ??= ScanSession(dirPath: dirPath);
      _session!.pages.add(
        ScanPage(originalPath: composedPath, currentPath: finalPath),
      );
      _resetId();
    });
    unawaited(_saveSession());
  }

  void _resetId() {
    _idFrontCropPath = null;
    _idFrontNumber = null;
  }

  Future<void> _cancelId() async {
    final frontNumber = _idFrontNumber;
    final frontCropPath = _idFrontCropPath;
    if (frontNumber == null || frontCropPath == null) {
      return;
    }
    final frontPath = frontCropPath.replaceFirst(
      RegExp(r'_crop\.jpg$', caseSensitive: false),
      '.jpg',
    );
    setState(() {
      _resetId();
      if (_pageCount == frontNumber) {
        _pageCount -= 1;
      }
    });
    await _deleteFiles([frontPath, frontCropPath]);
  }

  Future<void> _selectMode(CaptureMode mode) async {
    if (mode == _mode || _busy) {
      return;
    }
    if (_waitingForBack) {
      await _cancelId();
      if (!mounted) {
        return;
      }
    }
    setState(() => _mode = mode);
  }

  String _cropPathFor(String path) =>
      path.replaceFirst(RegExp(r'\.jpg$', caseSensitive: false), '_crop.jpg');

  Future<void> _deleteFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> _saveSession() async {
    final session = _session;
    if (session == null) {
      return;
    }
    try {
      await SessionStore.save(session);
    } catch (_) {}
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final next = !_flashOn;
    await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
    if (!mounted) {
      return;
    }
    setState(() => _flashOn = next);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.camera(Theme.of(context)),
      child: Scaffold(
        backgroundColor: AppColors.camBg,
        body: FutureBuilder<void>(
          future: _initFuture,
          builder: (context, snapshot) {
            if (_error != null) {
              return _errorView();
            }
            final ready =
                snapshot.connectionState == ConnectionState.done &&
                _controller != null;
            if (!ready) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.mint),
              );
            }
            return _cameraView();
          },
        ),
      ),
    );
  }

  Widget _cameraView() {
    final controller = _controller!;
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _previewSideMargin),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = MediaQuery.paddingOf(context);
              final previewRect = _previewRectFor(
                constraints.biggest,
                _portraitPreviewSize(controller),
                padding,
              );
              final box = constraints.biggest;
              final bandBottom =
                  box.height - padding.bottom - _bottomControlsHeight;
              final statusBottom = math.min(previewRect.bottom, bandBottom);
              final overlayTop = math.max(
                previewRect.top,
                padding.top + _topBarHeight,
              );
              return ClipRRect(
                clipper: _PreviewClipper(previewRect),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: AppColors.camBg),
                    _containPreview(controller, previewRect),
                    CustomPaint(
                      painter: DocumentGuidePainter(
                        ratio: _mode.frameRatio,
                        previewRect: previewRect,
                      ),
                    ),
                    ?_liveQuad(controller, previewRect),
                    if (_batchActive)
                      Positioned(
                        left: previewRect.left,
                        width: previewRect.width,
                        top: overlayTop + 14,
                        child: Center(child: _batchPill()),
                      ),
                    Positioned(
                      left: previewRect.left + 16,
                      width: math.max(previewRect.width - 32, 0),
                      bottom: box.height - statusBottom + 18,
                      child: Center(child: _statusRow()),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: _topBarHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () =>
                            Navigator.of(context)
                                .pop(_session?.pages.length ?? 0),
                        icon: const Icon(Icons.close, color: AppColors.camText),
                        iconSize: 26,
                        tooltip: 'Cerrar',
                      ),
                      const Spacer(),
                      _togglePill(
                        label: 'Auto',
                        on: _autoCapture,
                        tooltip: 'Disparo automático',
                        onTap: _busy ? null : _toggleAutoCapture,
                        leading: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _autoCapture
                                ? AppColors.mint
                                : AppColors.camMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _togglePill(
                        label: 'Lote',
                        on: _batchMode,
                        tooltip: 'Modo lote',
                        onTap: _busy ? null : _toggleBatch,
                        leading: Icon(
                          Icons.filter_none,
                          size: 17,
                          color: _batchMode
                              ? AppColors.mintSoft
                              : AppColors.camTextSoft,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: _toggleFlash,
                        icon: Icon(
                          _flashOn ? Icons.flash_on : Icons.flash_off,
                          color: _flashOn ? AppColors.mint : AppColors.camText,
                        ),
                        tooltip: _flashOn
                            ? 'Apagar linterna'
                            : 'Encender linterna',
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              _modeSelector(),
              const SizedBox(height: 10),
              SizedBox(
                height: 84,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _galleryButton(),
                      _shutterButton(),
                      _thumbnailSlot(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'También dispara con el botón de volumen',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.camMuted),
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ],
    );
  }

  Widget _togglePill({
    required String label,
    required bool on,
    required String tooltip,
    required VoidCallback? onTap,
    required Widget leading,
  }) {
    final foreground = on ? AppColors.mintSoft : AppColors.camTextSoft;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        toggled: on,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Material(
                color: on ? AppColors.camChipOn : Colors.transparent,
                shape: StadiumBorder(
                  side: on
                      ? BorderSide.none
                      : const BorderSide(
                          color: AppColors.camBorder,
                          width: 1.5,
                        ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        leading,
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Size? _portraitPreviewSize(CameraController controller) {
    final preview = controller.value.previewSize;
    final frame = _lastFrameSize;
    return preview != null
        ? Size(preview.height, preview.width)
        : frame != null
        ? Size(frame.height, frame.width)
        : null;
  }

  Rect _previewRectFor(Size box, Size? portrait, EdgeInsets padding) {
    if (portrait == null || portrait.isEmpty || box.isEmpty) {
      return Offset.zero & box;
    }
    final scale = math.min(
      box.width / portrait.width,
      box.height / portrait.height,
    );
    final width = portrait.width * scale;
    final height = portrait.height * scale;
    final bandTop = padding.top + _topBarHeight;
    final bandHeight =
        box.height - padding.bottom - _bottomControlsHeight - bandTop;
    final double top = height <= bandHeight
        ? bandTop + (bandHeight - height) / 2
        : math.min(
            math.max((box.height - height) / 2, bandTop),
            box.height - height,
          );
    return Rect.fromLTWH((box.width - width) / 2, top, width, height);
  }

  Widget? _liveQuad(CameraController controller, Rect previewRect) {
    final quad = _lastQuad;
    if (!_autoCapture || quad == null) {
      return null;
    }
    return IgnorePointer(
      child: CustomPaint(
        painter: LiveQuadPainter(
          quad: quad,
          stable: _stableCount >= 2,
          previewRect: previewRect,
          sensorOrientation: controller.description.sensorOrientation,
        ),
      ),
    );
  }

  Widget _batchPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.camChipOn.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.filter_none, size: 14, color: AppColors.mintSoft),
          const SizedBox(width: 6),
          Text(
            'Lote · ${_batchFilter.label}',
            style: const TextStyle(
              color: AppColors.mintSoft,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _detectedMessage() => switch (_mode) {
    CaptureMode.docs => 'Hoja detectada. No muevas el teléfono',
    CaptureMode.id => 'Identificación detectada. No muevas el teléfono',
    CaptureMode.card => 'Tarjeta detectada. No muevas el teléfono',
    CaptureMode.slides => 'Diapositiva detectada. No muevas el teléfono',
  };

  Widget _statusRow() {
    final waiting = _mode == CaptureMode.id && _waitingForBack;
    final counting = _autoCapture && _stableCount > 0;
    final pill = Container(
      padding: EdgeInsets.fromLTRB(counting ? 12 : 16, 10, 16, 10),
      decoration: BoxDecoration(
        color: _statusBg,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (counting) ...[
            TweenAnimationBuilder<double>(
              tween: Tween(end: (_stableCount / 3).clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 350),
              builder: (context, value, _) => SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 3,
                  color: AppColors.mint,
                  backgroundColor: AppColors.camBorder,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              counting
                  ? _detectedMessage()
                  : waiting
                  ? 'Ahora el reverso'
                  : _mode.hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.camText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (!waiting) {
      return pill;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: pill),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _busy ? null : _cancelId,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.camText,
            backgroundColor: _statusBg,
            minimumSize: const Size(44, 44),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Cancelar ID'),
        ),
      ],
    );
  }

  Widget _modeSelector() {
    return SizedBox(
      height: 48,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: math.max(constraints.maxWidth - 24, 0),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final mode in CaptureMode.values) ...[
                  if (mode != CaptureMode.values.first)
                    const SizedBox(width: 8),
                  _modeChip(mode),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeChip(CaptureMode mode) {
    final selected = mode == _mode;
    final onTap = _busy ? null : () => _selectMode(mode);
    return Semantics(
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Material(
              color: selected ? AppColors.teal : AppColors.camSurface,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 14),
                  child: Text(
                    mode.label,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.camTextSoft,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _containPreview(CameraController controller, Rect previewRect) {
    final preview = controller.value.previewSize;
    if (preview == null) {
      return Center(child: CameraPreview(controller));
    }
    return Positioned.fromRect(
      rect: previewRect,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: preview.height,
          height: preview.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  void _onShutterTap() {
    unawaited(HapticFeedback.lightImpact());
    unawaited(_capture());
  }

  Widget _shutterButton() {
    return Tooltip(
      message: 'Tomar foto',
      child: Semantics(
        button: true,
        enabled: !_busy,
        child: GestureDetector(
          onTap: _busy ? null : _onShutterTap,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.camText, width: 4),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _busy
                    ? AppColors.camText.withValues(alpha: 0.5)
                    : AppColors.camText,
              ),
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.camBg,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbnailSlot() {
    final shot = _lastShot;
    if (shot == null) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.camBorder, width: 1.5),
        ),
        child: const Icon(
          Icons.description_outlined,
          color: AppColors.camMuted,
        ),
      );
    }
    final count = _session?.pages.length ?? 0;
    final label = count == 1
        ? 'Ver 1 página capturada'
        : 'Ver $count páginas capturadas';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final session = _session;
            if (session == null || session.pages.isEmpty) {
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PagesScreen(session: session)),
            );
          },
          child: SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (count > 1)
                  Positioned(
                    left: 10,
                    top: 4,
                    child: Transform.rotate(
                      angle: 8 * math.pi / 180,
                      child: Container(
                        width: 38,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _stackBack,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 8,
                  top: 4,
                  child: Container(
                    width: 38,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.file(
                      shot,
                      width: 38,
                      height: 48,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                if (count > 0)
                  Positioned(
                    right: -2,
                    top: -4,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.mint,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: AppColors.onMint,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _galleryButton() {
    return IconButton(
      onPressed: _busy ? null : _chooseImport,
      icon: const Icon(Icons.photo_library_outlined),
      tooltip: 'Importar de la galería',
      style: IconButton.styleFrom(
        fixedSize: const Size(56, 56),
        foregroundColor: AppColors.camText,
        disabledForegroundColor: AppColors.camMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: AppColors.camBorder, width: 1.5),
      ),
    );
  }

  Widget _errorView() {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: IconButton(
                onPressed: () =>
                    Navigator.of(context).pop(_session?.pages.length ?? 0),
                icon: const Icon(Icons.close, color: AppColors.camText),
                tooltip: 'Cerrar',
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: const BoxDecoration(
                        color: AppColors.camSurface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.no_photography_outlined,
                        color: AppColors.camTextSoft,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.camTextSoft,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _initFuture = _initCamera();
                        });
                      },
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewClipper extends CustomClipper<RRect> {
  const _PreviewClipper(this.rect);

  final Rect rect;

  @override
  RRect getClip(Size size) =>
      RRect.fromRectAndRadius(rect, const Radius.circular(24));

  @override
  bool shouldReclip(covariant _PreviewClipper oldClipper) =>
      oldClipper.rect != rect;
}
