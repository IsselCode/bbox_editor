import 'dart:typed_data';
import 'dart:ui';

import 'bbox_entity.dart';
import 'bbox_frame_data.dart';

class BBoxCropData {
  const BBoxCropData({
    required this.box,
    required this.bytes,
    required this.sourceResolution,
    required this.cropSize,
    required this.sourceRect,
    required this.timestamp,
    required this.mimeType,
    required this.sourceType,
  });

  final BBoxEntity box;
  final Uint8List bytes;
  final Size sourceResolution;
  final Size cropSize;
  final Rect sourceRect;
  final DateTime timestamp;
  final String mimeType;
  final BBoxFrameSourceType sourceType;
}
