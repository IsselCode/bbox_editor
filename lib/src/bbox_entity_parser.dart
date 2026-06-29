part of 'bbox_entity.dart';

class BBoxEntityParser {
  static BBoxEntity fromServerJson(
    Map<String, dynamic> json, {
    required FitCoverMapper mapper,
  }) {
    final centerFrame = Offset(
      (json['cx'] as num).toDouble(),
      (json['cy'] as num).toDouble(),
    );
    final widthFrame = (json['w'] as num).toDouble();
    final heightFrame = (json['h'] as num).toDouble();
    final angleDegrees = _readAngleDegrees(json);

    return _entityFromFrameGeometry(
      id: (json['id'] as num).toInt(),
      centerFrame: centerFrame,
      widthFrame: widthFrame,
      heightFrame: heightFrame,
      angleRadians: angleDegrees * math.pi / 180.0,
      angleDegrees: angleDegrees,
      color: _readColor(json),
      tag: _readTag(json['tag']),
      mapper: mapper,
    );
  }

  static BBoxEntity fromServerCornersJson(
    Map<String, dynamic> json, {
    required FitCoverMapper mapper,
  }) {
    final tl = _readPoint(json['tl'], 'tl');
    final tr = _readPoint(json['tr'], 'tr');
    final br = _readPoint(json['br'], 'br');
    final bl = _readPoint(json['bl'], 'bl');

    final centerFrame = Offset(
      (tl.dx + tr.dx + br.dx + bl.dx) / 4,
      (tl.dy + tr.dy + br.dy + bl.dy) / 4,
    );
    final widthFrame = (((tr - tl).distance) + ((br - bl).distance)) / 2;
    final heightFrame = (((bl - tl).distance) + ((br - tr).distance)) / 2;
    final angleRadians = _meanAngle([
      math.atan2(tr.dy - tl.dy, tr.dx - tl.dx),
      math.atan2(br.dy - bl.dy, br.dx - bl.dx),
    ]);
    final angleDegrees = angleRadians * 180.0 / math.pi;

    return _entityFromFrameGeometry(
      id: (json['id'] as num).toInt(),
      centerFrame: centerFrame,
      widthFrame: widthFrame,
      heightFrame: heightFrame,
      angleRadians: angleRadians,
      angleDegrees: angleDegrees,
      color: _readColor(json),
      tag: _readTag(json['tag']),
      mapper: mapper,
    );
  }

  static BBoxEntity _entityFromFrameGeometry({
    required int id,
    required Offset centerFrame,
    required double widthFrame,
    required double heightFrame,
    required double angleRadians,
    required double angleDegrees,
    required Color color,
    required String? tag,
    required FitCoverMapper mapper,
  }) {
    final frame = BBoxFrameGeometry(angleDegrees: angleDegrees);
    frame.syncFromAbsoluteCenter(
      centerX: centerFrame.dx,
      centerY: centerFrame.dy,
      width: widthFrame,
      height: heightFrame,
      sourceResolution: mapper.camRes,
    );

    return BBoxEntity(
      id: id,
      center: mapper.pFrameToView(centerFrame),
      w: mapper.lenFrameToView(widthFrame),
      h: mapper.lenFrameToView(heightFrame),
      angle: angleRadians,
      color: color,
      tag: tag,
      frame: frame,
    );
  }

  static Offset _readPoint(dynamic raw, String fieldName) {
    if (raw is! Map) {
      throw FormatException(
        'Expected "$fieldName" as a map with x/y numeric fields.',
      );
    }
    final x = raw['x'];
    final y = raw['y'];
    if (x is! num || y is! num) {
      throw FormatException(
        'Expected "$fieldName" to contain numeric "x" and "y" fields.',
      );
    }
    return Offset(x.toDouble(), y.toDouble());
  }

  static String? _readTag(dynamic raw) => raw == null ? null : raw.toString();

  static double _readAngleDegrees(Map<String, dynamic> json) {
    final raw = json['angle_deg'] ?? json['angle_deg_cv'] ?? 0;
    return raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0;
  }

  static Color _readColor(Map<String, dynamic> json) {
    if (json['color_hex'] is String) {
      return BBoxEntity._colorFromHex(json['color_hex'] as String);
    }
    if (json['color_bgr'] is List) {
      return BBoxEntity._colorFromBgr(List<int>.from(json['color_bgr'] as List));
    }
    return const Color(0xFF0F52FF);
  }

  static double _meanAngle(Iterable<double> angles) {
    var x = 0.0;
    var y = 0.0;
    for (final angle in angles) {
      x += math.cos(angle);
      y += math.sin(angle);
    }
    if (x == 0 && y == 0) return 0.0;
    return math.atan2(y, x);
  }
}
