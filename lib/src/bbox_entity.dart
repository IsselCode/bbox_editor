import 'dart:math' as math;
import 'dart:ui';

import '../exports.dart';

part 'bbox_entity_parser.dart';

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

class BBoxViewGeometry {
  BBoxViewGeometry({
    required this.center,
    required this.width,
    required this.height,
    this.angleRadians = 0,
  });

  Offset center;
  double width;
  double height;
  double angleRadians;

  BBoxRelativeGeometry toRelative(Size viewSize) {
    final safeWidth = viewSize.width == 0 ? 1.0 : viewSize.width;
    final safeHeight = viewSize.height == 0 ? 1.0 : viewSize.height;
    return BBoxRelativeGeometry(
      center: Offset(center.dx / safeWidth, center.dy / safeHeight),
      width: width / safeWidth,
      height: height / safeHeight,
      angle: angleRadians,
    );
  }
}

class BBoxFrameGeometry {
  BBoxFrameGeometry({
    this.absoluteX,
    this.absoluteY,
    this.absoluteCenterX,
    this.absoluteCenterY,
    this.width,
    this.height,
    this.relativeCenterX,
    this.relativeCenterY,
    this.angleDegrees,
    this.sourceCropRect,
  });

  double? absoluteX;
  double? absoluteY;
  double? absoluteCenterX;
  double? absoluteCenterY;
  double? width;
  double? height;
  double? relativeCenterX;
  double? relativeCenterY;
  double? angleDegrees;
  Rect? sourceCropRect;

  Offset? get center {
    final x = absoluteCenterX;
    final y = absoluteCenterY;
    if (x == null || y == null) return null;
    return Offset(x, y);
  }

  set center(Offset? value) {
    absoluteCenterX = value?.dx;
    absoluteCenterY = value?.dy;
    _syncAbsoluteTopLeft();
  }

  bool get isResolved =>
      absoluteX != null &&
      absoluteY != null &&
      absoluteCenterX != null &&
      absoluteCenterY != null &&
      width != null &&
      height != null &&
      relativeCenterX != null &&
      relativeCenterY != null &&
      angleDegrees != null;

  void syncFromAbsoluteCenter({
    required double centerX,
    required double centerY,
    required double width,
    required double height,
    required Size sourceResolution,
  }) {
    absoluteCenterX = centerX;
    absoluteCenterY = centerY;
    this.width = width;
    this.height = height;
    absoluteX = centerX - (width / 2);
    absoluteY = centerY - (height / 2);
    relativeCenterX = width / 2;
    relativeCenterY = height / 2;
  }

  void _syncAbsoluteTopLeft() {
    if (absoluteCenterX == null ||
        absoluteCenterY == null ||
        width == null ||
        height == null) {
      return;
    }
    absoluteX = absoluteCenterX! - (width! / 2);
    absoluteY = absoluteCenterY! - (height! / 2);
  }

  BBoxRelativeGeometry toRelative(Size sourceResolution) {
    final safeWidth = sourceResolution.width == 0
        ? 1.0
        : sourceResolution.width;
    final safeHeight = sourceResolution.height == 0
        ? 1.0
        : sourceResolution.height;
    return BBoxRelativeGeometry(
      center: center == null
          ? null
          : Offset(center!.dx / safeWidth, center!.dy / safeHeight),
      width: width == null ? null : width! / safeWidth,
      height: height == null ? null : height! / safeHeight,
      angle: angleDegrees,
      sourceCropRect: sourceCropRect == null
          ? null
          : Rect.fromLTWH(
              sourceCropRect!.left / safeWidth,
              sourceCropRect!.top / safeHeight,
              sourceCropRect!.width / safeWidth,
              sourceCropRect!.height / safeHeight,
            ),
    );
  }
}

class BBoxRelativeGeometry {
  const BBoxRelativeGeometry({
    required this.center,
    required this.width,
    required this.height,
    required this.angle,
    this.sourceCropRect,
  });

  final Offset? center;
  final double? width;
  final double? height;
  final double? angle;
  final Rect? sourceCropRect;

