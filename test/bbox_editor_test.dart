import 'dart:convert';

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
    ToolPolicy policy,
  ) {
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
            ),
          ),
        ),
      ),
    );
  }

  Widget buildHarness(BBoxEditorController controller) {
    return buildHarnessWithPolicy(controller, ToolPolicy.enforced);
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
