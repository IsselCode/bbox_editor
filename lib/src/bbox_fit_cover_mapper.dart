// Mapeo para BoxFit.cover: de coordenadas de vista (widget) a frame real
import 'dart:math' as math;
import 'dart:ui';

class FitCoverMapper {
  final Size view;   // tamaño del widget que muestra el video
  final Size camRes;  // resolución real del frame (usa /meta del backend)
  late final double _scale;
  late final double _dx;
  late final double _dy;

  late final double _offX;
  late final double _offY;

  FitCoverMapper(this.view, this.camRes) {
    final sx = view.width / camRes.width;
    final sy = view.height / camRes.height;
    _scale = math.max(sx, sy);
    _offY  = (view.height - camRes.height * _scale) / 2.0;
    _offX = (view.width  - camRes.width * _scale) / 2.0;
    _dx = (view.width  - camRes.width * _scale) / 2.0;
    _dy = (view.height - camRes.height * _scale) / 2.0;
  }

  // FRAME -> VIEW
  Offset pFrameToView(Offset p) => Offset(p.dx * _scale + _offX, p.dy * _scale + _offY);
  double lenFrameToView(double l) => l * _scale;

  Offset pViewToFrame(Offset p) {
    final fx = (p.dx - _dx) / _scale;
    final fy = (p.dy - _dy) / _scale;
    return Offset(
      fx.clamp(0, camRes.width),
      fy.clamp(0, camRes.height),
    );
  }

  double lenViewToFrame(double l) => l / _scale;
}