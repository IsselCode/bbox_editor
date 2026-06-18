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
  bool _creationEnabled = true;
  int _maxBoxes = 3;
  _DemoSource _source = _DemoSource.image;

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
          sourceResolution: const Size(1280, 720),
          controller: _controller,
          logs: false,
          onCommitBox: _pushEvent,
        );
      case _DemoSource.cameraLive:
        return BBoxEditor(
          camera: const BBoxCameraConfig(mode: BBoxCameraMode.livePreview),
          controller: _controller,
          logs: false,
          onCommitBox: _pushEvent,
        );
      case _DemoSource.cameraCapture:
        return BBoxEditor(
          camera: const BBoxCameraConfig(mode: BBoxCameraMode.captureStill),
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
