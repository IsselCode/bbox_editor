import '../exports.dart';

sealed class BBoxEvent {
  final CommitOrigin origin;
  const BBoxEvent({required this.origin});
}

class BoxCreated extends BBoxEvent {
  final BBoxEntity box;
  const BoxCreated({required this.box, required super.origin});
}

class BoxUpdated extends BBoxEvent {
  final BBoxEntity box;
  const BoxUpdated({required this.box, required super.origin});
}

class BoxDeleted extends BBoxEvent {
  final int id;
  const BoxDeleted({required this.id, required super.origin});
}

class BoxSelected extends BBoxEvent {
  final BBoxEntity? box;
  const BoxSelected({this.box, required super.origin});
}

class BoxesCleared extends BBoxEvent { const BoxesCleared({required super.origin}); }