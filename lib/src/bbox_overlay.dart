import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../exports.dart';

class BBoxOverlay extends StatefulWidget {
  const BBoxOverlay({
    super.key,
    required this.viewSize,                         // tamaño del área del video (VISTA)
    required this.camResolution,
    this.onCommitBox, // (box, kind)
    required this.controller,
    this.initialBoxes = const [],
    this.minW = 20,
    this.minH = 20,
  });

  final Size viewSize;
  final Size camResolution;
  final List<BBoxEntity> initialBoxes;
  final double minW, minH;
  final BBoxEditorController controller;
  final void Function(BBoxEvent event)? onCommitBox;

  @override
  State<BBoxOverlay> createState() => _BBoxOverlayState();
}

class _BBoxOverlayState extends State<BBoxOverlay> {
  final List<BBoxEntity> _boxes = [];
  int? _selected;                  // id seleccionado
  Mode _mode = Mode.idle;
  Handle _activeHandle = Handle.none;

  // edición
  BBoxEntity? _live;             // copia mientras editas
  Offset? _drawStart;              // creación
  Offset? _dragDeltaLocal;         // drag
  double? _startVecAngle, _angleStart; // rotate

  //
  BBoxEntity? _editBase;   // ← box “congelado” al iniciar el gesto

  @override
  void initState() {
    super.initState();
    _boxes.addAll(widget.initialBoxes.map((b) => BBoxEntity(
      id: b.id, center: b.center, w: b.w, h: b.h, angle: b.angle, color: b.color, tag: b.tag
    )));
    widget.controller?.attachOverlay(
      clearAll: _clearAll,
      remove: _removeById,
      add: _addBox,
      update: _updateBox,
      selected: _selectedMethod,
      setAll: (lst) { _boxes
        ..clear()
        ..addAll(lst.map((b)=>BBoxEntity(id:b.id,center:b.center,w:b.w,h:b.h,angle:b.angle,color:b.color,tag: b.tag)));
      _selected = null; _endEdit(commit:false);
      },
    );
  }