  bool get isResolved => center != null && width != null && height != null;
}

class BBoxEntity {
  final int id;
  final BBoxViewGeometry view;
  final BBoxFrameGeometry frame;
  String? tag;
  bool showTag;
  Color color;

  BBoxEntity({
    int? id,
    required Offset center,
    required double w,
    required double h,
    double angle = 0,
    this.color = const Color(0xff0f52ff),
    this.tag,
    this.showTag = true,
    BBoxFrameGeometry? frame,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch,
       view = BBoxViewGeometry(
         center: center,
         width: w,
         height: h,
         angleRadians: angle,
       ),
       frame = frame ?? BBoxFrameGeometry();

  Offset get center => view.center;
  set center(Offset value) => view.center = value;

  double get w => view.width;
  set w(double value) => view.width = value;

  double get h => view.height;
  set h(double value) => view.height = value;

  double get angle => view.angleRadians;
  set angle(double value) => view.angleRadians = value;

  Offset get centerF => _requireFrameValue(
    frame.center,
    'frame.center no esta disponible todavia',
  );
  set centerF(Offset value) => frame.center = value;

  double get wF =>
      _requireFrameValue(frame.width, 'frame.width no esta disponible todavia');
  set wF(double value) => frame.width = value;

  double get hF => _requireFrameValue(
    frame.height,
    'frame.height no esta disponible todavia',
  );
  set hF(double value) => frame.height = value;

  double get angleDegScreen => _requireFrameValue(
    frame.angleDegrees,
    'frame.angleDegrees no esta disponible todavia',
  );
  set angleDegScreen(double value) => frame.angleDegrees = value;

  Rect? get sourceCropRect => frame.sourceCropRect;
  set sourceCropRect(Rect? value) => frame.sourceCropRect = value;

  T _requireFrameValue<T>(T? value, String message) {
    if (value == null) {
      throw StateError(message);
    }
    return value;
  }

  factory BBoxEntity.fromServerJson(
    Map<String, dynamic> j, {
    required FitCoverMapper mapper,
  }) => BBoxEntityParser.fromServerJson(j, mapper: mapper);

  factory BBoxEntity.fromServerCornersJson(
    Map<String, dynamic> j, {
    required FitCoverMapper mapper,
  }) => BBoxEntityParser.fromServerCornersJson(j, mapper: mapper);

  void setFrameCoords(FitCoverMapper mapper) {
    final centerFrame = mapper.pViewToFrame(center);
    final widthFrame = mapper.lenViewToFrame(w);
    final heightFrame = mapper.lenViewToFrame(h);
    frame.syncFromAbsoluteCenter(
      centerX: centerFrame.dx,
      centerY: centerFrame.dy,
      width: widthFrame,
      height: heightFrame,
      sourceResolution: mapper.camRes,
    );
    frame.angleDegrees = angle * 180.0 / math.pi;
  }

  BBoxRelativeGeometry relativeView(Size viewSize) => view.toRelative(viewSize);

  BBoxRelativeGeometry relativeFrame(Size sourceResolution) =>
      frame.toRelative(sourceResolution);

  Offset localToWorld(Offset p) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c) + center;
  }

  Offset worldToLocal(Offset p) {
    final q = p - center;
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(q.dx * c + q.dy * s, -q.dx * s + q.dy * c);
  }

  List<Offset> get corners {
    final hw = w / 2;
    final hh = h / 2;
    final pts = [
      Offset(-hw, -hh),
      Offset(hw, -hh),
      Offset(hw, hh),
      Offset(-hw, hh),
    ];
    return pts.map(localToWorld).toList();
  }

