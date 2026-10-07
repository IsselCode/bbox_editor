import 'dart:async';

import 'package:bbox_editor/exports.dart';
import 'package:bbox_editor/src/bbox_camera_surface_native.dart';
import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const orientationChannel = MethodChannel('bbox_editor/camera_orientation');
  late CameraPlatform originalPlatform;
  late _OrientationCameraPlatform platform;
  late BBoxEditorController controller;
  late List<Size> frameSizes;
  late List<Object> errors;
  late String? initialOrientation;
  late int orientationReads;
  Completer<String?>? pendingOrientation;

  setUp(() {
    originalPlatform = CameraPlatform.instance;
    platform = _OrientationCameraPlatform();
    CameraPlatform.instance = platform;
    controller = BBoxEditorController();
    frameSizes = [];
    errors = [];
    initialOrientation = DeviceOrientation.landscapeLeft.name;
    orientationReads = 0;
    pendingOrientation = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(orientationChannel, (call) async {
          expect(call.method, 'getOrientation');
          orientationReads++;
          return pendingOrientation == null
              ? initialOrientation
              : await pendingOrientation!.future;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(orientationChannel, null);
    CameraPlatform.instance = originalPlatform;
    controller.dispose();
    await platform.orientations.close();
  });

  Widget harness({BBoxCameraMode mode = BBoxCameraMode.livePreview}) {
    return MaterialApp(
      home: BBoxCameraSurface(
        controller: controller,
        config: BBoxCameraConfig(mode: mode),
        onFrameReady: frameSizes.add,
        onEditableFrameChanged: (_) {},
        onError: errors.add,
        onResumePreview: () {},
      ),
    );
  }

  void cameraTest(String description, WidgetTesterCallback callback) {
    testWidgets(description, (tester) async {
      try {
        await callback(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  void expectPreviewOrientation(
    WidgetTester tester,
    DeviceOrientation orientation,
  ) {
    final preview = tester.widget<CameraPreview>(find.byType(CameraPreview));
    expect(preview.controller.value.deviceOrientation, orientation);
    final landscape =
        orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    expect(
      tester.getSize(find.byType(CameraPreview)).aspectRatio,
      closeTo(landscape ? 16 / 9 : 9 / 16, 0.0001),
    );
    expect(
      frameSizes.last,
      landscape ? const Size(1280, 720) : const Size(720, 1280),
    );
    expect(controller.cameraPreviewActive, isTrue);
    expect(errors, isEmpty);
  }

  for (final mode in BBoxCameraMode.values) {
    for (final orientation in DeviceOrientation.values) {
      cameraTest(
        '${mode.name} starts in ${orientation.name} without a sensor event',
        (tester) async {
          initialOrientation = orientation.name;
          await tester.pumpWidget(harness(mode: mode));
          await tester.pumpAndSettle();

          expect(orientationReads, 1);
          expectPreviewOrientation(tester, orientation);
        },
      );
    }
  }

  cameraTest('orientation changes resize the preview and update frame bounds', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expectPreviewOrientation(tester, DeviceOrientation.landscapeLeft);

    for (final orientation in [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitDown,
    ]) {
      platform.orientations.add(DeviceOrientationChangedEvent(orientation));
      await tester.pumpAndSettle();
      expectPreviewOrientation(tester, orientation);
    }
    expect(orientationReads, 1);
    expect(frameSizes, [
      const Size(1280, 720),
      const Size(720, 1280),
      const Size(1280, 720),
      const Size(720, 1280),
    ]);
  });

  cameraTest('reopening a stationary camera reads orientation again', (
    tester,
  ) async {
    initialOrientation = DeviceOrientation.landscapeRight.name;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expectPreviewOrientation(tester, DeviceOrientation.landscapeRight);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(orientationReads, 2);
    expectPreviewOrientation(tester, DeviceOrientation.landscapeRight);
  });

  cameraTest('a newer sensor orientation wins over the startup read', (
    tester,
  ) async {
    pendingOrientation = Completer<String?>();
    await tester.pumpWidget(harness());
    await tester.pump();
    expect(orientationReads, 1);

    platform.orientations.add(
      const DeviceOrientationChangedEvent(DeviceOrientation.landscapeRight),
    );
    await tester.pump();
    pendingOrientation!.complete(DeviceOrientation.portraitUp.name);
    await tester.pumpAndSettle();

    expectPreviewOrientation(tester, DeviceOrientation.landscapeRight);
  });

  cameraTest(
    'a late orientation read after disposal does not reopen the camera',
    (tester) async {
      pendingOrientation = Completer<String?>();
      await tester.pumpWidget(harness());
      await tester.pump();
      expect(orientationReads, 1);

      await tester.pumpWidget(const SizedBox());
      pendingOrientation!.complete(DeviceOrientation.landscapeRight.name);
      await tester.pumpAndSettle();

      expect(frameSizes, isEmpty);
      expect(controller.cameraAttached, isFalse);
      expect(platform.disposedCameras, [1]);
      expect(errors, isEmpty);
    },
  );

  cameraTest(
    'an unavailable native channel keeps orientation updates working',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(orientationChannel, (_) async {
            throw MissingPluginException();
          });
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expectPreviewOrientation(tester, DeviceOrientation.portraitUp);

      platform.orientations.add(
        const DeviceOrientationChangedEvent(DeviceOrientation.landscapeLeft),
      );
      await tester.pumpAndSettle();
      expectPreviewOrientation(tester, DeviceOrientation.landscapeLeft);
    },
  );

  cameraTest('a capture lock uses the same proportions as CameraPreview', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    final preview = tester.widget<CameraPreview>(find.byType(CameraPreview));

    await preview.controller.lockCaptureOrientation(
      DeviceOrientation.portraitUp,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(CameraPreview)).aspectRatio,
      closeTo(9 / 16, 0.0001),
    );
    expect(frameSizes.last, const Size(720, 1280));

    await preview.controller.unlockCaptureOrientation();
    await tester.pumpAndSettle();
    expectPreviewOrientation(tester, DeviceOrientation.landscapeLeft);
  });
}

class _OrientationCameraPlatform extends CameraPlatform {
  final orientations =
      StreamController<DeviceOrientationChangedEvent>.broadcast();
  final disposedCameras = <int>[];
  final _errors = <int, StreamController<CameraErrorEvent>>{};
  int _nextCameraId = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    final id = ++_nextCameraId;
    _errors[id] = StreamController<CameraErrorEvent>.broadcast();
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1280,
          720,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          false,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      _errors[cameraId]!.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      orientations.stream;

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) => const Stream.empty();

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.green);

  @override
  Future<void> setFocusMode(int cameraId, FocusMode mode) async {}

  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {}

  @override
  Future<void> unlockCaptureOrientation(int cameraId) async {}

  @override
  Future<void> dispose(int cameraId) async {
    disposedCameras.add(cameraId);
    final errors = _errors.remove(cameraId)!;
    errors.add(CameraErrorEvent(cameraId, 'Disposed'));
    await errors.close();
  }
}
