import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../exports.dart';

class BBoxEditorController extends ChangeNotifier {
  BBoxEditorController() {
    boxes.addListener(_syncCanCreateBoxes);
    creationEnabled.addListener(_syncCanCreateBoxes);
    maxBoxCount.addListener(_syncCanCreateBoxes);
    _syncCanCreateBoxes();
  }

  late Size _viewSize;
  Size get viewSize => _viewSize;
  set viewSize(Size v) => _viewSize = v;
  late Size sourceResolution;

  final ValueNotifier<BBoxTool> bBoxTool = ValueNotifier(BBoxTool.auto);
  void setTool(BBoxTool tool) => bBoxTool.value = tool;

  final ValueNotifier<bool> creationEnabled = ValueNotifier(true);
  final ValueNotifier<int?> maxBoxCount = ValueNotifier(null);
  final ValueNotifier<bool> canCreateBoxesListenable = ValueNotifier(true);

  void setCreationEnabled(bool enabled) => creationEnabled.value = enabled;

  void setMaxBoxCount(int? max) {
    if (max != null && max < 0) {
      throw ArgumentError.value(
        max,
        'max',
        'maxBoxCount no puede ser negativo',
      );
    }
    maxBoxCount.value = max;
  }

  bool get canCreateBoxes => canCreateBoxesListenable.value;

  FitCoverMapper get mapper {
    assert(
      _viewSize.width > 0 && _viewSize.height > 0,
      'viewSize debe estar asignado antes de usar mapper',
    );
    assert(
      sourceResolution.width > 0 && sourceResolution.height > 0,
      'sourceResolution debe estar asignado antes de usar mapper',
    );
    return FitCoverMapper(_viewSize, sourceResolution);
  }

  final ValueNotifier<List<BBoxEntity>> boxes = ValueNotifier(const []);
  final ValueNotifier<BBoxEntity?> selectedBoxListenable = ValueNotifier(null);
  BBoxEntity? get selectedBox => selectedBoxListenable.value;

  bool _cameraAttached = false;
  bool get cameraAttached => _cameraAttached;

  bool _cameraPreviewActive = false;
  bool get cameraPreviewActive => _cameraPreviewActive;

  bool _cameraCaptureFrozen = false;
  bool get cameraCaptureFrozen => _cameraCaptureFrozen;

  bool _cameraCanCapture = false;
  bool get cameraCanCapture => _cameraCanCapture;

  bool _cameraCanResumePreview = false;
  bool get cameraCanResumePreview => _cameraCanResumePreview;

  final ValueNotifier<BBoxFrameData?> currentSourceFrame = ValueNotifier(null);
  final ValueNotifier<BBoxFrameData?> capturedSourceFrame = ValueNotifier(null);

  final _events = StreamController<BBoxEvent>.broadcast();
  Stream<BBoxEvent> get events => _events.stream;

  VoidCallback? _ovClearAll;
  void Function(int id, CommitOrigin commitOrigin)? _ovRemove;
  void Function(BBoxEntity box, CommitOrigin commitOrigin)? _ovAdd;
  void Function(List<BBoxEntity> boxes)? _ovSetAll;
  void Function(int id, BBoxEntity box, CommitOrigin commitOrigin)? _ovUpdate;
  void Function(int? id, CommitOrigin commitOrigin)? _ovSelected;

  Object? _cameraOwner;
  VoidCallback? _cameraCapture;
  VoidCallback? _cameraResumePreview;

  Object? _sourceFrameOwner;
  Future<BBoxFrameData?> Function()? _getCurrentSourceFrame;
  Future<BBoxFrameData?> Function()? _getCapturedSourceFrame;

  void attachOverlay({
    required VoidCallback clearAll,
    required void Function(int id, CommitOrigin commitOrigin) remove,
    required void Function(BBoxEntity box, CommitOrigin commitOrigin) add,
    required void Function(List<BBoxEntity> boxes) setAll,
    required void Function(int id, BBoxEntity box, CommitOrigin commitOrigin)
    update,
    required void Function(int? id, CommitOrigin commitOrigin) selected,
  }) {
    _ovClearAll = clearAll;
    _ovRemove = remove;
    _ovAdd = add;
    _ovSetAll = setAll;
    _ovUpdate = update;
    _ovSelected = selected;
  }

