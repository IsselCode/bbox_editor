import 'dart:async';
export 'src/bbox_editor_controls_config.dart';
import 'package:bbox_editor/mjpeg_stream/mjpeg_stream_screen.dart';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'exports.dart';
import 'src/bbox_camera_surface.dart';

class BBoxEditor extends StatefulWidget {
  final String? stream;
  final Size? sourceResolution;
  final BBoxCameraConfig? camera;
  final BBoxEditorController? controller;
  final Future<List<BBoxEntity>> Function(FitCoverMapper mapper)?
  onSourceReadyFutureBoxes;
  final void Function(BBoxEvent event)? onCommitBox;
  final void Function(BBoxFrameData frame)? onLiveFrame;
  final void Function(BBoxFrameData frame)? onCapturedFrame;

  final VoidCallback? onSourceError;
  final VoidCallback? onSourceReady;
  final VoidCallback? onRetry;
  final ImageProvider? image;

  final ToolPolicy policy;
  final bool logs;
  final BBoxEditorControlsConfig controlsConfig;

  BBoxEditor({
    super.key,
    this.stream,
    this.image,
    this.camera,
    this.sourceResolution,
    this.policy = ToolPolicy.platformDefault,
    this.controller,
    this.onRetry,
    this.onSourceError,
    this.onSourceReady,
    this.onSourceReadyFutureBoxes,
    this.onCommitBox,
    this.onLiveFrame,
    this.onCapturedFrame,
    this.logs = true,
    this.controlsConfig = const BBoxEditorControlsConfig(),
  }) {
    final configuredSources = [
      image,
      stream,
      camera,
    ].whereType<Object>().length;
    assert(
      configuredSources == 1,
      "Debes configurar exactamente una fuente: image, stream o camera",
    );
    assert(
      camera != null || sourceResolution != null,
      "Ingresa sourceResolution cuando uses image o stream",
    );
  }

  @override
  State<BBoxEditor> createState() => _BBoxEditorState();
}

class _BBoxEditorState extends State<BBoxEditor> {
  final Object _sourceFrameOwner = Object();
  final _tc = TransformationController();
  final Set<int> _touchPointers = <int>{};
  bool _sourceError = false;
  bool _cameraFrameReady = false;
  bool _loadingInitial = false;
  Size? _resolvedSourceResolution;
  BBoxFrameData? _imageFrameData;
  double _currentZoomScale = 1;
  BBoxEditorController get _ctrl =>
      widget.controller ?? (throw ArgumentError('controller es requerido'));

  Size get _sourceResolution =>
      _resolvedSourceResolution ?? widget.sourceResolution ?? const Size(4, 3);

  double get _sourceAspectRatio {
    final resolution = _sourceResolution;
    if (resolution.height == 0) return 16 / 9;
    return resolution.width / resolution.height;
  }

  bool get _usesCamera => widget.camera != null;
  bool get _usesStream => widget.stream != null;
  bool get _usesImage => widget.image != null;
  bool get _sourceHasVisualError => _sourceError;
  bool get _sourceAllowsBBoxEdit {
    if (!_usesCamera) return true;
    if (_sourceHasVisualError) return false;
    return _cameraFrameReady;
  }

