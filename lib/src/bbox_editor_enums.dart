enum Mode { idle, draw, drag, rotate, resize }

enum Handle { none, tl, t, tr, r, br, b, bl, l }

enum BBoxTool { auto, zoom, bboxs }

enum ToolPolicy { platformDefault, enforced }

enum CommitOrigin { controller, overlay }

enum BBoxCameraMode { captureStill, livePreview }

enum BBoxCameraLensDirection { front, back, external }

enum BBoxCameraResolutionPreset { low, medium, high, veryHigh, ultraHigh, max }
