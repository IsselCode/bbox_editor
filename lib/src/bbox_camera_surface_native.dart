import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bbox_camera_config.dart';
import 'bbox_editor_controller.dart';
import 'bbox_editor_enums.dart';
import 'bbox_frame_data.dart';
import 'bbox_live_frame_encoder.dart';

class BBoxCameraSurface extends StatefulWidget {
  const BBoxCameraSurface({
    super.key,
    required this.controller,
    required this.config,
    required this.onFrameReady,
    required this.onEditableFrameChanged,
    required this.onError,
    required this.onResumePreview,
    this.onLiveFrame,
    this.onCapturedFrame,
  });

  final BBoxEditorController controller;
  final BBoxCameraConfig config;
  final ValueChanged<Size> onFrameReady;
  final ValueChanged<bool> onEditableFrameChanged;
  final ValueChanged<Object> onError;
  final VoidCallback onResumePreview;
  final ValueChanged<BBoxFrameData>? onLiveFrame;
  final ValueChanged<BBoxFrameData>? onCapturedFrame;

  @override
  State<BBoxCameraSurface> createState() => _BBoxCameraSurfaceState();
}

class _BBoxCameraSurfaceState extends State<BBoxCameraSurface>
    with WidgetsBindingObserver {
  final Object _cameraBindingOwner = Object();
  CameraController? _cameraController;
  Uint8List? _capturedBytes;
  Size? _capturedSize;
  Object? _error;
  bool _initializing = true;
  bool _imageStreamStarted = false;
  bool _encodingFrame = false;
  bool _disposed = false;
  bool _captureInProgress = false;
  int _cameraGeneration = 0;
  _LiveFrameRequest? _pendingFrameRequest;
  _LiveFrameRequest? _activeFrameRequest;
  BBoxFrameData? _lastLiveFrame;

  bool get _isCaptureMode => widget.config.mode == BBoxCameraMode.captureStill;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.attachCamera(
      owner: _cameraBindingOwner,
      capture: _capturePhotoFromController,
      resumePreview: _resumePreviewFromController,
    );
    widget.controller.attachSourceFrameAccess(
      owner: _cameraBindingOwner,
      getCurrentFrame: _getCurrentFrameFromController,
      getCapturedFrame: _getCapturedFrameFromController,
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      widget.controller.attachNextFrameRequest(
        owner: _cameraBindingOwner,
        request: _requestNextFrame,
      );
    }
    _initializeCamera();
  }

  @override
  void didUpdateWidget(covariant BBoxCameraSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.detachCamera(_cameraBindingOwner);
      oldWidget.controller.detachSourceFrameAccess(_cameraBindingOwner);
      widget.controller.attachCamera(
        owner: _cameraBindingOwner,
        capture: _capturePhotoFromController,
        resumePreview: _resumePreviewFromController,
      );
      widget.controller.attachSourceFrameAccess(
        owner: _cameraBindingOwner,
        getCurrentFrame: _getCurrentFrameFromController,
        getCapturedFrame: _getCapturedFrameFromController,
      );
      if (defaultTargetPlatform == TargetPlatform.android) {
        widget.controller.attachNextFrameRequest(
          owner: _cameraBindingOwner,
          request: _requestNextFrame,
        );
      }
    }
    if (oldWidget.config == widget.config) return;

    if (oldWidget.config.mode != widget.config.mode) {
      _reinitializeCamera();
      return;
    }

    if (_requiresCameraReinitialize(oldWidget.config, widget.config)) {
      _reinitializeCamera();
      return;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_suspendCamera());
    } else if (state == AppLifecycleState.resumed &&
        _cameraController == null &&
        !_initializing) {
      _initializeCamera();
    }
  }

  Future<void> _reinitializeCamera() async {
    _cancelFrameRequests();
    await _disposeController();
    if (mounted) {
      setState(() {
        _capturedBytes = null;
        _capturedSize = null;
        _error = null;
        _initializing = true;
      });
    }
    widget.controller.updateCameraState(
      isAttached: true,
      isPreviewActive: false,
      isCaptureFrozen: false,
      canCapture: false,
      canResumePreview: false,
    );
    widget.onEditableFrameChanged(false);
    await _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final generation = ++_cameraGeneration;
    CameraController? initializedController;
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
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.nv21
            : null,
      );
      initializedController = controller;

      await controller.initialize();

      if (!mounted || _disposed || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.android && !_isCaptureMode) {
        await controller.startImageStream(_handleCameraImage);
        _imageStreamStarted = true;
      }

      setState(() {
        _cameraController = controller;
        _error = null;
        _initializing = false;
      });

      widget.controller.updateCameraState(
        isAttached: true,
        isPreviewActive: true,
        isCaptureFrozen: false,
        canCapture: _isCaptureMode,
        canResumePreview: false,
      );
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
      await initializedController?.dispose();
      if (!mounted) return;
      setState(() {
        _error = error;
        _initializing = false;
      });
      widget.controller.updateCameraState(
        isAttached: true,
        isPreviewActive: false,
        isCaptureFrozen: false,
        canCapture: false,
        canResumePreview: false,
      );
      widget.onEditableFrameChanged(false);
      widget.onError(error);
    }
  }

  Future<void> _capturePhoto() async {
    final controller = _cameraController;
    if (_captureInProgress ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    _captureInProgress = true;
    final restartStream = _imageStreamStarted && !_isCaptureMode;
    _cancelFrameRequests();

    try {
      if (restartStream) await _stopImageStream();
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final size = await _decodeImageSize(bytes);
      if (!mounted) return;
      setState(() {
        _capturedBytes = bytes;
        _capturedSize = size;
      });
      widget.controller.updateCameraState(
        isAttached: true,
        isPreviewActive: false,
        isCaptureFrozen: true,
        canCapture: false,
        canResumePreview: true,
      );
      final frame = BBoxFrameData(
        bytes: bytes,
        sourceResolution: _displaySizeFor(size),
        timestamp: DateTime.now(),
        mimeType: 'image/jpeg',
        sourceType: BBoxFrameSourceType.cameraCapture,
      );
      widget.controller.updateCapturedSourceFrame(frame);
      widget.onCapturedFrame?.call(frame);
      widget.onFrameReady(_displaySizeFor(size));
      widget.onEditableFrameChanged(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
      widget.controller.updateCameraState(
        isAttached: true,
        isPreviewActive: false,
        isCaptureFrozen: false,
        canCapture: false,
        canResumePreview: false,
      );
      widget.onEditableFrameChanged(false);
      widget.onError(error);
    } finally {
      try {
        if (restartStream &&
            mounted &&
            !_disposed &&
            controller.value.isInitialized &&
            !_imageStreamStarted) {
          await controller.startImageStream(_handleCameraImage);
          _imageStreamStarted = true;
        }
      } catch (_) {
        _imageStreamStarted = false;
      }
      _captureInProgress = false;
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
    widget.controller.updateCameraState(
      isAttached: true,
      isPreviewActive: true,
      isCaptureFrozen: false,
      canCapture: _isCaptureMode,
      canResumePreview: false,
    );
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

  Future<BBoxFrameData?> _getCurrentFrameFromController() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return _captureLiveFrameWithPicture();
    }
    return _lastLiveFrame;
  }

  Future<BBoxFrameData?> _captureLiveFrameWithPicture() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return null;
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final size = await _decodeImageSize(bytes);
      return BBoxFrameData(
        bytes: bytes,
        sourceResolution: _displaySizeFor(size),
        timestamp: DateTime.now(),
        mimeType: 'image/jpeg',
        sourceType: BBoxFrameSourceType.cameraLive,
      );
    } catch (_) {
      return null;
    }
  }

  Future<BBoxFrameData?> _getCapturedFrameFromController() async {
    final bytes = _capturedBytes;
    final size = _capturedSize;
    if (bytes == null || size == null) return null;
    return BBoxFrameData(
      bytes: bytes,
      sourceResolution: _displaySizeFor(size),
      timestamp: DateTime.now(),
      mimeType: 'image/jpeg',
      sourceType: BBoxFrameSourceType.cameraCapture,
    );
  }

  Future<BBoxFrameData?> _requestNextFrame(Duration timeout) {
    if (defaultTargetPlatform != TargetPlatform.android ||
        _isCaptureMode ||
        _disposed) {
      return Future.value(_lastLiveFrame);
    }
    final active = _activeFrameRequest;
    if (active != null && !active.completed) return active.completer.future;
    final pending = _pendingFrameRequest;
    if (pending != null && !pending.completed) return pending.completer.future;

    final request = _LiveFrameRequest(
      generation: _cameraGeneration,
      timeout: timeout,
    );
    _pendingFrameRequest = request;
    request.timer = Timer(request.timeout, () {
      if (request.completed) return;
      request.completed = true;
      if (identical(_pendingFrameRequest, request)) {
        _pendingFrameRequest = null;
      }
      if (!request.completer.isCompleted) request.completer.complete(null);
    });
    return request.completer.future;
  }

  void _handleCameraImage(CameraImage image) {
    final request = _pendingFrameRequest;
    final continuous = widget.onLiveFrame != null;
    if ((!continuous && (request == null || request.completed)) ||
        _encodingFrame ||
        _disposed) {
      return;
    }
    if (request != null && request.generation != _cameraGeneration) return;

    if (request != null) {
      _pendingFrameRequest = null;
      _activeFrameRequest = request;
    }
    _encodingFrame = true;
    final acquisitionStart = Stopwatch()..start();
    final raw = _copyCameraImage(image, acquisitionStart);
    final generation = _cameraGeneration;
    unawaited(_encodeAndComplete(raw, request, generation));
  }

  Future<void> _encodeAndComplete(
    BBoxRawLiveFrame raw,
    _LiveFrameRequest? request,
    int generation,
  ) async {
    try {
      final encoded = await encodeBBoxLiveFrame(raw);
      if (!mounted ||
          _disposed ||
          generation != _cameraGeneration ||
          (request?.completed ?? false)) {
      return;
      }
      final frame = BBoxFrameData(
        bytes: encoded.bytes,
        sourceResolution: Size(
          encoded.width.toDouble(),
          encoded.height.toDouble(),
        ),
        timestamp: DateTime.now(),
        mimeType: 'image/jpeg',
        sourceType: BBoxFrameSourceType.cameraLive,
      );
      _lastLiveFrame = frame;
      widget.controller.updateCurrentSourceFrame(frame);
      widget.onLiveFrame?.call(frame);
      if (request != null && !request.completer.isCompleted) {
        request.completer.complete(frame);
      }
    } catch (error, stackTrace) {
      if (request != null &&
          !request.completer.isCompleted &&
          !request.completed) {
        request.completer.completeError(error, stackTrace);
      }
    } finally {
      request?.timer?.cancel();
      if (request != null && identical(_activeFrameRequest, request)) {
        _activeFrameRequest = null;
      }
      _encodingFrame = false;
    }
  }

  BBoxRawLiveFrame _copyCameraImage(
    CameraImage image,
    Stopwatch acquisitionStopwatch,
  ) {
    acquisitionStopwatch.stop();
    final rotation = _rotationFor(_cameraController);
    final mirror =
        _cameraController?.description.lensDirection ==
        CameraLensDirection.front;
    return BBoxRawLiveFrame(
      width: image.width,
      height: image.height,
      planes: image.planes
          .map((plane) => Uint8List.fromList(plane.bytes))
          .toList(growable: false),
      rowStrides: image.planes
          .map((plane) => plane.bytesPerRow)
          .toList(growable: false),
      pixelStrides: image.planes
          .map((plane) => plane.bytesPerPixel ?? 1)
          .toList(growable: false),
      rotation: rotation,
      mirror: mirror,
      quality: widget.config.liveFrameJpegQuality,
      acquisitionDuration: acquisitionStopwatch.elapsed,
      targetWidth: widget.config.liveFrameTargetResolution?.width.round(),
      targetHeight: widget.config.liveFrameTargetResolution?.height.round(),
    );
  }

  int _rotationFor(CameraController? controller) {
    if (controller == null) return 0;
    final orientation = switch (controller.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      // camera_android_camerax reports the landscape orientations using this
      // convention for ImageAnalysis/CameraImage.
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    final sensor = controller.description.sensorOrientation;
    final isFront =
        controller.description.lensDirection == CameraLensDirection.front;
    return isFront
        ? (sensor + orientation) % 360
        : (sensor - orientation + 360) % 360;
  }

  Future<void> _stopImageStream() async {
    final controller = _cameraController;
    if (!_imageStreamStarted || controller == null) return;
    _imageStreamStarted = false;
    try {
      if (controller.value.isInitialized &&
          controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Stopping is intentionally idempotent across lifecycle transitions.
    }
  }

  Future<void> _suspendCamera() async {
    _cameraGeneration++;
    _cancelFrameRequests();
    await _stopImageStream();
    final controller = _cameraController;
    _cameraController = null;
    await controller?.dispose();
  }

  void _cancelFrameRequests() {
    for (final request in <_LiveFrameRequest?>[
      _pendingFrameRequest,
      _activeFrameRequest,
    ]) {
      if (request == null) continue;
      request.timer?.cancel();
      request.completed = true;
      if (!request.completer.isCompleted) request.completer.complete(null);
    }
    _pendingFrameRequest = null;
    if (!_encodingFrame) _activeFrameRequest = null;
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
    final controller = _cameraController;
    final hadCapturedFrame = _capturedBytes != null;

    setState(() {
      _capturedBytes = null;
      _capturedSize = null;
      _error = null;
    });

    if (hadCapturedFrame) {
      widget.onResumePreview();
    }

    final previewSize = controller?.value.previewSize;
    final editable = nextMode == BBoxCameraMode.livePreview;
    widget.controller.updateCameraState(
      isAttached: true,
      isPreviewActive: true,
      isCaptureFrozen: false,
      canCapture: !editable,
      canResumePreview: false,
    );
    _notifyModeTransition(
      editable: editable,
      resolution: previewSize == null ? null : _displaySizeFor(previewSize),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (controller != null && controller.value.isInitialized) {
        unawaited(_resumeNativePreview(controller));
      }
    });
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
      child: Center(
        child: child,
      ),
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
            child: Image.memory(bytes, fit: BoxFit.contain),
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
    final aspectRatio = controller.value.aspectRatio;
    return _buildLiveSurface(
      ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: 1,
              height: 1 / aspectRatio,
              child: CameraPreview(controller),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _disposeController() async {
    _cameraGeneration++;
    _cancelFrameRequests();
    await _stopImageStream();
    final controller = _cameraController;
    _cameraController = null;
    await controller?.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelFrameRequests();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.detachCamera(_cameraBindingOwner);
    widget.controller.detachSourceFrameAccess(_cameraBindingOwner);
    widget.controller.detachNextFrameRequest(_cameraBindingOwner);
    unawaited(_disposeController());
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

class _LiveFrameRequest {
  _LiveFrameRequest({required this.generation, required this.timeout});

  final int generation;
  final Duration timeout;
  final Completer<BBoxFrameData?> completer = Completer<BBoxFrameData?>();
  Timer? timer;
  bool completed = false;
}
