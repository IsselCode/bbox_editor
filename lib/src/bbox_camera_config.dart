import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'bbox_editor_enums.dart';

@immutable
class BBoxCameraConfig {
  const BBoxCameraConfig({
    this.mode = BBoxCameraMode.livePreview,
    this.lensDirection = BBoxCameraLensDirection.back,
    this.resolutionPreset = BBoxCameraResolutionPreset.high,
    this.focusMode = BBoxCameraFocusMode.auto,
    this.focusPoint,
    this.enableAudio = false,
    this.liveFrameTargetResolution,
    this.liveFrameJpegQuality = 85,
  });

  final BBoxCameraMode mode;
  final BBoxCameraLensDirection lensDirection;
  final BBoxCameraResolutionPreset resolutionPreset;
  final BBoxCameraFocusMode focusMode;
  final Offset? focusPoint;
  final bool enableAudio;
  final Size? liveFrameTargetResolution;
  final int liveFrameJpegQuality;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BBoxCameraConfig &&
        other.mode == mode &&
        other.lensDirection == lensDirection &&
        other.resolutionPreset == resolutionPreset &&
        other.focusMode == focusMode &&
        other.focusPoint == focusPoint &&
        other.enableAudio == enableAudio &&
        other.liveFrameTargetResolution == liveFrameTargetResolution &&
        other.liveFrameJpegQuality == liveFrameJpegQuality;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    lensDirection,
    resolutionPreset,
    focusMode,
    focusPoint,
    enableAudio,
    liveFrameTargetResolution,
    liveFrameJpegQuality,
  );
}
