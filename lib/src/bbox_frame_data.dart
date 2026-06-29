import 'dart:typed_data';
import 'dart:ui';

enum BBoxFrameSourceType { image, stream, cameraLive, cameraCapture }

class BBoxFrameData {
  const BBoxFrameData({
    required this.bytes,
    required this.sourceResolution,
    required this.timestamp,
    required this.mimeType,
    required this.sourceType,
  });

  final Uint8List bytes;
  final Size sourceResolution;
  final DateTime timestamp;
  final String mimeType;
  final BBoxFrameSourceType sourceType;
}