  @override
  void initState() {
    super.initState();
    _tc.addListener(_handleTransformChanged);
    if (widget.sourceResolution != null) {
      _resolvedSourceResolution = widget.sourceResolution;
      _ctrl.sourceResolution = widget.sourceResolution!;
    }
    _attachSourceFrameAccess();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      if (_usesImage) {
        if (widget.onLiveFrame != null) {
          await _prepareImageSourceFrame();
        }
        await _loadInitialBoxes();
      }
    });
  }

  @override
  void didUpdateWidget(covariant BBoxEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        oldWidget.image != widget.image ||
        oldWidget.stream != widget.stream ||
        oldWidget.camera != widget.camera;
    if (!sourceChanged) return;

    _sourceError = false;
    if (_usesCamera) {
      _cameraFrameReady = false;
    }
    if (widget.sourceResolution != null) {
      _resolvedSourceResolution = widget.sourceResolution;
      _ctrl.sourceResolution = widget.sourceResolution!;
    }
    _attachSourceFrameAccess();
    if (_usesImage) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (widget.onLiveFrame != null) {
          await _prepareImageSourceFrame();
        }
      });
    } else {
      _imageFrameData = null;
      _ctrl.updateCurrentSourceFrame(null);
      _ctrl.updateCapturedSourceFrame(null);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _attachSourceFrameAccess() {
    _ctrl.attachSourceFrameAccess(
      owner: _sourceFrameOwner,
      getCurrentFrame: _getCurrentSourceFrame,
      getCapturedFrame: _getCapturedSourceFrame,
    );
  }

  Future<void> _loadInitialBoxes() async {
    if (widget.onSourceReadyFutureBoxes != null) {
      setState(() => _loadingInitial = true);
      try {
        final list = await widget.onSourceReadyFutureBoxes!(_ctrl.mapper);
        _ctrl.setInitialBoxes(list);
      } finally {
        if (mounted) setState(() => _loadingInitial = false);
      }
    }
  }

  Future<void> _prepareImageSourceFrame() async {
    if (!_usesImage) return;
    final frame = await _frameDataFromImageProvider(
      widget.image!,
      _sourceResolution,
      BBoxFrameSourceType.image,
    );
    if (!mounted || frame == null) return;
    _imageFrameData = frame;
    _ctrl.updateCurrentSourceFrame(frame);
    widget.onLiveFrame?.call(frame);
  }

  Future<void> _handleSourceReady(Size resolution) async {
    _resolvedSourceResolution = resolution;
    _ctrl.sourceResolution = resolution;
    _sourceError = false;
    if (mounted) setState(() {});
    widget.onSourceReady?.call();
    await _loadInitialBoxes();
  }

  void _handleSourceError() {
    _sourceError = true;
    if (mounted) setState(() {});
    widget.onSourceError?.call();
  }

  Future<BBoxFrameData?> _getCurrentSourceFrame() async {
    if (_usesImage) {
      if (_imageFrameData != null) return _imageFrameData;
      await _prepareImageSourceFrame();
      return _imageFrameData;
    }
    return _ctrl.currentSourceFrame.value;
  }

  Future<BBoxFrameData?> _getCapturedSourceFrame() async {
    return _ctrl.capturedSourceFrame.value;
  }

  Future<BBoxFrameData?> _frameDataFromImageProvider(
    ImageProvider provider,
    Size sourceResolution,
    BBoxFrameSourceType sourceType,
  ) async {
    if (provider is MemoryImage) {
      return BBoxFrameData(
        bytes: provider.bytes,
        sourceResolution: sourceResolution,
        timestamp: DateTime.now(),
        mimeType: 'image/png',
        sourceType: sourceType,
      );
    }

    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<ImageInfo>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) => completer.complete(info),
      onError: (Object error, StackTrace? stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    stream.addListener(listener);
    try {
      final info = await completer.future;
      final byteData = await info.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        return _blankFrameData(sourceResolution, sourceType);
      }
      return BBoxFrameData(
        bytes: byteData.buffer.asUint8List(),
        sourceResolution: sourceResolution,
        timestamp: DateTime.now(),
        mimeType: 'image/png',
        sourceType: sourceType,
      );
    } catch (_) {
      return _blankFrameData(sourceResolution, sourceType);
    } finally {
      stream.removeListener(listener);
    }
  }

  Future<BBoxFrameData> _blankFrameData(
    Size sourceResolution,
    BBoxFrameSourceType sourceType,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final double width = sourceResolution.width <= 0
        ? 1
        : sourceResolution.width;
    final double height = sourceResolution.height <= 0
        ? 1
        : sourceResolution.height;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.black,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.ceil(), height.ceil());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return BBoxFrameData(
      bytes: byteData!.buffer.asUint8List(),
      sourceResolution: sourceResolution,
      timestamp: DateTime.now(),
      mimeType: 'image/png',
      sourceType: sourceType,
    );
  }

  bool get _isAutoTool => effectiveTool == BBoxTool.auto;
  bool get _isTouchZoomGesture => _touchPointers.length >= 2;

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    if (_touchPointers.add(event.pointer) && mounted) {
      setState(() {});
    }
  }

  void _handlePointerFinish(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    if (_touchPointers.remove(event.pointer) && mounted) {
      setState(() {});
    }
  }

  void _handleTransformChanged() {
    final nextScale = _tc.value.getMaxScaleOnAxis();
    if ((_currentZoomScale - nextScale).abs() < 0.001) return;
    if (mounted) {
      setState(() => _currentZoomScale = nextScale);
    } else {
      _currentZoomScale = nextScale;
    }
  }

  BBoxTool get effectiveTool {
    final selectedTool = widget.controller!.bBoxTool.value;
    switch (widget.policy) {
      case ToolPolicy.enforced:
        return selectedTool;
      case ToolPolicy.platformDefault:
        return selectedTool;
    }
  }

  // Flags ya resueltos para que el widget no repita lógica
  bool get allowScale {
    final p = widget.policy;
    if (effectiveTool == BBoxTool.auto) {
      if (isDesktopLike && p != ToolPolicy.enforced) return true;
      return true;
    }
    return effectiveTool == BBoxTool.zoom;
  }

  bool get allowPan {
    final p = widget.policy;
    if (effectiveTool == BBoxTool.auto) {
      if (isDesktopLike && p != ToolPolicy.enforced) return true;
      return _isTouchZoomGesture;
    }
    return effectiveTool == BBoxTool.zoom;
  }

  bool get allowBBoxEdit {
    final p = widget.policy;
    if (effectiveTool == BBoxTool.auto) {
      if (isDesktopLike && p != ToolPolicy.enforced) return true;
      return !_isTouchZoomGesture;
    }
    return effectiveTool == BBoxTool.bboxs;
  }

  @override
  void dispose() {
    _ctrl.detachSourceFrameAccess(_sourceFrameOwner);
    _tc.removeListener(_handleTransformChanged);
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _sourceAspectRatio,
      child: LayoutBuilder(
        builder: (context, c) {
          final viewSize = Size(c.maxWidth, c.maxHeight);
          _ctrl.viewSize = viewSize;

          return ValueListenableBuilder<BBoxTool>(
            valueListenable: widget.controller!.bBoxTool,
            builder: (context, value, child) {
              return Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _isAutoTool ? _handlePointerDown : null,
                onPointerUp: _isAutoTool ? _handlePointerFinish : null,
                onPointerCancel: _isAutoTool ? _handlePointerFinish : null,
                child: InteractiveViewer(
                  maxScale: 4,
                  minScale: 1,
                  scaleEnabled: allowScale,
                  panEnabled: allowPan,
                  transformationController: _tc,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // VIDEO
                      if (_usesStream)
                        MJPEGStreamScreen(
                          streamUrl: widget.stream!,
                          borderRadius: 0,
                          watermarkText: "Issel Code",
                          width: viewSize.width,
                          height: viewSize.height,
                          showLiveIcon: false,
                          showLogs: false,
                          blurSensitiveContent: false,
                          showWatermark: true,
                          onRetry: () => widget.onRetry?.call(),
                          onError: () {
                            _handleSourceError();
                          },
                          onStartCamera: () async {
                            await _handleSourceReady(_sourceResolution);
                          },
                          onFrame: (bytes) {
                            final frame = BBoxFrameData(
                              bytes: bytes,
                              sourceResolution: _sourceResolution,
                              timestamp: DateTime.now(),
                              mimeType: 'image/jpeg',
                              sourceType: BBoxFrameSourceType.stream,
                            );
                            _ctrl.updateCurrentSourceFrame(frame);
                            widget.onLiveFrame?.call(frame);
                          },
                        ),

                      // Aceptar cualquier tipo de imagen
                      if (_usesImage)
                        Image(image: widget.image!, fit: BoxFit.contain),

                      if (_usesCamera)
                        BBoxCameraSurface(
                          key: ValueKey(widget.camera),
                          controller: _ctrl,
                          config: widget.camera!,
                          onFrameReady: (resolution) async {
                            await _handleSourceReady(resolution);
                          },
                          onEditableFrameChanged: (editable) {
                            if (_cameraFrameReady == editable) return;
                            setState(() => _cameraFrameReady = editable);
                          },
                          onError: (_) => _handleSourceError(),
                          onResumePreview: () {
                            _ctrl.updateCapturedSourceFrame(null);
                            _ctrl.clearAll();
                          },
                          onLiveFrame: (frame) {
                            _ctrl.updateCurrentSourceFrame(frame);
                            widget.onLiveFrame?.call(frame);
                          },
                          onCapturedFrame: (frame) {
                            _ctrl.updateCapturedSourceFrame(frame);
                            widget.onCapturedFrame?.call(frame);
                          },
                        ),

                      // OVERLAY
                      if (!_sourceHasVisualError)
                        IgnorePointer(
                          ignoring: !(allowBBoxEdit && _sourceAllowsBBoxEdit),
                          child: ValueListenableBuilder<List<BBoxEntity>>(
                            valueListenable: _ctrl.boxes,
                            builder: (context, boxes, _) {
                              if (_loadingInitial) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              return BBoxOverlay(
                                viewSize: viewSize,
                                sourceResolution: _sourceResolution,
                                zoomScale: _currentZoomScale,
                                controlsConfig: widget.controlsConfig,
                                isInteractive:
                                    allowBBoxEdit && _sourceAllowsBBoxEdit,
                                // Usa el mismo controller que ya tienes para editar en memoria
                                controller: _ctrl,
                                initialBoxes: boxes,
                                onCommitBox: (event) {
                                  if (widget.logs) print(event.toString());
                                  widget.onCommitBox?.call(event);
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