  void detachOverlay() {
    _ovClearAll = null;
    _ovRemove = null;
    _ovAdd = null;
    _ovSetAll = null;
    _ovUpdate = null;
    _ovSelected = null;
  }

  void attachCamera({
    required Object owner,
    required VoidCallback capture,
    required VoidCallback resumePreview,
  }) {
    _cameraOwner = owner;
    _cameraCapture = capture;
    _cameraResumePreview = resumePreview;
    updateCameraState(
      isAttached: true,
      isPreviewActive: false,
      isCaptureFrozen: false,
      canCapture: false,
      canResumePreview: false,
    );
  }

  void detachCamera(Object owner) {
    if (!identical(_cameraOwner, owner)) return;
    _cameraOwner = null;
    _cameraCapture = null;
    _cameraResumePreview = null;
    updateCameraState(
      isAttached: false,
      isPreviewActive: false,
      isCaptureFrozen: false,
      canCapture: false,
      canResumePreview: false,
    );
  }

  void attachSourceFrameAccess({
    required Object owner,
    required Future<BBoxFrameData?> Function() getCurrentFrame,
    required Future<BBoxFrameData?> Function() getCapturedFrame,
  }) {
    _sourceFrameOwner = owner;
    _getCurrentSourceFrame = getCurrentFrame;
    _getCapturedSourceFrame = getCapturedFrame;
  }

  void detachSourceFrameAccess(Object owner) {
    if (!identical(_sourceFrameOwner, owner)) return;
    _sourceFrameOwner = null;
    _getCurrentSourceFrame = null;
    _getCapturedSourceFrame = null;
  }

