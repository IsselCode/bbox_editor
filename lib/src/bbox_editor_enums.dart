import 'dart:ui';

enum Mode { idle, draw, drag, rotate, resize }

enum Handle { none, tl, t, tr, r, br, b, bl, l }

enum BBoxTool { auto, zoom, bboxs }

enum ToolPolicy { platformDefault, enforced }

enum BBoxInteractionMode { directEdit, selectBeforeEdit }

enum CommitOrigin { controller, overlay }

enum BBoxCameraMode { captureStill, livePreview }

enum BBoxCameraLensDirection { front, back, external }

enum BBoxCameraResolutionPreset { low, medium, high, veryHigh, ultraHigh, max }

enum BBoxCaptureResolution {
  hd(Size(1280, 720), BBoxCameraResolutionPreset.medium),
  fullHd(Size(1920, 1080), BBoxCameraResolutionPreset.high);

  const BBoxCaptureResolution(this.targetSize, this.cameraPreset);

  final Size targetSize;
  final BBoxCameraResolutionPreset cameraPreset;
}
