// Manual demo retained for local reference.
// Run the package from example/lib/main.dart when targeting Flutter web.

import 'dart:convert';

import 'package:bbox_editor/bbox_editor.dart';
import 'package:bbox_editor/exports.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const _TouchAutoModeDemoApp());
}

enum _DemoSource { image, cameraLive, cameraCapture }

class _TouchAutoModeDemoApp extends StatelessWidget {
  const _TouchAutoModeDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F52FF)),
        useMaterial3: true,
      ),
      home: const _TouchAutoModeDemoScreen(),
    );
  }
}

class _TouchAutoModeDemoScreen extends StatefulWidget {
  const _TouchAutoModeDemoScreen();

  @override
  State<_TouchAutoModeDemoScreen> createState() =>
      _TouchAutoModeDemoScreenState();
}

class _TouchAutoModeDemoScreenState extends State<_TouchAutoModeDemoScreen> {
  final BBoxEditorController _controller = BBoxEditorController();
  final List<String> _events = <String>[];
  static const Map<BBoxTool, String> _toolLabels = {
    BBoxTool.auto: 'Auto',
    BBoxTool.bboxs: 'BBox',
    BBoxTool.zoom: 'Zoom',
  };
  static const Map<_DemoSource, String> _sourceLabels = {
    _DemoSource.image: 'Image',
    _DemoSource.cameraLive: 'Camera Live',
    _DemoSource.cameraCapture: 'Camera Capture',
  };
  static const Map<String, String> _propertyDescriptions = {
    'id': 'Identificador unico de la entidad seleccionada.',
    'center': 'Centro del bounding box en coordenadas de vista del editor.',
    'w': 'Ancho del bounding box en coordenadas de vista.',
    'h': 'Alto del bounding box en coordenadas de vista.',
    'angle': 'Rotacion actual del bounding box en radianes dentro de la vista.',
    'tag': 'Etiqueta asociada a la entidad si fue asignada.',
    'centerF':
        'Centro del bounding box transformado a coordenadas del frame original.',
    'wF': 'Ancho transformado al sistema de coordenadas del frame original.',
    'hF': 'Alto transformado al sistema de coordenadas del frame original.',
    'angleDegScreen':
        'Angulo exportado en grados segun la orientacion de pantalla.',
    'color': 'Color actual de la entidad expresado en hexadecimal.',
  };
  bool _creationEnabled = true;
  int _maxBoxes = 3;
  _DemoSource _source = _DemoSource.cameraLive;