  Map<Handle, Offset> handlePositions({double gap = 0}) {
    final hw = w / 2;
    final hh = h / 2;
    return {
      Handle.tl: localToWorld(Offset(-hw, -hh)),
      Handle.tr: localToWorld(Offset(hw, -hh)),
      Handle.br: localToWorld(Offset(hw, hh)),
      Handle.bl: localToWorld(Offset(-hw, hh)),
      Handle.t: localToWorld(Offset(0, -hh - gap)),
      Handle.r: localToWorld(Offset(hw + gap, 0)),
      Handle.b: localToWorld(Offset(0, hh + gap)),
      Handle.l: localToWorld(Offset(-hw - gap, 0)),
    };
  }

  Offset rotateHandle([double gap = 24]) =>
      localToWorld(Offset(0, -(h / 2 + gap)));

  bool contains(Offset world) => worldToLocal(
    world,
  ).let((p) => p.dx.abs() <= w / 2 && p.dy.abs() <= h / 2);

  static Color _colorFromHex(String hex) {
    final h = hex.replaceAll('#', '').toUpperCase();
    final r = int.parse(h.substring(0, 2), radix: 16);
    final g = int.parse(h.substring(2, 4), radix: 16);
    final b = int.parse(h.substring(4, 6), radix: 16);
    return Color.fromARGB(0xFF, r, g, b);
  }

  static Color _colorFromBgr(List<int> bgr) {
    final b = bgr[0] & 0xFF;
    final g = bgr[1] & 0xFF;
    final r = bgr[2] & 0xFF;
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
    Rect? sourceCropRect,
    String? tag,
    bool? showTag,
  }) {
    final nextFrame = BBoxFrameGeometry(
      absoluteX: frame.absoluteX,
      absoluteY: frame.absoluteY,
      absoluteCenterX: centerF?.dx ?? frame.absoluteCenterX,
      absoluteCenterY: centerF?.dy ?? frame.absoluteCenterY,
      width: wF ?? frame.width,
      height: hF ?? frame.height,
      relativeCenterX: frame.relativeCenterX,
      relativeCenterY: frame.relativeCenterY,
      angleDegrees: angleDegScreen ?? frame.angleDegrees,
      sourceCropRect: sourceCropRect ?? frame.sourceCropRect,
    );
    nextFrame._syncAbsoluteTopLeft();

    return BBoxEntity(
      id: id ?? this.id,
      center: center ?? this.center,
      w: w ?? this.w,
      h: h ?? this.h,
      angle: angle ?? this.angle,
      color: color ?? this.color,
      tag: tag ?? this.tag,
      showTag: showTag ?? this.showTag,
      frame: nextFrame,
    );
  }
}

extension BBoxCanvasBounds on BBoxEntity {
  ({double halfWidth, double halfHeight}) get axisAlignedHalfExtents {
    final cosA = math.cos(angle).abs();
    final sinA = math.sin(angle).abs();
    return (
      halfWidth: (cosA * w / 2) + (sinA * h / 2),
      halfHeight: (sinA * w / 2) + (cosA * h / 2),
    );
  }

  Rect get axisAlignedBounds {
    final extents = axisAlignedHalfExtents;
    return Rect.fromCenter(
      center: center,
      width: extents.halfWidth * 2,
      height: extents.halfHeight * 2,
    );
  }

  bool fitsWithin(Size viewSize, {double epsilon = 0.001}) {
    final bounds = axisAlignedBounds;
    return bounds.left >= -epsilon &&
        bounds.top >= -epsilon &&
        bounds.right <= viewSize.width + epsilon &&
        bounds.bottom <= viewSize.height + epsilon;
  }

  BBoxEntity? clampCenterWithin(Size viewSize, {double epsilon = 0.001}) {
    final extents = axisAlignedHalfExtents;
    final maxWidth = (extents.halfWidth * 2) - epsilon;
    final maxHeight = (extents.halfHeight * 2) - epsilon;
    if (maxWidth > viewSize.width || maxHeight > viewSize.height) {
      return null;
    }

    return copyWith(
      center: Offset(
        center.dx
            .clamp(extents.halfWidth, viewSize.width - extents.halfWidth)
            .toDouble(),
        center.dy
            .clamp(extents.halfHeight, viewSize.height - extents.halfHeight)
            .toDouble(),
      ),
    );
  }
}
