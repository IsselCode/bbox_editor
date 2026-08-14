import 'dart:ui';

/// A passive quadrilateral drawn over the editor source.
///
/// [points] are expressed in pixels of the original source frame and must be
/// ordered clockwise: top-left, top-right, bottom-right, bottom-left.
class PolygonEntity {
  PolygonEntity({
    int? id,
    required List<Offset> points,
    this.color = const Color(0xFF00C853),
    this.fillColor,
    this.strokeWidth = 2,
    this.tag,
    this.showTag = true,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch,
       points = List.unmodifiable(points) {
    _validatePoints(points);
    if (!strokeWidth.isFinite || strokeWidth <= 0) {
      throw ArgumentError.value(
        strokeWidth,
        'strokeWidth',
        'strokeWidth must be finite and greater than zero',
      );
    }
  }

  final int id;
  final List<Offset> points;
  final Color color;
  final Color? fillColor;
  final double strokeWidth;
  final String? tag;
  final bool showTag;

  factory PolygonEntity.fromCoordinates(
    List<List<num>> coordinates, {
    int? id,
    Color color = const Color(0xFF00C853),
    Color? fillColor,
    double strokeWidth = 2,
    String? tag,
    bool showTag = true,
  }) {
    if (coordinates.length != 4) {
      throw ArgumentError.value(
        coordinates,
        'coordinates',
        'A polygon must contain exactly four [x, y] points',
      );
    }

    final points = coordinates
        .map((coordinate) {
          if (coordinate.length != 2) {
            throw ArgumentError.value(
              coordinate,
              'coordinates',
              'Every polygon point must have the form [x, y]',
            );
          }
          return Offset(coordinate[0].toDouble(), coordinate[1].toDouble());
        })
        .toList(growable: false);

    return PolygonEntity(
      id: id,
      points: points,
      color: color,
      fillColor: fillColor,
      strokeWidth: strokeWidth,
      tag: tag,
      showTag: showTag,
    );
  }

  List<List<double>> toCoordinates() => points
      .map((point) => <double>[point.dx, point.dy])
      .toList(growable: false);

  PolygonEntity copyWith({
    List<Offset>? points,
    Color? color,
    Color? fillColor,
    bool clearFillColor = false,
    double? strokeWidth,
    String? tag,
    bool clearTag = false,
    bool? showTag,
  }) {
    return PolygonEntity(
      id: id,
      points: points ?? this.points,
      color: color ?? this.color,
      fillColor: clearFillColor ? null : fillColor ?? this.fillColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      tag: clearTag ? null : tag ?? this.tag,
      showTag: showTag ?? this.showTag,
    );
  }

  static void _validatePoints(List<Offset> points) {
    if (points.length != 4) {
      throw ArgumentError.value(
        points,
        'points',
        'A polygon must contain exactly four points',
      );
    }
    if (points.any((point) => !point.dx.isFinite || !point.dy.isFinite)) {
      throw ArgumentError.value(
        points,
        'points',
        'Polygon coordinates must be finite',
      );
    }
  }
}