  static final MemoryImage _demoImage = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2e0AAAAASUVORK5CYII=',
    ),
  );

  @override
  void initState() {
    super.initState();
    _controller.setCreationEnabled(_creationEnabled);
    _controller.setMaxBoxCount(_maxBoxes);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setTool(BBoxTool tool) {
    _controller.setTool(tool);
    setState(() {
      _events.insert(0, 'Tool -> $tool');
      if (_events.length > 8) _events.removeLast();
    });
  }

  void _pushEvent(BBoxEvent event) {
    setState(() {
      _events.insert(0, event.toString());
      if (_events.length > 8) _events.removeLast();
    });
  }

  void _setCreationEnabled(bool enabled) {
    _controller.setCreationEnabled(enabled);
    setState(() => _creationEnabled = enabled);
  }

  void _changeMaxBoxes(int delta) {
    final next = (_maxBoxes + delta).clamp(0, 99);
    _controller.setMaxBoxCount(next);
    setState(() => _maxBoxes = next);
  }

  void _setSource(_DemoSource source) {
    if (_source == source) return;
    _controller.clearAll();
    setState(() => _source = source);
  }

  bool get _isCaptureSource => _source == _DemoSource.cameraCapture;

  String _fmtDouble(double value) => value.toStringAsFixed(2);

  String _fmtOffset(Offset value) =>
      '(${_fmtDouble(value.dx)}, ${_fmtDouble(value.dy)})';

  String _fmtNullableString(String? value) =>
      value == null || value.isEmpty ? '-' : value;

  String _readLateString(String Function() reader) {
    try {
      return reader();
    } catch (_) {
      return '-';
    }
  }

  void _showPropertyInfo(String label) {
    final description =
        _propertyDescriptions[label] ?? 'Sin descripcion disponible.';
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(label),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInspectorRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Tooltip(
                  message: 'Ver descripcion',
                  child: InkWell(
                    onTap: () => _showPropertyInfo(label),
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.info_outline, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedEntityInspector() {
    final selected = _controller.selectedBox;
    if (selected == null) {
      return const Center(child: Text('No selected entity'));
    }

    final values = <MapEntry<String, String>>[
      MapEntry('id', '${selected.id}'),
      MapEntry('center', _fmtOffset(selected.center)),
      MapEntry('w', _fmtDouble(selected.w)),
      MapEntry('h', _fmtDouble(selected.h)),
      MapEntry('angle', _fmtDouble(selected.angle)),
      MapEntry('tag', _fmtNullableString(selected.tag)),
      MapEntry('centerF', _readLateString(() => _fmtOffset(selected.centerF))),
      MapEntry('wF', _readLateString(() => _fmtDouble(selected.wF))),
      MapEntry('hF', _readLateString(() => _fmtDouble(selected.hF))),
      MapEntry(
        'angleDegScreen',
        _readLateString(() => _fmtDouble(selected.angleDegScreen)),
      ),
      MapEntry('color', BBoxEntity.colorToHex(selected.color)),
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: values
            .map((entry) => _buildInspectorRow(entry.key, entry.value))
            .toList(),
      ),
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T value,
    required Map<T, String> labels,
    required ValueChanged<T?> onChanged,
    double width = 170,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: labels.entries
            .map(
              (entry) => DropdownMenuItem<T>(
                value: entry.key,
                child: Text(entry.value),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildEditor() {
    switch (_source) {
      case _DemoSource.image:
        return BBoxEditor(
          image: _demoImage,
          sourceResolution: const Size(1920, 1080),
          controller: _controller,
          logs: false,
          onCommitBox: _pushEvent,
        );
      case _DemoSource.cameraLive:
        return BBoxEditor(
          camera: const BBoxCameraConfig(
            mode: BBoxCameraMode.livePreview,
            resolutionPreset: BBoxCameraResolutionPreset.ultraHigh,
          ),
          controller: _controller,
          logs: false,
          onCommitBox: _pushEvent,
        );
      case _DemoSource.cameraCapture:
        return BBoxEditor(
          camera: const BBoxCameraConfig(
            mode: BBoxCameraMode.captureStill,
            resolutionPreset: BBoxCameraResolutionPreset.ultraHigh,
          ),
          controller: _controller,
          logs: false,
          onCommitBox: _pushEvent,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BBox Touch Auto Mode')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([
                  _controller.bBoxTool,
                  _controller.boxes,
                ]),
                builder: (context, _) {
                  final tool = _controller.bBoxTool.value;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildDropdownField<BBoxTool>(
                        label: 'BBox Mode',
                        value: tool,
                        labels: _toolLabels,
                        onChanged: (value) {
                          if (value != null) _setTool(value);
                        },
                      ),
                      _buildDropdownField<_DemoSource>(
                        label: 'Camera Mode',
                        value: _source,
                        labels: _sourceLabels,
                        width: 190,
                        onChanged: (value) {
                          if (value != null) _setSource(value);
                        },
                      ),
                      FilledButton.tonal(
                        onPressed: _isCaptureSource
                            ? _controller.captureCameraImage
                            : null,
                        child: const Text('Capture'),
                      ),
                      OutlinedButton(
                        onPressed: _isCaptureSource
                            ? _controller.resumeCameraPreview
                            : null,
                        child: const Text('Resume Camera'),
                      ),
                      Text('Source: ${_sourceLabels[_source]}'),
                      Text('Current: ${_toolLabels[tool]}'),
                      Text('Boxes: ${_controller.boxes.value.length}'),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Create'),
                          Switch(
                            value: _creationEnabled,
                            onChanged: _setCreationEnabled,
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Limit'),
                          IconButton(
                            onPressed: () => _changeMaxBoxes(-1),
                            icon: const Icon(Icons.remove),
                            tooltip: 'Decrease limit',
                          ),
                          Text('$_maxBoxes'),
                          IconButton(
                            onPressed: () => _changeMaxBoxes(1),
                            icon: const Icon(Icons.add),
                            tooltip: 'Increase limit',
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF121417),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: _buildEditor(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Events'),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _events.length,
                                  itemBuilder: (context, index) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        _events[index],
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text('Selected Entity'),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 240,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFD1D5DB),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: _buildSelectedEntityInspector(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
