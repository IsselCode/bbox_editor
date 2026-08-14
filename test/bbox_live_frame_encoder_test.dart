import 'dart:typed_data';

import 'package:bbox_editor/src/bbox_live_frame_encoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('encodes an owned NV21 frame to a decodable JPEG', () async {
    final encoded = await encodeBBoxLiveFrame(
      BBoxRawLiveFrame(
        width: 2,
        height: 2,
        planes: <Uint8List>[
          Uint8List.fromList(<int>[128, 128, 128, 128, 128, 128, 128, 128]),
        ],
        rowStrides: const <int>[2],
        pixelStrides: const <int>[1],
        rotation: 0,
        mirror: false,
        quality: 85,
        acquisitionDuration: Duration.zero,
      ),
    );

    final decoded = img.decodeImage(encoded.bytes);
    expect(decoded, isNotNull);
    expect(encoded.width, 2);
    expect(encoded.height, 2);
    expect(decoded!.width, encoded.width);
    expect(decoded.height, encoded.height);
  });

  test('rotation reports the dimensions of the encoded pixels', () async {
    final encoded = await encodeBBoxLiveFrame(
      BBoxRawLiveFrame(
        width: 2,
        height: 4,
        planes: <Uint8List>[
          Uint8List.fromList(List<int>.filled(16, 128)),
          Uint8List.fromList(List<int>.filled(4, 128)),
          Uint8List.fromList(List<int>.filled(4, 128)),
        ],
        rowStrides: const <int>[2, 1, 1],
        pixelStrides: const <int>[1, 1, 1],
        rotation: 90,
        mirror: false,
        quality: 85,
        acquisitionDuration: Duration.zero,
      ),
    );

    expect(encoded.width, 4);
    expect(encoded.height, 2);
  });
}
