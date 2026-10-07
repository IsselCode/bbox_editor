import 'dart:async';
import 'dart:math';

import 'package:bbox_editor/exports.dart';
import 'package:bbox_editor/src/bbox_camera_surface_native.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const orientationChannel = MethodChannel('bbox_editor/camera_orientation');
  late CameraPlatform originalPlatform;
  late _FocusCameraPlatform platform;
  late BBoxEditorController controller;
  late List<Object> errors;

  setUp(() {
    originalPlatform = CameraPlatform.instance;
    platform = _FocusCameraPlatform();
    CameraPlatform.instance = platform;
    controller = BBoxEditorController();
    errors = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(orientationChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(orientationChannel, null);
    CameraPlatform.instance = originalPlatform;
    controller.dispose();
  });

  Widget harness({
    BBoxCameraMode mode = BBoxCameraMode.livePreview,
    ValueChanged<BBoxFrameData>? onCapturedFrame,
  }) {
    return MaterialApp(
      home: BBoxCameraSurface(
        controller: controller,
        config: BBoxCameraConfig(mode: mode),
        onFrameReady: (_) {},
        onEditableFrameChanged: (_) {},
        onError: errors.add,
        onResumePreview: () {},
        onCapturedFrame: onCapturedFrame,
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

  cameraTest('autofocus starts after streaming and releases continuous AF', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(platform.calls, ['stream:1', 'auto:1', 'center:1', 'reset:1']);
    expect(controller.cameraPreviewActive, isTrue);
    expect(errors, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  cameraTest('a pending autofocus does not delay preview or cancel itself', (
    tester,
  ) async {
    platform.focusCompletion = Completer<void>();
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(controller.cameraPreviewActive, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final first = controller.refocusCamera();
    final second = controller.refocusCamera();
    expect(platform.calls.where((call) => call == 'center:1'), hasLength(1));
    expect(platform.calls, isNot(contains('reset:1')));

    platform.focusCompletion!.complete();
    await tester.pumpAndSettle();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(platform.calls.where((call) => call == 'reset:1'), hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  cameraTest('fixed-focus cameras keep a usable preview', (tester) async {
    platform.focusPointSupported = false;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(await controller.refocusCamera(), isFalse);
    expect(platform.calls, isNot(contains('center:1')));
    expect(controller.cameraPreviewActive, isTrue);
    expect(errors, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  cameraTest('failed focus resets AF without making the camera unavailable', (
    tester,
  ) async {
    platform.failFocus = true;
    await tester.pumpWidget(harness(mode: BBoxCameraMode.captureStill));
    await tester.pumpAndSettle();

    expect(await controller.refocusCamera(), isFalse);
    expect(platform.calls, contains('reset:1'));
    expect(controller.cameraPreviewActive, isTrue);
    expect(controller.cameraCanCapture, isTrue);
    expect(errors, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  cameraTest('capture invalidates pending focus and resume requests new AF', (
    tester,
  ) async {
    platform.focusCompletion = Completer<void>();
    late Completer<BBoxFrameData> captured;
    await tester.pumpWidget(
      harness(
        mode: BBoxCameraMode.captureStill,
        onCapturedFrame: (frame) => captured.complete(frame),
      ),
    );
    await tester.pumpAndSettle();
    final pendingFocus = controller.refocusCamera();

    await tester.runAsync(() async {
      captured = Completer<BBoxFrameData>();
      controller.captureCameraImage();
      // Image-size decoding completes outside the widget-test fake clock.
      await captured.future.timeout(const Duration(seconds: 5));
    });
    await tester.pumpAndSettle();
    expect(controller.cameraCaptureFrozen, isTrue);
    expect(await controller.refocusCamera(), isFalse);

    platform.focusCompletion!.complete();
    await tester.pumpAndSettle();
    expect(await pendingFocus, isFalse);
    expect(platform.calls, isNot(contains('reset:1')));

    platform.focusCompletion = null;
    controller.resumeCameraPreview();
    await tester.pumpAndSettle();
    expect(platform.calls.where((call) => call == 'center:1'), hasLength(2));
    expect(platform.calls.last, 'reset:1');
    expect(controller.cameraPreviewActive, isTrue);
    expect(errors, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  cameraTest('focus completion after disposal does not call the old camera', (
    tester,
  ) async {
    platform.focusCompletion = Completer<void>();
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    final pendingFocus = controller.refocusCamera();

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    platform.focusCompletion!.complete();
    await tester.pumpAndSettle();

    expect(await pendingFocus, isFalse);
    expect(platform.calls, isNot(contains('reset:1')));
    expect(await controller.refocusCamera(), isFalse);
    expect(errors, isEmpty);
  });

  test(
    'refocus is unavailable when the camera binding has no focus handler',
    () async {
      controller.attachCamera(
        owner: Object(),
        capture: () {},
        resumePreview: () {},
      );
      controller.updateCameraState(
        isAttached: true,
        isPreviewActive: true,
        isCaptureFrozen: false,
        canCapture: true,
        canResumePreview: false,
      );
      expect(await controller.refocusCamera(), isFalse);
    },
  );
}

class _FocusCameraPlatform extends CameraPlatform {
  final calls = <String>[];
  final _errors = <int, StreamController<CameraErrorEvent>>{};
  bool focusPointSupported = true;
  bool failFocus = false;
  Completer<void>? focusCompletion;
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
          focusPointSupported,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      _errors[cameraId]!.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    calls.add('stream:$cameraId');
    return const Stream.empty();
  }

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.black);

  @override
  Future<void> setFocusMode(int cameraId, FocusMode mode) async {
    calls.add('${mode.name}:$cameraId');
  }

  @override
  Future<void> setFocusPoint(int cameraId, Point<double>? point) async {
    if (point == null) {
      calls.add('reset:$cameraId');
      return;
    }
    expect(point, const Point<double>(0.5, 0.5));
    calls.add('center:$cameraId');
    if (failFocus) throw CameraException('FocusUnsupported', 'Test driver');
    await focusCompletion?.future;
  }

  @override
  Future<XFile> takePicture(int cameraId) async => XFile.fromData(
    img.encodeJpg(img.Image(width: 4, height: 4)),
    mimeType: 'image/jpeg',
    name: 'capture.jpg',
  );

  @override
  Future<void> dispose(int cameraId) async {
    calls.add('dispose:$cameraId');
    final errors = _errors.remove(cameraId)!;
    errors.add(CameraErrorEvent(cameraId, 'Disposed'));
    await errors.close();
  }
}
