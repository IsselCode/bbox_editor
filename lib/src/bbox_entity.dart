import 'dart:math' as math;
import 'dart:ui';

import '../exports.dart';

extension _Let<T> on T { R let<R>(R Function(T) f) => f(this); }
typedef PointMap = Offset Function(Offset);
typedef LenMap = double Function(double);

class BBoxEntity {
  final int id;
  Offset center;  // en VISTA
  double w, h;    // en VISTA
  double angle;   // radianes (VISTA)
  /// Solo referenciativo
  String? tag;

  late Offset centerF;
  late double wF;
  late double hF;
  late double angleDegScreen;
  Color color;

  BBoxEntity({
    int? id,
    required this.center,
    required this.w,
    required this.h,
    this.angle = 0,
    this.color = const Color(0xff0f52ff),
    this.tag,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch;



  // --------------------------
  // Factory: SERVER JSON -> VIEW
  // --------------------------
  /// Detecta: angle_deg (db) o angle_deg_cv (worker); color_hex o color_bgr.
  /// Aplica el mapeo FRAME -> VIEW que le pases.
  factory BBoxEntity.fromServerJson(
    Map<String, dynamic> j, {
    required FitCoverMapper mapper,
  }) {
    final id = (j['id'] as num).toInt();
    final cxF = (j['cx'] as num).toDouble();
    final cyF = (j['cy'] as num).toDouble();
    final wF  = (j['w']  as num).toDouble();
    final hF  = (j['h']  as num).toDouble();
    final tag  = (j['tag']  as String);

    // ángulo en grados: 'angle_deg' (db) o 'angle_deg_cv' (worker)
    final angDeg =
    (j['angle_deg'] ?? j['angle_deg_cv'] ?? 0) is num
        ? (j['angle_deg'] ?? j['angle_deg_cv'] as num).toDouble()
        : double.tryParse('${j['angle_deg'] ?? j['angle_deg_cv']}') ?? 0.0;
    final angRad = angDeg * math.pi / 180.0;

    // color: hex o bgr
    Color color = const Color(0xFF0F52FF);
    if (j['color_hex'] is String) {
      color = _colorFromHex(j['color_hex'] as String);
    } else if (j['color_bgr'] is List) {
      color = _colorFromBgr(List<int>.from(j['color_bgr'] as List));
    }

    // FRAME -> VIEW
    final centerV = mapper.pFrameToView(Offset(cxF, cyF));
    final wV = mapper.lenFrameToView(wF);
    final hV = mapper.lenFrameToView(hF);

    return BBoxEntity(
      id: id,
      center: centerV,
      w: wV,
      h: hV,
      angle: angRad,
      color: color,
      tag: tag
    );
  }

  /// Asigna coordenadas y angulo para backend
  void setFrameCoords(FitCoverMapper mapper) {
    // centro y tamaños en coordenadas de FRAME
    centerF = mapper.pViewToFrame(center);
    wF = mapper.lenViewToFrame(w);
    hF = mapper.lenViewToFrame(h);
    // tu BBoxEntity usa ángulo en RAD → pásalo a GRADOS para el backend
    angleDegScreen = angle * 180.0 / math.pi;
  }


  // --------------------------
  // Geometría (ya lo tenías)
  // --------------------------
  Offset localToWorld(Offset p) {
    final c = math.cos(angle), s = math.sin(angle);
    return Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c) + center;
  }

  Offset worldToLocal(Offset p) {
    final q = p - center;
    final c = math.cos(angle), s = math.sin(angle);
    return Offset(q.dx * c + q.dy * s, -q.dx * s + q.dy * c);
  }

  List<Offset> get corners {
    final hw = w / 2, hh = h / 2;
    final pts = [Offset(-hw, -hh), Offset(hw, -hh), Offset(hw, hh), Offset(-hw, hh)];
    return pts.map(localToWorld).toList();
  }

  Map<Handle, Offset> handlePositions({double gap = 0}) {
    final hw = w / 2, hh = h / 2;
    return {
      Handle.tl: localToWorld(Offset(-hw, -hh)),
      Handle.tr: localToWorld(Offset(hw, -hh)),
      Handle.br: localToWorld(Offset(hw, hh)),
      Handle.bl: localToWorld(Offset(-hw, hh)),
      Handle.t : localToWorld(Offset(0, -hh - gap)),
      Handle.r : localToWorld(Offset(hw + gap, 0)),
      Handle.b : localToWorld(Offset(0, hh + gap)),
      Handle.l : localToWorld(Offset(-hw - gap, 0)),
    };
  }

  Offset rotateHandle([double gap = 24]) => localToWorld(Offset(0, -(h / 2 + gap)));
  bool contains(Offset world) => worldToLocal(world).let((p) => p.dx.abs() <= w/2 && p.dy.abs() <= h/2);

  // --------------------------
  // Helpers de color
  // --------------------------
  static Color _colorFromHex(String hex) {
    final h = hex.replaceAll('#', '').toUpperCase();
    final r = int.parse(h.substring(0, 2), radix: 16);
    final g = int.parse(h.substring(2, 4), radix: 16);
    final b = int.parse(h.substring(4, 6), radix: 16);
    return Color.fromARGB(0xFF, r, g, b);
  }

  static Color _colorFromBgr(List<int> bgr) {
    final b = bgr[0] & 0xFF, g = bgr[1] & 0xFF, r = bgr[2] & 0xFF;
    return Color.fromARGB(0xFF, r, g, b);
  }

  static String colorToHex(Color color, {bool leadingHashSign = true}) {
    String toHex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '${leadingHashSign ? '#' : ''}'
        '${toHex(color.red)}${toHex(color.green)}${toHex(color.blue)}';
  }
}

extension BBoxCopy on BBoxEntity {
  BBoxEntity copyWith({
    int? id,
    Offset? center,
    double? w,
    double? h,
    double? angle,
    Color? color,
    Offset? centerF,
    double? wF,
    double? hF,
    double? angleDegScreen,
    String? tag,
  }) {
    final clone = BBoxEntity(
      id: id ?? this.id,
      center: center ?? this.center,
      w: w ?? this.w,
      h: h ?? this.h,
      angle: angle ?? this.angle,
      color: color ?? this.color,
      tag: tag ?? this.tag,
    );

    // copiar también los campos "late"
    clone.centerF = centerF ?? this.centerF;
    clone.wF = wF ?? this.wF;
    clone.hF = hF ?? this.hF;
    clone.angleDegScreen = angleDegScreen ?? this.angleDegScreen;

    return clone;
  }
}


