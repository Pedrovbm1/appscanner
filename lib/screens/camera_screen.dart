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
import '../widgets/document_guide_painter.dart';
import '../widgets/import_progress_dialog.dart';
import '../widgets/live_quad_painter.dart';
import 'crop_screen.dart';
import 'filter_screen.dart';
import 'pages_screen.dart';

enum _ImportSource { photos, pdf }

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, RouteAware {
  static const double _topBarHeight = 48;
  static const double _bottomControlsHeight = 200;

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
    unawaited(_restoreSettings());
    _initFuture = _initCamera();
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
        setState(() => _error = 'No se encontró ninguna cámara en este dispositivo.');
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
        const SnackBar(content: Text('No se pudo tomar la foto. Intenta de nuevo.')),
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
        const SnackBar(content: Text('No se pudo activar el disparo automático.')),
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
    if (!_autoCapture || _busy || !(ModalRoute.of(context)?.isCurrent ?? false)) {
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

  Future<void> _openCrop(File file) async {
    final croppedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => CropScreen(file: file)),
    );
    if (!mounted) {
      return;
    }
    if (croppedPath != null) {
      final filteredPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => FilterScreen(source: File(croppedPath)),
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
    final croppedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => CropScreen(file: file)),
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
        const SnackBar(content: Text('Frente listo. Ahora captura el reverso.')),
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
        outputPath: '$dirPath${Platform.pathSeparator}page_${frontNumber}_id.jpg',
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
    final filteredPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => FilterScreen(source: File(composedPath)),
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (_error != null) {
            return _errorView();
          }
          final ready = snapshot.connectionState == ConnectionState.done && _controller != null;
          if (!ready) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          return _cameraView();
        },
      ),
    );
  }

  Widget _cameraView() {
    final controller = _controller!;
    return Stack(
      fit: StackFit.expand,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final previewRect = _previewRectFor(
              constraints.biggest,
              _portraitPreviewSize(controller),
              MediaQuery.paddingOf(context),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                _containPreview(controller, previewRect),
                CustomPaint(
                  painter: DocumentGuidePainter(
                    ratio: _mode.frameRatio,
                    previewRect: previewRect,
                  ),
                ),
                ?_liveQuad(controller, previewRect),
              ],
            );
          },
        ),
        SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_session?.pages.length ?? 0),
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Cerrar',
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _busy ? null : _toggleBatch,
                    icon: Icon(
                      _batchMode ? Icons.burst_mode : Icons.burst_mode_outlined,
                      color: Colors.white,
                    ),
                    tooltip: 'Modo lote',
                  ),
                  IconButton(
                    onPressed: _busy ? null : _toggleAutoCapture,
                    icon: Icon(
                      _autoCapture
                          ? Icons.camera_enhance
                          : Icons.camera_enhance_outlined,
                      color: Colors.white,
                    ),
                    tooltip: 'Disparo automático',
                  ),
                  IconButton(
                    onPressed: _toggleFlash,
                    icon: Icon(
                      _flashOn ? Icons.flashlight_on : Icons.flashlight_off,
                      color: Colors.white,
                    ),
                    tooltip: 'Linterna',
                  ),
                ],
              ),
              const Spacer(),
              if (_batchActive) ...[
                _batchPill(),
                const SizedBox(height: 8),
              ],
              _hintRow(),
              const SizedBox(height: 12),
              _modeSelector(),
              const SizedBox(height: 10),
              SizedBox(
                height: 84,
                child: Row(
                  children: [
                    Expanded(child: Center(child: _thumbnailSlot())),
                    _shutterButton(),
                    Expanded(child: Center(child: _galleryButton())),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF00796B).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Lote · ${_batchFilter.label}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _hintRow() {
    final waiting = _mode == CaptureMode.id && _waitingForBack;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _autoCapture && _stableCount > 0
            ? 'Mantén el documento quieto…'
            : waiting
                ? 'Ahora el reverso'
                : _mode.hint,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
    if (!waiting) {
      return pill;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        pill,
        const SizedBox(width: 8),
        TextButton(
          onPressed: _busy ? null : _cancelId,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.black.withValues(alpha: 0.55),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Cancelar ID'),
        ),
      ],
    );
  }

  Widget _modeSelector() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: CaptureMode.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final mode = CaptureMode.values[index];
          final selected = mode == _mode;
          return Center(
            child: Material(
              color: selected
                  ? Colors.teal
                  : Colors.white.withValues(alpha: 0.18),
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _busy ? null : () => _selectMode(mode),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    mode.label,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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
    return GestureDetector(
      onTap: _busy ? null : _onShutterTap,
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _busy ? Colors.white54 : Colors.white,
            ),
            child: _busy
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _thumbnailSlot() {
    final shot = _lastShot;
    if (shot == null) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white38, width: 2),
        ),
        child: const Icon(Icons.image_outlined, color: Colors.white54),
      );
    }
    return GestureDetector(
      onTap: () {
        final session = _session;
        if (session == null || session.pages.isEmpty) {
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PagesScreen(session: session)),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(shot, width: 52, height: 52, fit: BoxFit.cover),
      ),
    );
  }

  Widget _galleryButton() {
    return IconButton(
      onPressed: _busy ? null : _chooseImport,
      icon: const Icon(Icons.photo_library_outlined, color: Colors.white70),
      tooltip: 'Galería',
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 20),
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
    );
  }
}
