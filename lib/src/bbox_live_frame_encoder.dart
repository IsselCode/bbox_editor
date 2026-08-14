import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Owned copy of the planes received from [CameraImage].
///
/// This type is intentionally private to the camera adapter. A CameraImage must
/// never outlive the callback that delivered it.
class BBoxRawLiveFrame {
  const BBoxRawLiveFrame({
    required this.width,
    required this.height,
    required this.planes,
    required this.rowStrides,
    required this.pixelStrides,
    required this.rotation,
    required this.mirror,
    required this.quality,
    this.targetWidth,
    this.targetHeight,
  });

  final int width;
  final int height;
  final List<Uint8List> planes;
  final List<int> rowStrides;
  final List<int> pixelStrides;
  final int rotation;
  final bool mirror;
  final int quality;
  final int? targetWidth;
  final int? targetHeight;
}

class BBoxEncodedLiveFrame {
  const BBoxEncodedLiveFrame({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Encodes a copied camera frame without doing conversion on the UI isolate.
Future<BBoxEncodedLiveFrame> encodeBBoxLiveFrame(BBoxRawLiveFrame frame) {
  return Isolate.run(() => _encodeBBoxLiveFrame(frame));
}

BBoxEncodedLiveFrame _encodeBBoxLiveFrame(BBoxRawLiveFrame frame) {
  if (frame.width <= 0 || frame.height <= 0 || frame.planes.isEmpty) {
    throw StateError(
      'El frame de cámara no tiene dimensiones o planos válidos',
    );
  }

  final rgb = Uint8List(frame.width * frame.height * 3);
  final yPlane = frame.planes.first;
  final yStride = frame.rowStrides.first;
  final hasSeparateChroma = frame.planes.length >= 3;
  final chromaPlane = hasSeparateChroma ? frame.planes[1] : yPlane;
  final vPlane = hasSeparateChroma ? frame.planes[2] : yPlane;
  final chromaStride = hasSeparateChroma
      ? frame.rowStrides[1]
      : frame.rowStrides.first;
  final vStride = hasSeparateChroma ? frame.rowStrides[2] : chromaStride;
  final chromaPixelStride = hasSeparateChroma ? frame.pixelStrides[1] : 2;
  final vPixelStride = hasSeparateChroma ? frame.pixelStrides[2] : 2;

  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final yIndex = y * yStride + x;
      final uvX = x ~/ 2;
      final uvY = y ~/ 2;
      int u;
      int v;
      if (hasSeparateChroma) {
        final uIndex = uvY * chromaStride + uvX * chromaPixelStride;
        final vIndex = uvY * vStride + uvX * vPixelStride;
        u = _byteAt(chromaPlane, uIndex);
        v = _byteAt(vPlane, vIndex);
      } else {
        // NV21 stores V then U after the Y plane. Some Android devices expose
        // this as one plane with padding in rowStride; use that stride for the
        // chroma offset as well.
        final chromaOffset = yStride * frame.height;
        final uvIndex = chromaOffset + uvY * chromaStride + uvX * 2;
        v = _byteAt(yPlane, uvIndex);
        u = _byteAt(yPlane, uvIndex + 1);
      }
      final yy = _byteAt(yPlane, yIndex);
      final c = yy - 16;
      final d = u - 128;
      final e = v - 128;
      final r = _clamp8((298 * c + 409 * e + 128) >> 8);
      final g = _clamp8((298 * c - 100 * d - 208 * e + 128) >> 8);
      final b = _clamp8((298 * c + 516 * d + 128) >> 8);
      final outputX = frame.mirror ? frame.width - x - 1 : x;
      final outputIndex = (y * frame.width + outputX) * 3;
      rgb[outputIndex] = r;
      rgb[outputIndex + 1] = g;
      rgb[outputIndex + 2] = b;
    }
  }

  var image = img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: rgb.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final rotation = ((frame.rotation % 360) + 360) % 360;
  if (rotation != 0) {
    image = img.copyRotate(image, angle: rotation);
  }
  final targetWidth = frame.targetWidth;
  final targetHeight = frame.targetHeight;
  if (targetWidth != null &&
      targetHeight != null &&
      targetWidth > 0 &&
      targetHeight > 0 &&
      (targetWidth != image.width || targetHeight != image.height)) {
    final sourceAspect = image.width / image.height;
    final targetAspect = targetWidth / targetHeight;
    if ((sourceAspect - targetAspect).abs() > 0.01) {
      throw StateError(
        'La resolución objetivo no conserva la relación de aspecto del frame',
      );
    }
    image = img.copyResize(image, width: targetWidth, height: targetHeight);
  }
  final bytes = img.encodeJpg(image, quality: frame.quality.clamp(1, 100));
  return BBoxEncodedLiveFrame(
    bytes: Uint8List.fromList(bytes),
    width: image.width,
    height: image.height,
  );
}

int _byteAt(Uint8List bytes, int index) {
  if (index < 0 || index >= bytes.length) return 128;
  return bytes[index];
}

int _clamp8(int value) => value.clamp(0, 255);
