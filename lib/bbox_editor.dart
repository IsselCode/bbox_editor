import 'dart:typed_data';
import 'package:bbox_editor/mjpeg_stream/mjpeg_stream_screen.dart';
import 'package:flutter/material.dart';
import 'exports.dart';

class BBoxEditor extends StatefulWidget {
  final String? stream;
  final Size camResolution;
  final BBoxEditorController? controller;
  final Future<List<BBoxEntity>> Function(FitCoverMapper mapper)? onStreamReadyFutureBoundings;
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
    required this.camResolution,
    this.policy = ToolPolicy.platformDefault,
    this.controller,
    this.onRetry,
    this.onStreamError,
    this.onStreamReady,
    this.onStreamReadyFutureBoundings,
    this.onCommitBox,
    this.logs = true
  }) {
    assert(!(image == null && stream == null), "Solo puedes añadir una imagen o tu stream");
    assert(image != null || stream != null, "Ingresa una imagen o endpoint de stream");
  }

  @override
  State<BBoxEditor> createState() => _BBoxEditorState();
}

class _BBoxEditorState extends State<BBoxEditor> {
  final _tc = TransformationController();
  bool cameraStreamError = false;
  bool _loadingInitial = false;
  BBoxEditorController get _ctrl => widget.controller ?? (throw ArgumentError('controller es requerido'));

  @override
  void initState() {
    super.initState();
    _ctrl.cameraResolution = widget.camResolution;
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      if (widget.image != null) await loadBoxes();
    },);
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

  BBoxTool get effectiveTool {
    final p = widget.policy;
    switch (p) {
      case ToolPolicy.enforced:
        return widget.controller!.bBoxTool.value;
      case ToolPolicy.platformDefault:
        return isMobileLike ? widget.controller!.bBoxTool.value : BBoxTool.bboxs;
    }
  }

  // Flags ya resueltos para que el widget no repita lógica
  bool get allowZoom {
    final p = widget.policy;
    if (isDesktopLike && p != ToolPolicy.enforced) return true;
    return effectiveTool == BBoxTool.zoom;
  }

  bool get allowBBoxEdit {
    final p = widget.policy;
    if (isDesktopLike && p != ToolPolicy.enforced) return true;
    return effectiveTool == BBoxTool.bboxs;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(
        builder: (context, c) {
          final viewSize = Size(c.maxWidth, c.maxHeight);
          _ctrl.viewSize = viewSize;

          return ValueListenableBuilder<BBoxTool>(
            valueListenable: widget.controller!.bBoxTool,
            builder: (context, value, child) {

              return InteractiveViewer(
                maxScale: 4,
                minScale: 1,
                scaleEnabled: allowZoom,
                panEnabled: allowZoom,
                transformationController: _tc,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // VIDEO
                    if (widget.image == null && widget.stream != null)
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
                        cameraStreamError = true;
                        setState(() {});
                        widget.onStreamError?.call();
                      },
                      onStartCamera: () async {
                        cameraStreamError = false;
                        setState(() {});
                        widget.onStreamReady?.call();
                        // Disparamos la carga de boundings si el padre nos dio el callback
                        await loadBoxes();
                      },
                    ),

                    // Aceptar cualquier tipo de imagen
                    if (widget.image != null && widget.stream == null)
                    Image(image: widget.image!, fit: BoxFit.contain,),

                    // OVERLAY
                    if (!cameraStreamError && allowBBoxEdit)
                      ValueListenableBuilder<List<BBoxEntity>>(
                        valueListenable: _ctrl.boxes,
                        builder: (context, boxes, _) {
                          if (_loadingInitial) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          return BBoxOverlay(
                            viewSize: viewSize,
                            camResolution: widget.camResolution,
                            // Usa el mismo controller que ya tienes para editar en memoria
                            controller: widget.controller!,
                            initialBoxes: boxes,
                            onCommitBox: (event) {
                              if (widget.logs) print(event.toString());
                              widget.onCommitBox?.call(event);
                            },
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