  @override
  void didUpdateWidget(covariant BBoxOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detachOverlay();
      widget.controller?.attachOverlay(
        clearAll: _clearAll,
        remove: _removeById,
        add: _addBox,
        update: _updateBox,
        selected: _selectedMethod,
        setAll: (lst) { _boxes
          ..clear()
          ..addAll(lst.map((b)=>BBoxEntity(id:b.id,center:b.center,w:b.w,h:b.h,angle:b.angle,color:b.color, tag: b.tag)));
        _selected = null; _endEdit(commit:false);
        },
      );
    }
  }

  @override
  void dispose() {
    widget.controller?.detachOverlay();
    super.dispose();
  }

  // --- API interna para controller ---
  Future<void> _clearAll() async { setState(() { _boxes.clear(); _selected = null; _cancelEdit(); }); }
  Future<void> _removeById(int id, CommitOrigin commitOrigin) async {
    // guarda copia para enviar delta
    // (Por si se requiere actualización)
    final removed = _boxes.firstWhere((b)=>b.id==id, orElse: ()=>BBoxEntity(id:id,center:Offset.zero, w:0, h:0));

    setState(() {
      _boxes.removeWhere((b)=>b.id==id);
      if (_selected==id) _selected=null;
      _cancelEdit();
    });

    // Enviar commit al padre cuando la actualización viene del controller
      widget.onCommitBox?.call(BoxDeleted(id: id, origin: commitOrigin));
  }
  Future<void> _addBox(BBoxEntity b, CommitOrigin commitOrigin) async {
    setState(() {
      final mapper = FitCoverMapper(widget.viewSize, widget.camResolution);
      b.setFrameCoords(mapper);
      _boxes.add(b);
      _selected = b.id;
    });
      // Enviar commit al padre cuando la actualización viene del controller
      widget.onCommitBox?.call(BoxCreated(box: b, origin: commitOrigin));
    }
  Future<void> _updateBox(int id, BBoxEntity box, CommitOrigin commitOrigin) async {
    setState(() {
      final mapper = FitCoverMapper(widget.viewSize, widget.camResolution);
      box.setFrameCoords(mapper);
      int ibbox = _boxes.indexWhere((element) => element.id == box.id,);
      _boxes[ibbox] = box;
    });

    // Se envia el commit
    widget.onCommitBox?.call(BoxUpdated(box: box, origin: commitOrigin));
  }
  Future<void> _selectedMethod(int? id, CommitOrigin commitOrigin) async {

    if (id != null ){

      // Trae el box al frente y solo selección (sin live ni edición)
      final idx = _boxes.indexWhere((b) => b.id == id);
      if (idx != -1) {
        final box = _boxes.removeAt(idx);
        _boxes.add(box);
        widget.onCommitBox?.call(BoxSelected(origin: commitOrigin, box: box));
        _selected = box.id;
      }
      _live = null;
      _mode = Mode.idle;
      _activeHandle = Handle.none;

    } else {
      _selected = null;
      _live = null;
      _mode = Mode.idle;
      _activeHandle = Handle.none;
      widget.onCommitBox?.call(BoxSelected(origin: commitOrigin));
    }
    setState(() {});
  }

  ({int id, Handle handle, bool rotate, double dist})? _hitTest(Offset pos) {
    const handleR = 16.0;    // para resize
    const rotateR = 22.0;    // 🔁 para rotación (overlay level)
    final candidates = <({int id,Handle handle,bool rotate,double dist})>[];

    for (final b in _boxes) {
      // ROTATE (overlay, no botón)
      final rh = b.rotateHandle();
      final dr = (rh - pos).distance;
      if (dr <= rotateR) candidates.add((id:b.id, handle:Handle.none, rotate:true, dist:dr));

      // RESIZE handles
      final hs = b.handlePositions();
      hs.forEach((h, p) {
        final d = (p - pos).distance;
        if (d <= handleR) candidates.add((id:b.id, handle:h, rotate:false, dist:d));
      });

      // DRAG interior
      if (b.contains(pos)) {
        candidates.add((id:b.id, handle:Handle.none, rotate:false, dist:handleR));
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a,b)=>a.dist.compareTo(b.dist));
    return candidates.first;
  }

  // --- Gestos ---
  void _onTapDown(TapDownDetails d) async {
    final pos = d.localPosition; // si estás usando matriz de IV, aquí iría _toScene(pos)
    final hit = _hitTest(pos);

    if (hit != null) {
      widget.controller.setSelectedBox(hit.id, commitOrigin: CommitOrigin.overlay);
    } else {
      widget.controller.setSelectedBox(null, commitOrigin: CommitOrigin.overlay);
    }
  }

  void _onPanStart(DragStartDetails d) {
    final pos = d.localPosition;
    final hit = _hitTest(pos);

    if (hit != null) {
      // selecciona y trae al frente
      final idx = _boxes.indexWhere((b)=>b.id==hit.id);
      if (idx != -1) {
        setState(() {
          final box = _boxes.removeAt(idx);
          _boxes.add(box);               // al frente
          _selected = box.id;
          _live = BBoxEntity(id: box.id, center: box.center, w: box.w, h: box.h, angle: box.angle, color: box.color, tag: box.tag);
        });
      }

      if (hit.rotate) {
        final b = _boxes.last;
        _mode = Mode.rotate;
        _startVecAngle = math.atan2(pos.dy - b.center.dy, pos.dx - b.center.dx);
        _angleStart = b.angle;
        setState(() {});
        return;
      }

      if (hit.handle != Handle.none) {
        _mode = Mode.resize;
        _activeHandle = hit.handle;
        // congela el box tal como estaba al inicio del gesto
        final b = _boxes.last;
        _editBase = BBoxEntity(
          id: b.id, center: b.center, w: b.w, h: b.h, angle: b.angle, color: b.color, tag: b.tag
        );
        setState(() {});
        return;
      }

      // interior -> drag
      _mode = Mode.drag;
      final b = _boxes.last;
      _dragDeltaLocal = b.worldToLocal(pos);
      setState(() {});
      return;
    }

    // fuera de todos -> crear nuevo
    _mode = Mode.draw;
    _activeHandle = Handle.none;
    _selected = null;
    _drawStart = pos;
    _live = BBoxEntity(center: pos, w: 1, h: 1);
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final pos = d.localPosition;
    final live = _live; if (live == null) return;

    switch (_mode) {
      case Mode.draw:
        final s = _drawStart!;
        final cx = (s.dx + pos.dx) / 2, cy = (s.dy + pos.dy) / 2;
        _live = BBoxEntity(id: live.id,
          center: Offset(cx, cy),
          w: (pos.dx - s.dx).abs().clamp(widget.minW, double.infinity),
          h: (pos.dy - s.dy).abs().clamp(widget.minH, double.infinity),
          angle: 0,
          color: Color(0xff0f52ff),
          tag: live.tag
        );
        break;

      case Mode.drag:
        final b = _boxes.last; // seleccionado al frente
        final local = _dragDeltaLocal ?? Offset.zero;
        final c = math.cos(b.angle), s = math.sin(b.angle);
        final worldDelta = Offset(local.dx * c - local.dy * s, local.dx * s + local.dy * c);
        var newCenter = pos - worldDelta;
        final hw = live.w / 2, hh = live.h / 2;
        newCenter = Offset(
          newCenter.dx.clamp(hw, widget.viewSize.width - hw),
          newCenter.dy.clamp(hh, widget.viewSize.height - hh),
        );
        _live = BBoxEntity(id: live.id, center: newCenter, w: live.w, h: live.h, angle: live.angle, color: b.color, tag: b.tag);
        break;

      case Mode.rotate:
        final b = _boxes.last;
        final aNow = math.atan2(pos.dy - b.center.dy, pos.dx - b.center.dx);
        var ang = (_angleStart ?? 0) + (aNow - (_startVecAngle ?? 0));
        if (ang > math.pi) ang -= 2*math.pi;
        if (ang < -math.pi) ang += 2*math.pi;
        _live = BBoxEntity(id: live.id, center: b.center, w: b.w, h: b.h, angle: ang, color: b.color, tag: b.tag);
        break;

      case Mode.resize:
        final base = _editBase ?? _boxes.last;  // ← base congelada
        _live = _resizeFromHandle(base, live, _activeHandle, pos, widget.minW, widget.minH);
        break;

      case Mode.idle:
        break;
    }
    setState(() {});
  }

  Future<void> _onPanEnd() async => _endEdit(commit: true);

  void _cancelEdit() {
    _mode = Mode.idle; _activeHandle = Handle.none;
    _live = null; _drawStart = null; _dragDeltaLocal = null;
    _startVecAngle = null; _angleStart = null;
    _editBase = null;
  }

  Future<void> _endEdit({required bool commit}) async {
    BBoxEntity? live = _live;

    if (commit && live != null) {
      final idx = _boxes.indexWhere((b)=>b.id==live.id);
      final isCreate = idx == -1;

      if (isCreate) {
        widget.controller.addBox(live, commitOrigin: CommitOrigin.overlay);
      } else {
        _boxes[idx] = live;
        widget.controller.updateBox(live.id, live, commitOrigin: CommitOrigin.overlay);
      }
    }
    _cancelEdit();
  }


  // --------- resize (en ejes locales) ---------
  BBoxEntity _resizeFromHandle(
      BBoxEntity base,   // caja CONGELADA al panStart (ejes fijos)
      BBoxEntity cur,    // copia que vamos mostrando
      Handle h,
      Offset posWorld,
      double minW,
      double minH,
      ) {
    // Cursor en COORDENADAS LOCALES del base
    final p = base.worldToLocal(posWorld);

    final hwB = base.w / 2, hhB = base.h / 2;   // semiejes del BASE
    final minHW = minW / 2, minHH = minH / 2;

    // Nuevo centro en local (acumulado por ejes)
    double cx = 0.0, cy = 0.0;
    // Nuevos semiejes
    double hw = hwB, hh = hhB;

    // ---- Helpers que colocan el borde ACTIVO justo en el cursor ----
    // Mantienen fijo el borde opuesto del BASE.
    void dragRight() {
      // Borde fijo: x = -hwB ; borde nuevo: x = p.dx
      final px = math.max(p.dx, 2*minHW - hwB); // clamp para tamaño mínimo
      hw = (px + hwB) / 2.0;                    // semieje nuevo
      cx = (px - hwB) / 2.0;                    // centro local en X
    }

    void dragLeft() {
      // Borde fijo: x = +hwB ; borde nuevo: x = p.dx (negativo)
      final px = math.min(p.dx, hwB - 2*minHW);
      hw = (hwB - px) / 2.0;
      cx = (px + hwB) / 2.0;
    }

    void dragBottom() {
      // Borde fijo: y = -hhB ; borde nuevo: y = p.dy
      final py = math.max(p.dy, 2*minHH - hhB);
      hh = (py + hhB) / 2.0;
      cy = (py - hhB) / 2.0;
    }

    void dragTop() {
      // Borde fijo: y = +hhB ; borde nuevo: y = p.dy (negativo)
      final py = math.min(p.dy, hhB - 2*minHH);
      hh = (hhB - py) / 2.0;
      cy = (py + hhB) / 2.0;
    }

    switch (h) {
      case Handle.r:  dragRight(); break;
      case Handle.l:  dragLeft();  break;
      case Handle.b:  dragBottom(); break;
      case Handle.t:  dragTop();    break;

      case Handle.tr: dragRight(); dragTop(); break;
      case Handle.br: dragRight(); dragBottom(); break;
      case Handle.tl: dragLeft();  dragTop(); break;
      case Handle.bl: dragLeft();  dragBottom(); break;

      case Handle.none: break;
    }

    // Centro LOCAL → MUNDO según ángulo del BASE
    final c = math.cos(base.angle), s = math.sin(base.angle);
    final worldShift = Offset(cx * c - cy * s, cx * s + cy * c);
    final newCenter = base.center + worldShift;

    final newW = (hw * 2).clamp(minW, double.infinity);
    final newH = (hh * 2).clamp(minH, double.infinity);

    return BBoxEntity(
      id: cur.id,
      center: newCenter,
      w: newW,
      h: newH,
      angle: base.angle,
      color: cur.color,
      tag: cur.tag
    );
  }

  // --------- HELPERS

  BBoxEntity? get _selectedBox {
    if (_selected == null) return null;
    final idx = _boxes.indexWhere((b)=>b.id==_selected);
    return idx == -1 ? null : _boxes[idx];
  }

  Future<void> _deleteSelected() async {
    final id = _selected;
    if (id == null) return;
    widget.controller.removeBox(id, commitOrigin: CommitOrigin.overlay);
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selectedBox;
    // puntos de referencia del bbox seleccionado
    Offset? rotatePos, deletePos;
    if (sel != null) {
      rotatePos = sel.rotateHandle(); // arriba al centro
      final tr = sel.handlePositions()[Handle.tr]; // esquina superior derecha
      if (tr != null) {
        // levanta un poco el botón para no tapar la manija
        deletePos = tr.translate(0, -20);
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onTapDown: _onTapDown,
      onPanEnd: (_) => _onPanEnd(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _MultiPainter(
              boxes: _boxes,
              selectedId: _selected,
              live: _live,
            ),
          ),

          if (sel != null && rotatePos != null)
          Positioned(
            left: rotatePos.dx - 10,
            top: rotatePos.dy - 15,
            child: IgnorePointer(
              child: Icon(Icons.crop_rotate, size: 20, color: Colors.white,)
            ),
          ),

          if (sel != null && deletePos != null)
            Positioned(
              left: deletePos.dx - 18,
              top: deletePos.dy - 18,
              child: IconButton(
                onPressed: _deleteSelected,
                icon: Icon(Icons.delete_outline, color: Colors.red, size: 20,),
              ),
            ),
        ],
      ),
    );
  }

}

