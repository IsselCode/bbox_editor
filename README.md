# bbox_editor

Flutter widget para crear, editar y consumir bounding boxes sobre tres tipos de fuente:

- `image`: imagen estática
- `stream`: stream MJPEG por URL
- `camera`: cámara del dispositivo

## Conceptos

- `view`: coordenadas visibles del canvas en pantalla
- `source`: coordenadas reales de la fuente visual
- `sourceResolution`: resolución base usada para convertir entre `view` y `source`

Si usas `image` o `stream`, debes proporcionar `sourceResolution`.  
Si usas `camera`, el paquete la obtiene automáticamente.

## Fuente de datos

### Imagen

```dart
final controller = BBoxEditorController();

BBoxEditor(
  image: NetworkImage(imageUrl),
  sourceResolution: const Size(1920, 1080),
  controller: controller,
  onCommitBox: (event) {
    // BoxCreated, BoxUpdated, BoxDeleted, BoxSelected
  },
);
```

### Stream MJPEG

`stream` no significa "cámara externa" en sí misma. Significa que la fuente llega como un stream MJPEG remoto, por ejemplo desde una cámara IP, un backend o un dispositivo en red.

```dart
final controller = BBoxEditorController();

BBoxEditor(
  stream: 'http://192.168.1.20:8080/video',
  sourceResolution: const Size(1280, 720),
  controller: controller,
  onSourceReady: () {
    debugPrint('Stream listo');
  },
  onSourceError: () {
    debugPrint('No se pudo abrir la fuente');
  },
);
```

### Cámara del dispositivo

#### Video en vivo

```dart
final controller = BBoxEditorController();

BBoxEditor(
  camera: const BBoxCameraConfig(
    mode: BBoxCameraMode.livePreview,
    resolutionPreset: BBoxCameraResolutionPreset.veryHigh,
  ),
  controller: controller,
);
```

### Presets de resolucion

`resolutionPreset` no fija una resolucion exacta en todos los dispositivos.  
Es una preferencia, y la plataforma selecciona la opcion mas cercana disponible.

| Preset | Resolucion aproximada |
| --- | --- |
| `low` | `320x240` |
| `medium` | `720x480` |
| `high` | `1280x720` |
| `veryHigh` | `1920x1080` |
| `ultraHigh` | `3840x2160` |
| `max` | maxima disponible del dispositivo |

La resolucion real obtenida puede variar segun:

- dispositivo
- sistema operativo
- implementacion del plugin de camara

Para saber cual fue la resolucion real usada por la fuente:

```dart
onSourceReady: () {
  debugPrint('Source resolution: ${controller.sourceResolution}');
}
```

#### Captura congelada

```dart
final controller = BBoxEditorController();

BBoxEditor(
  camera: const BBoxCameraConfig(
    mode: BBoxCameraMode.captureStill,
    resolutionPreset: BBoxCameraResolutionPreset.ultraHigh,
  ),
  controller: controller,
);
```

En `captureStill`, el flujo recomendado es externo al widget:

```dart
FilledButton(
  onPressed: controller.cameraCanCapture
      ? controller.captureCameraImage
      : null,
  child: const Text('Capture'),
);

OutlinedButton(
  onPressed: controller.cameraCanResumePreview
      ? controller.resumeCameraPreview
      : null,
  child: const Text('Resume Camera'),
);
```

## Estado del controlador

`BBoxEditorController` ya expone el estado útil para integrar tu UI. Los
flags de cámara son getters simples y notifican cambios a través del propio
controller:

- `boxes`
- `selectedBox`
- `selectedBoxListenable`
- `creationEnabled`
- `maxBoxCount`
- `canCreateBoxes`
- `canCreateBoxesListenable`
- `cameraAttached`
- `cameraPreviewActive`
- `cameraCaptureFrozen`
- `cameraCanCapture`
- `cameraCanResumePreview`

Ejemplo:

```dart
AnimatedBuilder(
  animation: Listenable.merge([
    controller,
    controller.boxes,
    controller.selectedBoxListenable,
  ]),
  builder: (context, _) {
    return Column(
      children: [
        Text('Boxes: ${controller.boxes.value.length}'),
        Text('Selected: ${controller.selectedBox?.id ?? '-'}'),
      ],
    );
  },
);
```

## Precarga de boxes

Si necesitas cargar boxes iniciales después de que la fuente esté lista:

```dart
BBoxEditor(
  image: MemoryImage(bytes),
  sourceResolution: const Size(1920, 1080),
  controller: controller,
  onSourceReadyFutureBoxes: (mapper) async {
    return [
      BBoxEntity(
        id: 1,
        center: const Offset(300, 200),
        w: 180,
        h: 120,
      )..setFrameCoords(mapper),
    ];
  },
);
```

## Tags visibles

Cada `BBoxEntity` puede mostrar su `tag` como un pill encima del bbox:

```dart
final box = BBoxEntity(
  center: const Offset(300, 200),
  w: 180,
  h: 120,
  tag: 'person',
  showTag: true,
);
```

Si `showTag` es `false`, el pill no se renderiza aunque exista `tag`.

## Modos de edición

- `BBoxTool.auto`: decide entre edición y zoom según plataforma y gesto
- `BBoxTool.bboxs`: solo edición de bounding boxes
- `BBoxTool.zoom`: solo zoom/pan

```dart
controller.setTool(BBoxTool.auto);
controller.setCreationEnabled(true);
controller.setMaxBoxCount(5);
```

## Interacción del overlay

Puedes cambiar el modo global de interacción del overlay:

```dart
BBoxEditor(
  image: MemoryImage(bytes),
  sourceResolution: const Size(1920, 1080),
  controller: controller,
  controlsConfig: const BBoxEditorControlsConfig(
    interactionMode: BBoxInteractionMode.selectBeforeEdit,
  ),
);
```

- `BBoxInteractionMode.directEdit`: al arrastrar un bbox lo editas directamente
- `BBoxInteractionMode.selectBeforeEdit`: primero seleccionas con tap y luego arrastras; si haces drag sobre un bbox no seleccionado, puedes crear otro encima

## Eventos

`onCommitBox` emite:

- `BoxCreated`
- `BoxUpdated`
- `BoxDeleted`
- `BoxSelected`
- `BoxesCleared`

## Notas

- En web, la cámara requiere `localhost` o `https`
- En apps consumidoras, los permisos de cámara deben configurarse en la plataforma
- Para `image` y `stream`, si `sourceResolution` es incorrecta, las coordenadas exportadas también lo serán
