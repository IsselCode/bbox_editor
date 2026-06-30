import 'bbox_editor_enums.dart';

class BBoxEditorControlsConfig {
  const BBoxEditorControlsConfig({
    this.showRotateControl = true,
    this.showDeleteControl = true,
    this.interactionMode = BBoxInteractionMode.directEdit,
  });

  final bool showRotateControl;
  final bool showDeleteControl;
  final BBoxInteractionMode interactionMode;
}