class _MultiPainter extends CustomPainter {
  final List<BBoxEntity> boxes;
  final int? selectedId;
  final BBoxEntity? live;

  _MultiPainter({required this.boxes, this.selectedId, this.live});

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in boxes) {
      final path = _obbPath(b);
      final isSel = b.id == selectedId;
      final paintBox = Paint()
        ..color = b.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? 2.5 : 1.6;

      // sombra fuera
      if (isSel) {
        final overlay = Paint()..color = Colors.black.withOpacity(0.25);
        final full = Path()..addRect(Offset.zero & size);
        canvas.drawPath(Path.combine(PathOperation.difference, full, path), overlay);
      }
      canvas.drawPath(path, paintBox);

      if (isSel) {
        // handles
        final hs = b.handlePositions();
        final ph = Paint()..color = Colors.white..style = PaintingStyle.fill;
        for (final p in hs.values) {
          canvas.drawRect(Rect.fromCenter(center: p, width: 8, height: 8), ph);
        }
      }

    }
    if (live != null) {
      final path = _obbPath(live!);
      canvas.drawPath(path, Paint()
        ..color = Color(0xff0f52ff)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
  }

  Path _obbPath(BBoxEntity b) {
    final p = Path()..addPolygon(b.corners, true);
    return p;
  }

  @override
  bool shouldRepaint(covariant _MultiPainter old) =>
      old.boxes != boxes || old.selectedId != selectedId || old.live != live;
}