  void updateCameraState({
    required bool isAttached,
    required bool isPreviewActive,
    required bool isCaptureFrozen,
    required bool canCapture,
    required bool canResumePreview,
  }) {
    var changed = false;
    if (_cameraAttached != isAttached) {
      _cameraAttached = isAttached;
      changed = true;
    }
    if (_cameraPreviewActive != isPreviewActive) {
      _cameraPreviewActive = isPreviewActive;
      changed = true;
    }
    if (_cameraCaptureFrozen != isCaptureFrozen) {
      _cameraCaptureFrozen = isCaptureFrozen;
      changed = true;
    }
    if (_cameraCanCapture != canCapture) {
      _cameraCanCapture = canCapture;
      changed = true;
    }
    if (_cameraCanResumePreview != canResumePreview) {
      _cameraCanResumePreview = canResumePreview;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void updateCurrentSourceFrame(BBoxFrameData? frame) {
    currentSourceFrame.value = frame;
  }

  void updateCapturedSourceFrame(BBoxFrameData? frame) {
    capturedSourceFrame.value = frame;
  }

  void setInitialBoxes(List<BBoxEntity> list) {
    final selectedId = selectedBox?.id;
    boxes.value = List.unmodifiable(list);
    _syncSelectedBoxById(selectedId);
    _ovSetAll?.call(list);
  }

  void clearAll() {
    boxes.value = const [];
    _setSelectedBox(null);
    _ovClearAll?.call();
    _events.add(const BoxesCleared(origin: CommitOrigin.controller));
  }

  void captureCameraImage() {
    if (!cameraCanCapture) return;
    _cameraCapture?.call();
  }

  void resumeCameraPreview() {
    if (!cameraCanResumePreview) return;
    _cameraResumePreview?.call();
  }

  Future<BBoxFrameData?> getCurrentSourceFrame() async {
    final fromProvider = await _getCurrentSourceFrame?.call();
    if (fromProvider != null) {
      currentSourceFrame.value = fromProvider;
      return fromProvider;
    }
    return currentSourceFrame.value;
  }

  Future<BBoxFrameData?> getCapturedSourceFrame() async {
    final fromProvider = await _getCapturedSourceFrame?.call();
    if (fromProvider != null) {
      capturedSourceFrame.value = fromProvider;
      return fromProvider;
    }
    return capturedSourceFrame.value;
  }

  Future<BBoxCropData?> getBoxCrop(BBoxEntity box) async {
    final frame = await _resolveCropFrame();
    if (frame == null) return null;
    return _cropBoxFromFrame(box, frame);
  }

  Future<BBoxCropData?> getBoxCropById(int id) async {
    final box = boxes.value.cast<BBoxEntity?>().firstWhere(
      (element) => element?.id == id,
      orElse: () => null,
    );
    if (box == null) return null;
    return getBoxCrop(box);
  }

  Future<List<BBoxCropData>> getAllBoxCrops() async {
    final frame = await _resolveCropFrame();
    if (frame == null) return const [];
    final crops = <BBoxCropData>[];
    for (final box in boxes.value) {
      final crop = await _cropBoxFromFrame(box, frame);
      if (crop != null) crops.add(crop);
    }
    return crops;
  }

  Future<void> addBox(
    BBoxEntity b, {
    CommitOrigin commitOrigin = CommitOrigin.controller,
  }) async {
    if (!canCreateBoxes) return;
    boxes.value = [...boxes.value, b];
    _setSelectedBox(b);
    _ovAdd?.call(b, commitOrigin);
    _events.add(BoxCreated(box: b, origin: commitOrigin));
  }

  Future<void> setSelectedBox(
    int? id, {
    CommitOrigin commitOrigin = CommitOrigin.controller,
  }) async {
    _syncSelectedBoxById(id);
    _ovSelected?.call(id, commitOrigin);
  }

  Future<void> selected(
    BBoxEntity b, {
    CommitOrigin commitOrigin = CommitOrigin.controller,
  }) async {
    if (!canCreateBoxes) return;
    boxes.value = [...boxes.value, b];
    _setSelectedBox(b);
    _ovAdd?.call(b, commitOrigin);
    _events.add(BoxCreated(box: b, origin: commitOrigin));
  }

  Future<void> removeBox(
    int id, {
    CommitOrigin commitOrigin = CommitOrigin.controller,
  }) async {
    boxes.value = boxes.value.where((e) => e.id != id).toList(growable: false);
    if (selectedBox?.id == id) {
      _setSelectedBox(null);
    }
    _ovRemove?.call(id, commitOrigin);
    _events.add(BoxDeleted(id: id, origin: commitOrigin));
  }

  Future<void> updateBox(
    int id,
    BBoxEntity b, {
    CommitOrigin commitOrigin = CommitOrigin.controller,
  }) async {
    final i = boxes.value.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final l = [...boxes.value]..[i] = b;
    boxes.value = l;
    if (selectedBox?.id == id) {
      _setSelectedBox(b);
    }
    _ovUpdate?.call(b.id, b, commitOrigin);
    _events.add(BoxUpdated(box: b, origin: commitOrigin));
  }

  Future<BBoxFrameData?> _resolveCropFrame() async {
    final captured = await getCapturedSourceFrame();
    if (captured != null) return captured;
    return getCurrentSourceFrame();
  }

  Future<BBoxCropData?> _cropBoxFromFrame(
    BBoxEntity box,
    BBoxFrameData frame,
  ) async {
    final codec = await ui.instantiateImageCodec(frame.bytes);
    final frameInfo = await codec.getNextFrame();
    final image = frameInfo.image;

    try {
      final scaleX = image.width / frame.sourceResolution.width;
      final scaleY = image.height / frame.sourceResolution.height;
      final pixelCorners = _pixelCornersForBox(box, frame, image);
      final cropGeometry = _tightCropGeometry(pixelCorners);
      if (cropGeometry == null) return null;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.translate(cropGeometry.width / 2, cropGeometry.height / 2);
      canvas.rotate(-cropGeometry.angle);
      canvas.translate(-cropGeometry.center.dx, -cropGeometry.center.dy);
      canvas.drawImage(image, Offset.zero, Paint());
      final picture = recorder.endRecording();
      final cropImage = await picture.toImage(
        cropGeometry.width.ceil(),
        cropGeometry.height.ceil(),
      );
      final byteData = await cropImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      cropImage.dispose();
      if (byteData == null) return null;

      final sourceRect = Rect.fromLTWH(
        cropGeometry.sourceRect.left / scaleX,
        cropGeometry.sourceRect.top / scaleY,
        cropGeometry.sourceRect.width / scaleX,
        cropGeometry.sourceRect.height / scaleY,
      );
      box.sourceCropRect = sourceRect;

      return BBoxCropData(
        box: box,
        bytes: byteData.buffer.asUint8List(),
        sourceResolution: frame.sourceResolution,
        cropSize: Size(cropGeometry.width, cropGeometry.height),
        sourceRect: sourceRect,
        timestamp: DateTime.now(),
        mimeType: 'image/png',
        sourceType: frame.sourceType,
      );
    } finally {
      image.dispose();
    }
  }

  List<Offset> _pixelCornersForBox(
    BBoxEntity box,
    BBoxFrameData frame,
    ui.Image image,
  ) {
    final scaleX = image.width / frame.sourceResolution.width;
    final scaleY = image.height / frame.sourceResolution.height;
    return box.corners
        .map(mapper.pViewToFrame)
        .map((point) => Offset(point.dx * scaleX, point.dy * scaleY))
        .toList(growable: false);
  }

  _CropGeometry? _tightCropGeometry(List<Offset> corners) {
    if (corners.length != 4) return null;
    final topLeft = corners[0];
    final topRight = corners[1];
    final bottomRight = corners[2];
    final bottomLeft = corners[3];
    final width = (topRight - topLeft).distance;
    final height = (bottomRight - topRight).distance;
    if (width <= 0 || height <= 0) return null;

    final angle = math.atan2(
      topRight.dy - topLeft.dy,
      topRight.dx - topLeft.dx,
    );
    final center = Offset(
      (topLeft.dx + topRight.dx + bottomRight.dx + bottomLeft.dx) / 4,
      (topLeft.dy + topRight.dy + bottomRight.dy + bottomLeft.dy) / 4,
    );
    return _CropGeometry(
      center: center,
      width: width,
      height: height,
      angle: angle,
      sourceRect: _axisAlignedRectForCorners(corners),
    );
  }

  Rect _axisAlignedRectForCorners(List<Offset> corners) {
    final minX = corners.map((point) => point.dx).reduce(math.min);
    final maxX = corners.map((point) => point.dx).reduce(math.max);
    final minY = corners.map((point) => point.dy).reduce(math.min);
    final maxY = corners.map((point) => point.dy).reduce(math.max);
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _syncCanCreateBoxes() {
    final max = maxBoxCount.value;
    final next =
        creationEnabled.value && (max == null || boxes.value.length < max);
    if (canCreateBoxesListenable.value != next) {
      canCreateBoxesListenable.value = next;
    }
  }

  void _syncSelectedBoxById(int? id) {
    if (id == null) {
      _setSelectedBox(null);
      return;
    }
    final index = boxes.value.indexWhere((element) => element.id == id);
    _setSelectedBox(index == -1 ? null : boxes.value[index]);
  }

  void _setSelectedBox(BBoxEntity? box) {
    if (selectedBoxListenable.value == box) return;
    selectedBoxListenable.value = box;
  }

  @override
  void dispose() {
    bBoxTool.dispose();
    creationEnabled.dispose();
    maxBoxCount.dispose();
    canCreateBoxesListenable.dispose();
    boxes.dispose();
    selectedBoxListenable.dispose();
    currentSourceFrame.dispose();
    capturedSourceFrame.dispose();
    _events.close();
    super.dispose();
  }
}

class _CropGeometry {
  const _CropGeometry({
    required this.center,
    required this.width,
    required this.height,
    required this.angle,
    required this.sourceRect,
  });

  final Offset center;
  final double width;
  final double height;
  final double angle;
  final Rect sourceRect;
}
