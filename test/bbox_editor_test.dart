import 'dart:convert';
import 'dart:math' as math;

import 'package:bbox_editor/bbox_editor.dart';
import 'package:bbox_editor/exports.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final image = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2e0AAAAASUVORK5CYII=',
    ),
  );

  Widget buildHarnessWithPolicy(
    BBoxEditorController controller,
    ToolPolicy policy, {
    BBoxEditorControlsConfig controlsConfig = const BBoxEditorControlsConfig(),
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            child: BBoxEditor(
              image: image,
              sourceResolution: const Size(1280, 720),
              controller: controller,
              logs: false,
              policy: policy,
              controlsConfig: controlsConfig,
            ),
          ),
        ),
      ),
    );
  }

  Widget buildHarness(BBoxEditorController controller) {
    return buildHarnessWithPolicy(controller, ToolPolicy.enforced);
  }

  Offset editorGlobalPoint(WidgetTester tester, Offset localPoint) {
    return tester.getTopLeft(find.byType(BBoxEditor)) + localPoint;
  }

  Offset deleteControlCenter(BBoxEntity box) {
    return box.handlePositions()[Handle.tr]!.translate(30, -30);
  }

  Offset rotateControlCenter(BBoxEntity box) {
    return box.rotateHandle(36);
  }

  Future<void> drawTouchBox(
    WidgetTester tester, {
    Offset startOffset = const Offset(-80, -40),
    Offset midOffset = const Offset(30, 20),
    Offset endOffset = const Offset(120, 90),
  }) async {
    final editor = find.byType(BBoxEditor);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    final start = tester.getCenter(editor) + startOffset;

    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(start + midOffset);
    await tester.pump();
    await gesture.moveTo(start + endOffset);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> dragFromTo(WidgetTester tester, Offset start, Offset end) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    final mid = Offset(
      start.dx + ((end.dx - start.dx) / 2),
      start.dy + ((end.dy - start.dy) / 2),
    );
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(mid);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> touchMoveAndRelease(
    WidgetTester tester,
    Offset start,
    Offset end,
  ) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('controller defaults to auto tool', (tester) async {
    final controller = BBoxEditorController();
    addTearDown(controller.dispose);

    expect(controller.bBoxTool.value, BBoxTool.auto);
  });

  testWidgets('auto mode creates a bbox with one touch drag', (tester) async {
    final controller = BBoxEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildHarness(controller));
    await tester.pumpAndSettle();

    await drawTouchBox(tester);

    expect(controller.boxes.value, hasLength(1));
    expect(controller.boxes.value.single.w, greaterThan(20));
    expect(controller.boxes.value.single.h, greaterThan(20));
  });

  testWidgets('creation can be disabled from controller', (tester) async {
    final controller = BBoxEditorController();
    controller.setCreationEnabled(false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildHarness(controller));
    await tester.pumpAndSettle();

    await drawTouchBox(tester);

    expect(controller.boxes.value, isEmpty);
  });

  testWidgets('small touch movement on empty canvas does not create a bbox', (
    tester,
  ) async {
    final controller = BBoxEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildHarness(controller));
    await tester.pumpAndSettle();

    final start = tester.getCenter(find.byType(BBoxEditor));
    await touchMoveAndRelease(tester, start, start + const Offset(6, 4));

    expect(controller.boxes.value, isEmpty);
  });

  testWidgets(
    'short deliberate drag below resize minimum does not create a bbox',
    (tester) async {
      final controller = BBoxEditorController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildHarness(controller));
      await tester.pumpAndSettle();

      final start = tester.getCenter(find.byType(BBoxEditor));
      await dragFromTo(tester, start, start + const Offset(14, 14));

      expect(controller.boxes.value, isEmpty);
    },
  );

  testWidgets(
    'valid create commits once it reaches the same minimum as resize',
    (tester) async {
      final controller = BBoxEditorController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildHarness(controller));
      await tester.pumpAndSettle();

      final start = tester.getCenter(find.byType(BBoxEditor));
      await dragFromTo(tester, start, start + const Offset(24, 24));

      expect(controller.boxes.value, hasLength(1));
      expect(controller.boxes.value.single.w, greaterThanOrEqualTo(20));
      expect(controller.boxes.value.single.h, greaterThanOrEqualTo(20));
    },
  );

  test('frame relative centers are local to crop size', () {
    final frame = BBoxFrameGeometry();
    frame.syncFromAbsoluteCenter(
      centerX: 640,
      centerY: 360,
      width: 200,
      height: 100,
      sourceResolution: const Size(1920, 1080),
    );

    expect(frame.absoluteX, 540);
    expect(frame.absoluteY, 310);
    expect(frame.absoluteCenterX, 640);
    expect(frame.absoluteCenterY, 360);
    expect(frame.relativeCenterX, 100);
    expect(frame.relativeCenterY, 50);
  });

  test(
    'fromServerJson maps backend frame coordinates into entity geometry',
    () {
      final mapper = FitCoverMapper(
        const Size(640, 360),
        const Size(1280, 720),
      );

      final box = BBoxEntity.fromServerJson({
        'id': 9,
        'cx': 640,
        'cy': 360,
        'w': 200,
        'h': 100,
        'tag': 'person',
        'angle_deg': 30,
        'color_hex': '#22C55E',
      }, mapper: mapper);

      expect(box.id, 9);
      expect(box.tag, 'person');
      expect(box.showTag, isTrue);
      expect(box.center.dx, closeTo(320, 0.001));
      expect(box.center.dy, closeTo(180, 0.001));
      expect(box.w, closeTo(100, 0.001));
      expect(box.h, closeTo(50, 0.001));
      expect(box.angle, closeTo(math.pi / 6, 0.0001));
      expect(box.centerF.dx, closeTo(640, 0.001));
      expect(box.centerF.dy, closeTo(360, 0.001));
    },
  );

  test(
    'fromServerCornersJson reconstructs rotated rectangle from clean corners',
    () {
      final mapper = FitCoverMapper(
        const Size(640, 360),
        const Size(1280, 720),
      );
      final frameBox = BBoxEntity(
        id: 41,
        center: const Offset(640, 360),
        w: 240,
        h: 120,
        angle: math.pi / 6,
      );
      final corners = frameBox.corners;

      final box = BBoxEntity.fromServerCornersJson({
        'id': 41,
        'tag': 'vehicle',
        'color_bgr': [0, 0, 255],
        'tl': {'x': corners[0].dx, 'y': corners[0].dy},
        'tr': {'x': corners[1].dx, 'y': corners[1].dy},
        'br': {'x': corners[2].dx, 'y': corners[2].dy},
        'bl': {'x': corners[3].dx, 'y': corners[3].dy},
      }, mapper: mapper);

      expect(box.id, 41);
      expect(box.tag, 'vehicle');
      expect(box.center.dx, closeTo(320, 0.001));
      expect(box.center.dy, closeTo(180, 0.001));
      expect(box.w, closeTo(120, 0.001));
      expect(box.h, closeTo(60, 0.001));
      expect(box.angle, closeTo(math.pi / 6, 0.0001));
      expect(box.centerF.dx, closeTo(640, 0.001));
      expect(box.centerF.dy, closeTo(360, 0.001));
      expect(box.wF, closeTo(240, 0.001));
      expect(box.hF, closeTo(120, 0.001));
      expect(box.angleDegScreen, closeTo(30, 0.001));
    },
  );

  test('rotated bbox geometry clamps center within canvas bounds', () {
    final box = BBoxEntity(
      center: const Offset(12, 14),
      w: 60,
      h: 40,
      angle: math.pi / 4,
    );

    final clamped = box.clampCenterWithin(const Size(120, 90));

    expect(clamped, isNotNull);
    expect(clamped!.fitsWithin(const Size(120, 90)), isTrue);
  });

  test('oversized rotated bbox reports that it cannot fit inside canvas', () {
    final box = BBoxEntity(
      center: const Offset(60, 45),
      w: 140,
      h: 100,
      angle: math.pi / 4,
    );

    expect(box.clampCenterWithin(const Size(120, 90)), isNull);
  });

  testWidgets('controller exposes current frame for image source', (
    tester,
  ) async {
    final controller = BBoxEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildHarness(controller));
    await tester.pumpAndSettle();
    await drawTouchBox(tester);

    final frame = await controller.getCurrentSourceFrame();

    expect(frame, isNotNull);
    expect(frame!.bytes, isNotEmpty);
  });

  testWidgets('overlay shows and hides bbox tag pills per entity', (
    tester,
  ) async {
    final controller = BBoxEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildHarness(controller));
    await tester.pumpAndSettle();

    final box = BBoxEntity(
      id: 77,
      center: const Offset(320, 180),
      w: 140,
      h: 80,
      tag: 'person',
      showTag: true,
    );

    await controller.addBox(box);
    await tester.pumpAndSettle();
    expect(find.text('person'), findsOneWidget);

    await controller.updateBox(box.id, box.copyWith(showTag: false));
    await tester.pumpAndSettle();
    expect(find.text('person'), findsNothing);
  });

  testWidgets('drawing beyond editor edges still commits bbox inside canvas', (
    tester,
  ) async {
    final controller = BBoxEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildHarness(controller));
    await tester.pumpAndSettle();

    await drawTouchBox(
      tester,
      startOffset: const Offset(-350, -180),
      midOffset: const Offset(250, 120),
      endOffset: const Offset(500, 400),
    );

    expect(controller.boxes.value, hasLength(1));
    expect(
      controller.boxes.value.single.fitsWithin(controller.viewSize),
      isTrue,
    );
  });

  testWidgets('selected bbox shows rotate and delete controls by default', (
    tester,
  ) async {
    final controller = BBoxEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildHarness(controller));
    await tester.pumpAndSettle();
    await drawTouchBox(tester);

    expect(find.byIcon(Icons.crop_rotate), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets(
    'controls config hides rotate and delete controls and disables their interactions',
    (tester) async {
      final controller = BBoxEditorController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildHarnessWithPolicy(
          controller,
          ToolPolicy.enforced,
          controlsConfig: const BBoxEditorControlsConfig(
            showRotateControl: false,
            showDeleteControl: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await drawTouchBox(tester);

      expect(find.byIcon(Icons.crop_rotate), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      final originalBox = controller.boxes.value.single;
      final originalAngle = originalBox.angle;
      controller.setCreationEnabled(false);

      await tester.tapAt(
        editorGlobalPoint(tester, deleteControlCenter(originalBox)),
      );
      await tester.pumpAndSettle();

      expect(controller.boxes.value, hasLength(1));

      final rotateGesture = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      final rotateStart = editorGlobalPoint(
        tester,
        rotateControlCenter(originalBox),
      );
      await rotateGesture.down(rotateStart);
      await tester.pump();
      await rotateGesture.moveTo(rotateStart + const Offset(24, 24));
      await tester.pump();
      await rotateGesture.up();
      await tester.pumpAndSettle();

      expect(controller.boxes.value, hasLength(1));
      expect(controller.boxes.value.single.angle, originalAngle);
    },
  );

  testWidgets('controller derived state tracks selection and box limit', (
    tester,
  ) async {
    final controller = BBoxEditorController();
    controller.setMaxBoxCount(1);
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildHarness(controller));
    await tester.pumpAndSettle();

    expect(controller.canCreateBoxesListenable.value, isTrue);
    expect(controller.selectedBox, isNull);

    await drawTouchBox(tester);

    expect(controller.boxes.value, hasLength(1));
    expect(controller.selectedBox?.id, controller.boxes.value.single.id);
    expect(controller.canCreateBoxesListenable.value, isFalse);

    await controller.removeBox(controller.boxes.value.single.id);

    expect(controller.selectedBox, isNull);
    expect(controller.canCreateBoxesListenable.value, isTrue);
  });

  testWidgets('controller camera state gates capture and resume actions', (
    tester,
  ) async {
    final controller = BBoxEditorController();
    addTearDown(controller.dispose);

    var captureCalls = 0;
    var resumeCalls = 0;
    var controllerNotifications = 0;
    final owner = Object();

    controller.addListener(() => controllerNotifications++);

    controller.attachCamera(
      owner: owner,
      capture: () => captureCalls++,
      resumePreview: () => resumeCalls++,
    );
    addTearDown(() => controller.detachCamera(owner));

    expect(controller.cameraAttached, isTrue);
    expect(controller.cameraCanCapture, isFalse);
    expect(controller.cameraCanResumePreview, isFalse);
    expect(controllerNotifications, 1);

    controller.captureCameraImage();
    controller.resumeCameraPreview();
    expect(captureCalls, 0);
    expect(resumeCalls, 0);

    controller.updateCameraState(
      isAttached: true,
      isPreviewActive: true,
      isCaptureFrozen: false,
      canCapture: true,
      canResumePreview: false,
    );
    controller.captureCameraImage();
    expect(captureCalls, 1);
    expect(controllerNotifications, 2);

    controller.updateCameraState(
      isAttached: true,
      isPreviewActive: false,
      isCaptureFrozen: true,
      canCapture: false,
      canResumePreview: true,
    );
    controller.resumeCameraPreview();
    expect(resumeCalls, 1);
    expect(controllerNotifications, 3);

    controller.updateCameraState(
      isAttached: true,
      isPreviewActive: false,
      isCaptureFrozen: true,
      canCapture: false,
      canResumePreview: true,
    );
    expect(controllerNotifications, 3);
  });

  testWidgets('select-before-edit mode creates bbox over an unselected box', (
    tester,
  ) async {
    final controller = BBoxEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildHarnessWithPolicy(
        controller,
        ToolPolicy.enforced,
        controlsConfig: const BBoxEditorControlsConfig(
          interactionMode: BBoxInteractionMode.selectBeforeEdit,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final original = BBoxEntity(
      id: 1,
      center: const Offset(320, 180),
      w: 160,
      h: 90,
      tag: 'base',
    );
    await controller.addBox(original);
    await controller.setSelectedBox(null);
    await tester.pumpAndSettle();

    await dragFromTo(
      tester,
      editorGlobalPoint(tester, original.center),
      editorGlobalPoint(tester, original.center + const Offset(90, 60)),
    );

    expect(controller.boxes.value, hasLength(2));
    final base = controller.boxes.value.firstWhere((box) => box.id == 1);
    expect(base.center, original.center);
    expect(base.w, original.w);
    expect(base.h, original.h);
  });

  testWidgets('select-before-edit mode drags only after selecting a box', (
    tester,
  ) async {
    final controller = BBoxEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildHarnessWithPolicy(
        controller,
        ToolPolicy.enforced,
        controlsConfig: const BBoxEditorControlsConfig(
          interactionMode: BBoxInteractionMode.selectBeforeEdit,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final original = BBoxEntity(
      id: 2,
      center: const Offset(320, 180),
      w: 160,
      h: 90,
      tag: 'movable',
    );
    await controller.addBox(original);
    await controller.setSelectedBox(null);
    await tester.pumpAndSettle();

    await tester.tapAt(editorGlobalPoint(tester, original.center));
    await tester.pumpAndSettle();
    expect(controller.selectedBox?.id, original.id);

    await dragFromTo(
      tester,
      editorGlobalPoint(tester, original.center),
      editorGlobalPoint(tester, original.center + const Offset(70, 20)),
    );

    expect(controller.boxes.value, hasLength(1));
    final moved = controller.boxes.value.single;
    expect(moved.id, original.id);
    expect(moved.center.dx, greaterThan(original.center.dx));
    expect(moved.center.dy, greaterThan(original.center.dy));
  });

  testWidgets('small touch movement over a box still behaves like tap select', (
    tester,
  ) async {
    final controller = BBoxEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildHarnessWithPolicy(
        controller,
        ToolPolicy.enforced,
        controlsConfig: const BBoxEditorControlsConfig(
          interactionMode: BBoxInteractionMode.selectBeforeEdit,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final original = BBoxEntity(
      id: 3,
      center: const Offset(320, 180),
      w: 160,
      h: 90,
      tag: 'tap-select',
    );
    await controller.addBox(original);
    await controller.setSelectedBox(null);
    await tester.pumpAndSettle();

    final start = editorGlobalPoint(tester, original.center);
    await touchMoveAndRelease(tester, start, start + const Offset(5, 3));

    expect(controller.boxes.value, hasLength(1));
    expect(controller.selectedBox?.id, original.id);
    expect(controller.boxes.value.single.center, original.center);
  });

  testWidgets('small touch movement on a selected box commits drag', (
    tester,
  ) async {
    final controller = BBoxEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildHarness(controller));
    await tester.pumpAndSettle();

    final original = BBoxEntity(
      id: 4,
      center: const Offset(320, 180),
      w: 160,
      h: 90,
      tag: 'small-drag',
    );
    await controller.addBox(original);
    await controller.setSelectedBox(original.id);
    await tester.pumpAndSettle();

    final start = editorGlobalPoint(tester, original.center);
    await touchMoveAndRelease(tester, start, start + const Offset(5, 3));

    expect(controller.boxes.value, hasLength(1));
    final moved = controller.boxes.value.single;
    expect(moved.center.dx, greaterThan(original.center.dx));
    expect(moved.center.dy, greaterThan(original.center.dy));
  });

  testWidgets('small touch movement on a resize handle commits resize', (
    tester,
  ) async {
    final controller = BBoxEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildHarness(controller));
    await tester.pumpAndSettle();

    final original = BBoxEntity(
      id: 5,
      center: const Offset(320, 180),
      w: 160,
      h: 90,
      tag: 'small-resize',
    );
    await controller.addBox(original);
    await controller.setSelectedBox(original.id);
    await tester.pumpAndSettle();

    final box = controller.boxes.value.single;
    final handle = box.handlePositions()[Handle.br]!;
    final start = editorGlobalPoint(tester, handle);
    await touchMoveAndRelease(tester, start, start + const Offset(5, 3));

    expect(controller.boxes.value, hasLength(1));
    final resized = controller.boxes.value.single;
    expect(resized.w, greaterThan(original.w));
    expect(resized.h, greaterThan(original.h));
  });

  testWidgets('controller max box count blocks creations beyond limit', (
    tester,
  ) async {
    final controller = BBoxEditorController();
    controller.setMaxBoxCount(1);
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildHarness(controller));
    await tester.pumpAndSettle();

    await drawTouchBox(tester);
    await drawTouchBox(
      tester,
      startOffset: const Offset(40, -20),
      midOffset: const Offset(20, 20),
      endOffset: const Offset(100, 100),
    );

    expect(controller.boxes.value, hasLength(1));
  });

  testWidgets(
    'auto mode does not commit a bbox during two-touch zoom gesture',
    (tester) async {
      final controller = BBoxEditorController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildHarness(controller));
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(BBoxEditor));
      final g1 = await tester.createGesture(
        pointer: 1,
        kind: PointerDeviceKind.touch,
      );
      final g2 = await tester.createGesture(
        pointer: 2,
        kind: PointerDeviceKind.touch,
      );

      await g1.down(center + const Offset(-50, 0));
      await tester.pump();
      await g2.down(center + const Offset(50, 0));
      await tester.pump();
      await g1.moveTo(center + const Offset(-90, 0));
      await g2.moveTo(center + const Offset(90, 0));
      await tester.pump();
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      expect(controller.boxes.value, isEmpty);
    },
  );

  testWidgets('mobile auto mode keeps scale enabled for pinch gestures', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final controller = BBoxEditorController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildHarnessWithPolicy(controller, ToolPolicy.platformDefault),
      );
      await tester.pumpAndSettle();

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final overlay = tester.widget<BBoxOverlay>(find.byType(BBoxOverlay));
      expect(viewer.scaleEnabled, isTrue);
      expect(viewer.panEnabled, isFalse);
      expect(overlay.isInteractive, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('desktop auto mode enables zoom and bbox editing together', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = BBoxEditorController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildHarnessWithPolicy(controller, ToolPolicy.platformDefault),
      );
      await tester.pumpAndSettle();

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final overlay = tester.widget<BBoxOverlay>(find.byType(BBoxOverlay));
      expect(viewer.scaleEnabled, isTrue);
      expect(viewer.panEnabled, isTrue);
      expect(overlay.isInteractive, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('desktop bbox mode only enables bbox editing', (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = BBoxEditorController();
      controller.setTool(BBoxTool.bboxs);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildHarnessWithPolicy(controller, ToolPolicy.platformDefault),
      );
      await tester.pumpAndSettle();

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final overlay = tester.widget<BBoxOverlay>(find.byType(BBoxOverlay));
      expect(viewer.scaleEnabled, isFalse);
      expect(viewer.panEnabled, isFalse);
      expect(overlay.isInteractive, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('desktop zoom mode only enables zoom interactions', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = BBoxEditorController();
      controller.setTool(BBoxTool.zoom);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildHarnessWithPolicy(controller, ToolPolicy.platformDefault),
      );
      await tester.pumpAndSettle();

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final overlay = tester.widget<BBoxOverlay>(find.byType(BBoxOverlay));
      expect(viewer.scaleEnabled, isTrue);
      expect(viewer.panEnabled, isTrue);
      expect(overlay.isInteractive, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}
