import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'bbox_editor_enums.dart';

@immutable
class BBoxCameraConfig {
  const BBoxCameraConfig({
    this.mode = BBoxCameraMode.livePreview,
    this.lensDirection = BBoxCameraLensDirection.back,
    this.resolution = BBoxCaptureResolution.hd,
    @Deprecated('Use resolution instead')
    BBoxCameraResolutionPreset? resolutionPreset,
    this.enableAudio = false,
    @Deprecated('Use resolution instead') Size? liveFrameTargetResolution,
    this.liveFrameJpegQuality = 85,
  }) : resolutionPresetOverride = resolutionPreset,
       liveFrameTargetResolutionOverride = liveFrameTargetResolution;

  final BBoxCameraMode mode;
  final BBoxCameraLensDirection lensDirection;
  final BBoxCaptureResolution resolution;
  final BBoxCameraResolutionPreset? resolutionPresetOverride;
  final bool enableAudio;
  final Size? liveFrameTargetResolutionOverride;
  final int liveFrameJpegQuality;

  BBoxCameraResolutionPreset get resolutionPreset =>
      resolutionPresetOverride ?? resolution.cameraPreset;
  Size get liveFrameTargetResolution =>
      liveFrameTargetResolutionOverride ?? resolution.targetSize;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BBoxCameraConfig &&
        other.mode == mode &&
        other.lensDirection == lensDirection &&
        other.resolution == resolution &&
        other.resolutionPresetOverride == resolutionPresetOverride &&
        other.enableAudio == enableAudio &&
        other.liveFrameTargetResolutionOverride ==
            liveFrameTargetResolutionOverride &&
        other.liveFrameJpegQuality == liveFrameJpegQuality;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    lensDirection,
    resolution,
    resolutionPresetOverride,
    enableAudio,
    liveFrameTargetResolutionOverride,
    liveFrameJpegQuality,
  );
}
