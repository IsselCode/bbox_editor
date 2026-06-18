import 'package:bbox_editor/mjpeg_stream/mjpeg_stream_screen.dart';
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
  onStreamReadyFutureBoundings;
  final void Function(BBoxEvent event)? onCommitBox;

  final VoidCallback? onStreamError;
  final VoidCallback? onStreamReady;
  final VoidCallback? onRetry;
  final ImageProvider? image;

  final ToolPolicy policy;
  final bool logs;

  BBoxEditor({
    super.key,
    this.stream,
    this.image,
    this.camera,
    this.sourceResolution,
    this.policy = ToolPolicy.platformDefault,
    this.controller,
    this.onRetry,
    this.onStreamError,
    this.onStreamReady,
    this.onStreamReadyFutureBoundings,
    this.onCommitBox,
    this.logs = true,
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
  final _tc = TransformationController();
  final Set<int> _touchPointers = <int>{};
  bool cameraStreamError = false;
  bool _cameraFrameReady = false;
  bool _loadingInitial = false;
  Size? _resolvedSourceResolution;
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
  bool get _sourceHasVisualError => cameraStreamError;
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
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      if (_usesImage) await loadBoxes();
    });
  }

  loadBoxes() async {
    if (widget.onStreamReadyFutureBoundings != null) {
      setState(() => _loadingInitial = true);
      try {
        final list = await widget.onStreamReadyFutureBoundings!(_ctrl.mapper);
        _ctrl.setInitialBoxes(list);
      } finally {
        if (mounted) setState(() => _loadingInitial = false);
      }
    }
  }

  Future<void> _handleSourceReady(Size resolution) async {
    _resolvedSourceResolution = resolution;
    _ctrl.sourceResolution = resolution;
    cameraStreamError = false;
    if (mounted) setState(() {});
    widget.onStreamReady?.call();
    await loadBoxes();
  }

  void _handleSourceError() {
    cameraStreamError = true;
    if (mounted) setState(() {});
    widget.onStreamError?.call();
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
  bool get allowZoom {
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
                  scaleEnabled: allowZoom,
                  panEnabled: allowZoom,
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
                        ),

                      // Aceptar cualquier tipo de imagen
                      if (_usesImage)
                        Image(image: widget.image!, fit: BoxFit.contain),

                      if (_usesCamera)
                        BBoxCameraSurface(
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
                            _ctrl.clearAll();
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
