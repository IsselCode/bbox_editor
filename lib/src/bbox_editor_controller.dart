import 'dart:async';
import 'package:flutter/material.dart';
import '../exports.dart';

class BBoxEditorController extends ChangeNotifier {
  // --- Tamaños y mapper
  late Size _viewSize;
  Size get viewSize => _viewSize;
  set viewSize(Size v) => _viewSize = v;
  late Size sourceResolution;

  // Herramienta seleccionada
  final ValueNotifier<BBoxTool> bBoxTool = ValueNotifier(BBoxTool.auto);
  void setTool(BBoxTool tool) => bBoxTool.value = tool;

  // Control de creación de boxes
  final ValueNotifier<bool> creationEnabled = ValueNotifier(true);
  final ValueNotifier<int?> maxBoxCount = ValueNotifier(null);

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

  bool get canCreateBoxes {
    if (!creationEnabled.value) return false;
    final max = maxBoxCount.value;
    if (max == null) return true;
    return boxes.value.length < max;
  }

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

  // --- Estado reactivo de boxes
  final ValueNotifier<List<BBoxEntity>> boxes = ValueNotifier(const []);

  // --- Eventos (opcional si te sirven)
  final _events = StreamController<BBoxEvent>.broadcast();
  Stream<BBoxEvent> get events => _events.stream;

  // --- Hooks que antes vivían en MultiBBoxOverlayController
  VoidCallback? _ovClearAll;
  void Function(int id, CommitOrigin commitOrigin)? _ovRemove;
  void Function(BBoxEntity box, CommitOrigin commitOrigin)? _ovAdd;
  void Function(List<BBoxEntity> boxes)? _ovSetAll;
  void Function(int id, BBoxEntity box, CommitOrigin commitOrigin)? _ovUpdate;
  void Function(int? id, CommitOrigin commitOrigin)? _ovSelected;
  VoidCallback? _cameraCapture;
  VoidCallback? _cameraResumePreview;

  /// Llamado por el overlay en su initState
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

  /// Llamado por el overlay en su dispose
  void detachOverlay() {
    _ovClearAll = null;
    _ovRemove = null;
    _ovAdd = null;
    _ovSetAll = null;
    _ovUpdate = null;
    _ovSelected = null;
  }

  void attachCamera({
    required VoidCallback capture,
    required VoidCallback resumePreview,
  }) {
    _cameraCapture = capture;
    _cameraResumePreview = resumePreview;
  }

  void detachCamera() {
    _cameraCapture = null;
    _cameraResumePreview = null;
  }

  // --- API externa para el padre/negocio y también usada por el overlay

  void setInitialBoxes(List<BBoxEntity> list) {
    boxes.value = List.unmodifiable(list);
    _ovSetAll?.call(
      list,
    ); // notifica al overlay para sincronizar su buffer interno si tiene
    // (No emito evento aquí para evitar ruido si no lo necesitas)
  }

  void clearAll() {
    boxes.value = const [];
    _ovClearAll?.call();
    _events.add(const BoxesCleared(origin: CommitOrigin.controller));
  }

  void captureCameraImage() {
    _cameraCapture?.call();
  }

  void resumeCameraPreview() {
    _cameraResumePreview?.call();
  }

  Future<void> addBox(
    BBoxEntity b, {
    CommitOrigin commitOrigin = CommitOrigin.controller,
  }) async {
    if (!canCreateBoxes) return;
    boxes.value = [...boxes.value, b];
    _ovAdd?.call(b, commitOrigin);
    _events.add(BoxCreated(box: b, origin: commitOrigin));
  }

  BBoxEntity? selectedBox;
  Future<void> setSelectedBox(
    int? id, {
    CommitOrigin commitOrigin = CommitOrigin.controller,
  }) async {
    if (id != null) {
      selectedBox = boxes.value.singleWhere((element) => element.id == id);
    } else {
      selectedBox = null;
    }
    _ovSelected?.call(id, commitOrigin);
  }

  Future<void> selected(
    BBoxEntity b, {
    CommitOrigin commitOrigin = CommitOrigin.controller,
  }) async {
    if (!canCreateBoxes) return;
    boxes.value = [...boxes.value, b];
    _ovAdd?.call(b, commitOrigin);
    _events.add(BoxCreated(box: b, origin: commitOrigin));
  }

  Future<void> removeBox(
    int id, {
    CommitOrigin commitOrigin = CommitOrigin.controller,
  }) async {
    boxes.value = boxes.value.where((e) => e.id != id).toList(growable: false);
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
    final updated = b;
    final l = [...boxes.value]..[i] = updated;
    boxes.value = l;
    _ovUpdate?.call(b.id, b, commitOrigin);
    _events.add(BoxUpdated(box: b, origin: commitOrigin));
  }

  @override
  void dispose() {
    bBoxTool.dispose();
    creationEnabled.dispose();
    maxBoxCount.dispose();
    boxes.dispose();
    _events.close();
    super.dispose();
  }
}
