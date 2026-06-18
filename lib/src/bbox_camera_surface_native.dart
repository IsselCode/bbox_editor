import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'bbox_camera_config.dart';
import 'bbox_editor_controller.dart';
import 'bbox_editor_enums.dart';

class BBoxCameraSurface extends StatefulWidget {
  const BBoxCameraSurface({
    super.key,
    required this.controller,
    required this.config,
    required this.onFrameReady,
    required this.onEditableFrameChanged,
    required this.onError,
    required this.onResumePreview,
  });

  final BBoxEditorController controller;
  final BBoxCameraConfig config;
  final ValueChanged<Size> onFrameReady;
  final ValueChanged<bool> onEditableFrameChanged;
  final ValueChanged<Object> onError;
  final VoidCallback onResumePreview;

  @override
  State<BBoxCameraSurface> createState() => _BBoxCameraSurfaceState();
}

class _BBoxCameraSurfaceState extends State<BBoxCameraSurface>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  Uint8List? _capturedBytes;
  Size? _capturedSize;
  Object? _error;
  bool _initializing = true;

  bool get _isCaptureMode => widget.config.mode == BBoxCameraMode.captureStill;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.attachCamera(
      capture: _capturePhotoFromController,
      resumePreview: _resumePreviewFromController,
    );
    _initializeCamera();
  }

  @override
  void didUpdateWidget(covariant BBoxCameraSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.detachCamera();
      widget.controller.attachCamera(
        capture: _capturePhotoFromController,
        resumePreview: _resumePreviewFromController,
      );
    }
    if (oldWidget.config == widget.config) return;

    if (_requiresCameraReinitialize(oldWidget.config, widget.config)) {
      _reinitializeCamera();
      return;
    }

    _handleModeChange(oldWidget.config.mode, widget.config.mode);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _reinitializeCamera() async {
    await _disposeController();
    if (mounted) {
      setState(() {
        _capturedBytes = null;
        _capturedSize = null;
        _error = null;
        _initializing = true;
      });
    }
    widget.onEditableFrameChanged(false);
    await _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException(
          'NoCameraAvailable',
          'No hay cámaras disponibles en el dispositivo.',
        );
      }

      final description = cameras.firstWhere(
        (camera) =>
            camera.lensDirection ==
            _mapLensDirection(widget.config.lensDirection),
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        description,
        _mapResolutionPreset(widget.config.resolutionPreset),
        enableAudio: widget.config.enableAudio,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _error = null;
        _initializing = false;
      });

      final previewSize = controller.value.previewSize;
      if (previewSize != null) {
        widget.onFrameReady(_displaySizeFor(previewSize));
      }

      if (_isCaptureMode) {
        widget.onEditableFrameChanged(_capturedBytes != null);
      } else {
        widget.onEditableFrameChanged(true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _initializing = false;
      });
      widget.onEditableFrameChanged(false);
      widget.onError(error);
    }
  }

  Future<void> _capturePhoto() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final size = await _decodeImageSize(bytes);
      if (!mounted) return;
      setState(() {
        _capturedBytes = bytes;
        _capturedSize = size;
      });
      widget.onFrameReady(_displaySizeFor(size));
      widget.onEditableFrameChanged(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
      widget.onEditableFrameChanged(false);
      widget.onError(error);
    }
  }

  void _capturePhotoFromController() {
    unawaited(_capturePhoto());
  }

  void _resumePreviewFromController() {
    if (_capturedBytes == null) return;
    final controller = _cameraController;
    setState(() {
      _capturedBytes = null;
      _capturedSize = null;
      _error = null;
    });
    widget.onEditableFrameChanged(false);
    widget.onResumePreview();
    final previewSize = controller?.value.previewSize;
    final resolution = previewSize == null
        ? null
        : _displaySizeFor(previewSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (controller != null && controller.value.isInitialized) {
        unawaited(_resumeNativePreview(controller));
      }
      if (resolution != null) {
        widget.onFrameReady(resolution);
      }
    });
  }

  Future<void> _resumeNativePreview(CameraController controller) async {
    try {
      await controller.resumePreview();
    } catch (_) {
      // Some platforms do not pause the preview during still capture.
    }
  }

  bool _requiresCameraReinitialize(
    BBoxCameraConfig previous,
    BBoxCameraConfig next,
  ) {
    return previous.lensDirection != next.lensDirection ||
        previous.resolutionPreset != next.resolutionPreset ||
        previous.enableAudio != next.enableAudio;
  }

  void _handleModeChange(BBoxCameraMode previousMode, BBoxCameraMode nextMode) {
    if (previousMode == nextMode) return;

    if (nextMode == BBoxCameraMode.livePreview) {
      setState(() {
        _capturedBytes = null;
        _capturedSize = null;
        _error = null;
      });
      final previewSize = _cameraController?.value.previewSize;
      _notifyModeTransition(
        editable: true,
        resolution: previewSize == null ? null : _displaySizeFor(previewSize),
      );
      return;
    }

    setState(() {
      _capturedBytes = null;
      _capturedSize = null;
      _error = null;
    });
    final previewSize = _cameraController?.value.previewSize;
    _notifyModeTransition(
      editable: false,
      resolution: previewSize == null ? null : _displaySizeFor(previewSize),
    );
  }

  void _notifyModeTransition({required bool editable, Size? resolution}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onEditableFrameChanged(editable);
      if (resolution != null) {
        widget.onFrameReady(resolution);
      }
    });
  }

  Future<Size> _decodeImageSize(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    final image = await completer.future;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    return size;
  }

  Size _displaySizeFor(Size sourceSize) {
    final width = sourceSize.width.abs();
    final height = sourceSize.height.abs();
    if (width == 0 || height == 0) return const Size(1, 1);
    if (height > width) return Size(height, width);
    return Size(width, height);
  }

  Widget _buildLiveSurface(Widget child) {
    return ColoredBox(
      color: Colors.black,
      child: Center(child: child),
    );
  }

  Widget _buildCapturedSurface({
    required Uint8List bytes,
    required Size sourceSize,
  }) {
    final width = sourceSize.width.abs() == 0 ? 1.0 : sourceSize.width.abs();
    final height = sourceSize.height.abs() == 0 ? 1.0 : sourceSize.height.abs();

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: width,
            height: height,
            child: Image.memory(bytes, fit: BoxFit.fill),
          ),
        ),
      ),
    );
  }

  CameraLensDirection _mapLensDirection(BBoxCameraLensDirection direction) {
    switch (direction) {
      case BBoxCameraLensDirection.front:
        return CameraLensDirection.front;
      case BBoxCameraLensDirection.back:
        return CameraLensDirection.back;
      case BBoxCameraLensDirection.external:
        return CameraLensDirection.external;
    }
  }

  ResolutionPreset _mapResolutionPreset(BBoxCameraResolutionPreset preset) {
    switch (preset) {
      case BBoxCameraResolutionPreset.low:
        return ResolutionPreset.low;
      case BBoxCameraResolutionPreset.medium:
        return ResolutionPreset.medium;
      case BBoxCameraResolutionPreset.high:
        return ResolutionPreset.high;
      case BBoxCameraResolutionPreset.veryHigh:
        return ResolutionPreset.veryHigh;
      case BBoxCameraResolutionPreset.ultraHigh:
        return ResolutionPreset.ultraHigh;
      case BBoxCameraResolutionPreset.max:
        return ResolutionPreset.max;
    }
  }

  Widget _buildPreview() {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return _buildLiveSurface(CameraPreview(controller));
  }

  Future<void> _disposeController() async {
    final controller = _cameraController;
    _cameraController = null;
    await controller?.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.detachCamera();
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.camera_alt_outlined, color: Colors.white70),
                const SizedBox(height: 12),
                Text(
                  'Camera unavailable',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_error',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _reinitializeCamera,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPreview(),
        if (_isCaptureMode && _capturedBytes != null)
          _buildCapturedSurface(
            bytes: _capturedBytes!,
            sourceSize: _capturedSize ?? const Size(4, 3),
          ),
      ],
    );
  }
}
