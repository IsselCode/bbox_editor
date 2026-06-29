import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'bbox_camera_config.dart';
import 'bbox_editor_controller.dart';
import 'bbox_editor_enums.dart';
import 'bbox_frame_data.dart';

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

class _BBoxCameraSurfaceState extends State<BBoxCameraSurface> {
  final Object _cameraBindingOwner = Object();
  late final String _viewType;
  late final web.HTMLDivElement _hostElement;
  web.HTMLVideoElement? _videoElement;
  web.MediaStream? _stream;
  Uint8List? _capturedBytes;
  Size? _capturedSize;
  Object? _error;
  bool _initializing = true;
  bool _applyMirrorCorrection = false;
  int? _liveFrameCallbackId;

  bool get _isCaptureMode => widget.config.mode == BBoxCameraMode.captureStill;

  @override
  void initState() {
    super.initState();
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
    _viewType =
        'bbox-editor-camera-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    _hostElement = web.HTMLDivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'flex'
      ..style.alignItems = 'center'
      ..style.justifyContent = 'center'
      ..style.backgroundColor = 'black'
      ..style.overflow = 'hidden';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (_) => _hostElement,
    );
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

  Future<void> _reinitializeCamera() async {
    await _disposeCamera();
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
    try {
      final videoElement = web.HTMLVideoElement()
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', '')
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'contain'
        ..style.backgroundColor = 'black'
        ..style.transformOrigin = 'center'
        ..style.pointerEvents = 'none';

      final constraints = web.MediaStreamConstraints(
        audio: widget.config.enableAudio.toJS,
        video: _buildVideoConstraints(),
      );

      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;

      _applyMirrorCorrection = _shouldApplyMirrorCorrection(stream);
      _applyContainerMirrorCorrection(_hostElement);
      _hostElement.textContent = '';
      _hostElement.append(videoElement);

      videoElement.srcObject = stream;
      await videoElement.play().toDart;

      await _waitForVideoSize(videoElement);

      if (!mounted) {
        _stopStream(stream);
        return;
      }

      final sourceSize = Size(
        videoElement.videoWidth.toDouble(),
        videoElement.videoHeight.toDouble(),
      );

      setState(() {
        _videoElement = videoElement;
        _stream = stream;
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
      _startLiveFrameLoopIfNeeded();
      widget.onFrameReady(sourceSize);
      widget.onEditableFrameChanged(!_isCaptureMode);
    } catch (error) {
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

  JSAny _buildVideoConstraints() {
    final resolution = _resolutionFor(widget.config.resolutionPreset);
    final facingMode = _facingModeFor(widget.config.lensDirection);
    return <String, Object>{
      'width': <String, Object>{'ideal': resolution.width.toInt()},
      'height': <String, Object>{'ideal': resolution.height.toInt()},
      'aspectRatio': <String, Object>{
        'ideal': resolution.width / resolution.height,
      },
      if (facingMode != null)
        'facingMode': <String, Object>{'ideal': facingMode},
    }.jsify()!;
  }

  String? _facingModeFor(BBoxCameraLensDirection direction) {
    switch (direction) {
      case BBoxCameraLensDirection.front:
        return 'user';
      case BBoxCameraLensDirection.back:
        return 'environment';
      case BBoxCameraLensDirection.external:
        return null;
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
    final video = _videoElement;
    final hadCapturedFrame = _capturedBytes != null;

    setState(() {
      _capturedBytes = null;
      _capturedSize = null;
      _error = null;
    });

    if (hadCapturedFrame) {
      widget.onResumePreview();
    }

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
      resolution: video != null && video.videoWidth > 0 && video.videoHeight > 0
          ? Size(video.videoWidth.toDouble(), video.videoHeight.toDouble())
          : null,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || video == null) return;
      unawaited(_resumeWebPreview(video));
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

  bool _shouldApplyMirrorCorrection(web.MediaStream stream) {
    final tracks = stream.getVideoTracks().toDart;
    if (tracks.isEmpty) return false;

    final track = tracks.first;
    final settings = track.getSettings();
    final facingMode = _readTrackFacingMode(settings).toLowerCase();
    if (facingMode == 'environment') return false;
    if (facingMode == 'user') return true;

    final label = track.label.toLowerCase();
    if (_looksBackFacing(label)) return false;
    if (_looksFrontFacing(label)) return true;

    return widget.config.lensDirection != BBoxCameraLensDirection.back;
  }

  String _readTrackFacingMode(web.MediaTrackSettings settings) {
    try {
      return settings.facingMode;
    } catch (_) {
      return '';
    }
  }

  bool _looksBackFacing(String label) {
    return label.contains('back') ||
        label.contains('rear') ||
        label.contains('environment') ||
        label.contains('world');
  }

  bool _looksFrontFacing(String label) {
    return label.contains('front') ||
        label.contains('user') ||
        label.contains('face') ||
        label.contains('facetime') ||
        label.contains('macbook') ||
        label.contains('webcam') ||
        label.contains('built-in');
  }

  void _applyContainerMirrorCorrection(web.HTMLDivElement container) {
    if (_applyMirrorCorrection) {
      container.style.transform = 'scaleX(-1)';
      container.style.transformOrigin = 'center';
      return;
    }
    container.style.transform = 'none';
    container.style.transformOrigin = 'center';
  }

  Size _resolutionFor(BBoxCameraResolutionPreset preset) {
    switch (preset) {
      case BBoxCameraResolutionPreset.low:
        return const Size(320, 240);
      case BBoxCameraResolutionPreset.medium:
        return const Size(720, 480);
      case BBoxCameraResolutionPreset.high:
        return const Size(1280, 720);
      case BBoxCameraResolutionPreset.veryHigh:
        return const Size(1920, 1080);
      case BBoxCameraResolutionPreset.ultraHigh:
      case BBoxCameraResolutionPreset.max:
        return const Size(3840, 2160);
    }
  }

  Future<void> _waitForVideoSize(web.HTMLVideoElement element) async {
    if (element.videoWidth > 0 && element.videoHeight > 0) return;
    final completer = Completer<void>();
    late web.EventListener listener;
    listener = ((web.Event _) {
      if (element.videoWidth > 0 && element.videoHeight > 0) {
        element.removeEventListener('loadedmetadata', listener);
        completer.complete();
      }
    }).toJS;
    element.addEventListener('loadedmetadata', listener);
    await completer.future.timeout(const Duration(seconds: 5));
  }

  Future<void> _capturePhoto() async {
    final video = _videoElement;
    if (video == null) return;

    final width = video.videoWidth;
    final height = video.videoHeight;
    if (width <= 0 || height <= 0) return;

    final canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    final context = canvas.context2D;

    if (_applyMirrorCorrection) {
      context
        ..translate(width.toDouble(), 0)
        ..scale(-1, 1);
    }

    context.drawImageScaled(video, 0, 0, width.toDouble(), height.toDouble());

    final dataUrl = canvas.toDataURL('image/jpeg');
    final base64Part = dataUrl.contains(',')
        ? dataUrl.split(',').last
        : dataUrl;
    final bytes = base64Decode(base64Part);
    final size = Size(width.toDouble(), height.toDouble());

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
      sourceResolution: size,
      timestamp: DateTime.now(),
      mimeType: 'image/jpeg',
      sourceType: BBoxFrameSourceType.cameraCapture,
    );
    widget.controller.updateCapturedSourceFrame(frame);
    widget.onCapturedFrame?.call(frame);
    widget.onFrameReady(size);
    widget.onEditableFrameChanged(true);
  }

  void _capturePhotoFromController() {
    unawaited(_capturePhoto());
  }

  void _resumePreviewFromController() {
    final video = _videoElement;
    if (_capturedBytes == null || video == null) return;
    final resolution = Size(
      video.videoWidth.toDouble(),
      video.videoHeight.toDouble(),
    );

    setState(() {
      _capturedBytes = null;
      _capturedSize = null;
      _error = null;
    });
    widget.onEditableFrameChanged(false);
    widget.onResumePreview();
    widget.controller.updateCapturedSourceFrame(null);
    widget.controller.updateCameraState(
      isAttached: true,
      isPreviewActive: true,
      isCaptureFrozen: false,
      canCapture: _isCaptureMode,
      canResumePreview: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_resumeWebPreview(video));
      widget.onFrameReady(resolution);
    });
  }

  Future<BBoxFrameData?> _getCurrentFrameFromController() async {
    final video = _videoElement;
    if (video == null) return null;
    return _captureVideoFrame(
      video,
      sourceType: BBoxFrameSourceType.cameraLive,
    );
  }

  Future<BBoxFrameData?> _getCapturedFrameFromController() async {
    final bytes = _capturedBytes;
    final size = _capturedSize;
    if (bytes == null || size == null) return null;
    return BBoxFrameData(
      bytes: bytes,
      sourceResolution: size,
      timestamp: DateTime.now(),
      mimeType: 'image/jpeg',
      sourceType: BBoxFrameSourceType.cameraCapture,
    );
  }

  Future<BBoxFrameData?> _captureVideoFrame(
    web.HTMLVideoElement video, {
    required BBoxFrameSourceType sourceType,
  }) async {
    final width = video.videoWidth;
    final height = video.videoHeight;
    if (width <= 0 || height <= 0) return null;

    final canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    final context = canvas.context2D;
    if (_applyMirrorCorrection) {
      context
        ..translate(width.toDouble(), 0)
        ..scale(-1, 1);
    }
    context.drawImageScaled(video, 0, 0, width.toDouble(), height.toDouble());
    final dataUrl = canvas.toDataURL('image/jpeg');
    final base64Part = dataUrl.contains(',')
        ? dataUrl.split(',').last
        : dataUrl;
    final bytes = base64Decode(base64Part);
    return BBoxFrameData(
      bytes: bytes,
      sourceResolution: Size(width.toDouble(), height.toDouble()),
      timestamp: DateTime.now(),
      mimeType: 'image/jpeg',
      sourceType: sourceType,
    );
  }

  void _startLiveFrameLoopIfNeeded() {
    if (widget.onLiveFrame == null) return;
    if (widget.config.mode != BBoxCameraMode.livePreview) return;
    if (_liveFrameCallbackId != null) return;
    _scheduleNextLiveFrame();
  }

  void _scheduleNextLiveFrame() {
    _liveFrameCallbackId = web.window.requestAnimationFrame(
      ((num _) {
        _liveFrameCallbackId = null;
        unawaited(_emitLiveFrameAndReschedule());
      }).toJS,
    );
  }

  Future<void> _emitLiveFrameAndReschedule() async {
    if (!mounted || widget.onLiveFrame == null) return;
    if (widget.config.mode != BBoxCameraMode.livePreview) return;
    final video = _videoElement;
    if (video != null) {
      final frame = await _captureVideoFrame(
        video,
        sourceType: BBoxFrameSourceType.cameraLive,
      );
      if (frame != null && mounted) {
        widget.controller.updateCurrentSourceFrame(frame);
        widget.onLiveFrame?.call(frame);
      }
    }
    if (mounted) {
      _scheduleNextLiveFrame();
    }
  }

  Future<void> _resumeWebPreview(web.HTMLVideoElement video) async {
    try {
      await video.play().toDart;
    } catch (_) {
      // If the browser is already playing the stream, there is nothing to do.
    }
  }

  Future<void> _disposeCamera() async {
    if (_liveFrameCallbackId != null) {
      web.window.cancelAnimationFrame(_liveFrameCallbackId!);
      _liveFrameCallbackId = null;
    }
    _stopStream(_stream);
    _stream = null;
    _videoElement?.srcObject = null;
    _videoElement?.remove();
    _videoElement = null;
    _hostElement.textContent = '';
  }

  void _stopStream(web.MediaStream? stream) {
    if (stream == null) return;
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
  }

  Widget _buildCapturedSurface({
    required Uint8List bytes,
    required Size sourceSize,
  }) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: sourceSize.width == 0 ? 1 : sourceSize.width,
            height: sourceSize.height == 0 ? 1 : sourceSize.height,
            child: Image.memory(bytes, fit: BoxFit.fill),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.detachCamera(_cameraBindingOwner);
    widget.controller.detachSourceFrameAccess(_cameraBindingOwner);
    _disposeCamera();
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
        HtmlElementView(viewType: _viewType),
        if (_isCaptureMode && _capturedBytes != null)
          _buildCapturedSurface(
            bytes: _capturedBytes!,
            sourceSize: _capturedSize ?? const Size(4, 3),
          ),
      ],
    );
  }
}
