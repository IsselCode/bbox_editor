import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'bbox_editor_enums.dart';

@immutable
class BBoxCameraConfig {
  const BBoxCameraConfig({
    this.mode = BBoxCameraMode.livePreview,
    this.lensDirection = BBoxCameraLensDirection.back,
    this.resolutionPreset = BBoxCameraResolutionPreset.high,
    this.enableAudio = false,
    this.liveFrameTargetResolution,
    this.liveFrameJpegQuality = 85,
  });

  final BBoxCameraMode mode;
  final BBoxCameraLensDirection lensDirection;
  final BBoxCameraResolutionPreset resolutionPreset;
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
        other.enableAudio == enableAudio &&
        other.liveFrameTargetResolution == liveFrameTargetResolution &&
        other.liveFrameJpegQuality == liveFrameJpegQuality;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    lensDirection,
    resolutionPreset,
    enableAudio,
    liveFrameTargetResolution,
    liveFrameJpegQuality,
  );
}
