import 'dart:async';
import 'package:flutter/material.dart';
import '../exports.dart';

class BBoxEditorController extends ChangeNotifier {
  // --- Tamaños y mapper
  late Size _viewSize;
  Size get viewSize => _viewSize;
  set viewSize(Size v) => _viewSize = v;
  late Size cameraResolution;

  // Herramienta seleccionada
  final ValueNotifier<BBoxTool> bBoxTool = ValueNotifier(BBoxTool.bboxs);
  void setTool(BBoxTool tool) => bBoxTool.value = tool;

  FitCoverMapper get mapper {
    assert(_viewSize.width > 0 && _viewSize.height > 0,
    'viewSize debe estar asignado antes de usar mapper');
    assert(cameraResolution.width > 0 && cameraResolution.height > 0,
    'cameraResolution debe estar asignado antes de usar mapper');
    return FitCoverMapper(_viewSize, cameraResolution);
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

  /// Llamado por el overlay en su initState
  void attachOverlay({
    required VoidCallback clearAll,
    required void Function(int id, CommitOrigin commitOrigin) remove,
    required void Function(BBoxEntity box, CommitOrigin commitOrigin) add,
    required void Function(List<BBoxEntity> boxes) setAll,
    required void Function(int id, BBoxEntity box, CommitOrigin commitOrigin) update,
    required void Function(int? id, CommitOrigin commitOrigin) selected
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

  // --- API externa para el padre/negocio y también usada por el overlay

  void setInitialBoxes(List<BBoxEntity> list) {
    boxes.value = List.unmodifiable(list);
    _ovSetAll?.call(list); // notifica al overlay para sincronizar su buffer interno si tiene
    // (No emito evento aquí para evitar ruido si no lo necesitas)
  }

  void clearAll() {
    boxes.value = const [];
    _ovClearAll?.call();
    _events.add(const BoxesCleared(origin: CommitOrigin.controller));
  }

  Future<void> addBox(BBoxEntity b, {CommitOrigin commitOrigin = CommitOrigin.controller}) async  {
    boxes.value = [...boxes.value, b];
    _ovAdd?.call(b, commitOrigin);
    _events.add(BoxCreated(box: b, origin: commitOrigin));
  }

  BBoxEntity? selectedBox;
  Future<void> setSelectedBox(int? id, {CommitOrigin commitOrigin = CommitOrigin.controller}) async {
    if (id != null ){
      selectedBox = boxes.value.singleWhere((element) => element.id == id);
    } else {
      selectedBox = null;
    }
    _ovSelected?.call(id, commitOrigin);
  }

  Future<void> selected(BBoxEntity b, {CommitOrigin commitOrigin = CommitOrigin.controller}) async  {
    boxes.value = [...boxes.value, b];
    _ovAdd?.call(b, commitOrigin);
    _events.add(BoxCreated(box: b, origin: commitOrigin));
  }

  Future<void> removeBox(int id, {CommitOrigin commitOrigin = CommitOrigin.controller}) async {
    boxes.value = boxes.value.where((e) => e.id != id).toList(growable: false);
    _ovRemove?.call(id, commitOrigin);
    _events.add(BoxDeleted(id: id, origin: commitOrigin));
  }

  Future<void> updateBox(int id, BBoxEntity b, {CommitOrigin commitOrigin = CommitOrigin.controller}) async {
    final i = boxes.value.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final old = boxes.value[i];
    final updated = b;
    final l = [...boxes.value]..[i] = updated;
    boxes.value = l;
    _ovUpdate?.call(b.id, b, commitOrigin);
    _events.add(BoxUpdated(box: b, origin: commitOrigin));
  }

  @override
  void dispose() {
    boxes.dispose();
    _events.close();
    super.dispose();
  }
}
