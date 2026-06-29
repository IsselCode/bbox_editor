import 'dart:ui' as ui;

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
    'tag': 'Etiqueta asociada a la entidad si fue asignada.',
    'color': 'Color actual de la entidad expresado en hexadecimal.',
    'viewSize':
        'Tamano actual del canvas visible del editor en coordenadas de vista.',
    'sourceResolution': 'Resolucion real de la imagen, stream o camara fuente.',
    'viewCenter': 'Centro del bounding box en coordenadas de vista.',
    'viewWidth': 'Ancho del bounding box en coordenadas de vista.',
    'viewHeight': 'Alto del bounding box en coordenadas de vista.',
    'viewAngle':
        'Rotacion actual del bounding box en radianes dentro de la vista.',
    'sourceAbsoluteX':
        'Posicion X absoluta de la esquina superior izquierda del bounding box en la imagen original.',
    'sourceAbsoluteY':
        'Posicion Y absoluta de la esquina superior izquierda del bounding box en la imagen original.',
    'sourceAbsoluteCenterX':
        'Centro X absoluto del bounding box en la imagen original.',
    'sourceAbsoluteCenterY':
        'Centro Y absoluto del bounding box en la imagen original.',
    'sourceWidth':
        'Ancho transformado al sistema de coordenadas del frame original.',
    'sourceHeight':
        'Alto transformado al sistema de coordenadas del frame original.',
    'sourceRelativeCenterX':
        'Centro X del crop en coordenadas locales del propio recorte; corresponde a width / 2.',
    'sourceRelativeCenterY':
        'Centro Y del crop en coordenadas locales del propio recorte; corresponde a height / 2.',
    'sourceAngle':
        'Angulo exportado en grados segun la orientacion de pantalla.',
    'sourceCropRect':
        'Rectangulo del recorte dentro de la imagen original: left, top, width y height.',
  };
  bool _creationEnabled = true;
  bool _showRotateControl = true;
  bool _showDeleteControl = true;
  int _maxBoxes = 3;
  _DemoSource _source = _DemoSource.image;
  MemoryImage? _demoImage;
  static const Size _demoImageSize = Size(1280, 720);

  BBoxEditorControlsConfig get _controlsConfig => BBoxEditorControlsConfig(
    showRotateControl: _showRotateControl,
    showDeleteControl: _showDeleteControl,
  );

  @override
  void initState() {
    super.initState();
    _controller.setCreationEnabled(_creationEnabled);
    _controller.setMaxBoxCount(_maxBoxes);
    _prepareDemoImage();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setTool(BBoxTool tool) {
    _controller.setTool(tool);
    _pushMessage('Tool -> $tool');
  }

  void _pushEvent(BBoxEvent event) {
    _pushMessage(event.toString());
  }

  void _pushMessage(String message) {
    setState(() {
      _events.insert(0, message);
      if (_events.length > 24) _events.removeLast();
    });
  }

  void _setShowRotateControl(bool value) {
    setState(() => _showRotateControl = value);
    _pushMessage('Config -> Rotate control ${value ? 'on' : 'off'}');
  }

  void _setShowDeleteControl(bool value) {
    setState(() => _showDeleteControl = value);
    _pushMessage('Config -> Delete control ${value ? 'on' : 'off'}');
  }

  Future<void> _prepareDemoImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & _demoImageSize;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          const [Color(0xFF0B1020), Color(0xFF1D4ED8), Color(0xFFF59E0B)],
          const [0, 0.58, 1],
        ),
    );
    canvas.drawCircle(
      const Offset(240, 220),
      130,
      Paint()..color = const Color(0x66FFFFFF),
    );
    canvas.drawCircle(
      const Offset(1000, 520),
      170,
      Paint()..color = const Color(0x3322C55E),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(440, 130, 410, 250),
        const Radius.circular(28),
      ),
      Paint()..color = const Color(0xCC111827),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(170, 450, 280, 150),
        const Radius.circular(24),
      ),
      Paint()..color = const Color(0xBFF8FAFC),
    );

    final linePaint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 3;
    for (var x = 0.0; x <= _demoImageSize.width; x += 80) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, _demoImageSize.height),
        linePaint,
      );
    }
    for (var y = 0.0; y <= _demoImageSize.height; y += 80) {
      canvas.drawLine(Offset(0, y), Offset(_demoImageSize.width, y), linePaint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      _demoImageSize.width.toInt(),
      _demoImageSize.height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (!mounted || bytes == null) return;
    setState(() {
      _demoImage = MemoryImage(bytes.buffer.asUint8List());
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

  Future<void> _showFrameDialog({
    required String title,
    required Future<BBoxFrameData?> future,
    String emptyMessage = 'No frame available.',
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
            child: FutureBuilder<BBoxFrameData?>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _buildDialogShell(
                    title: title,
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                final frame = snapshot.data;
                if (frame == null) {
                  return _buildDialogShell(
                    title: title,
                    child: Text(emptyMessage),
                  );
                }

                return _buildDialogShell(
                  title: title,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildMetaChip('Source', frame.sourceType.name),
                          _buildMetaChip(
                            'Resolution',
                            '${frame.sourceResolution.width.toInt()}x${frame.sourceResolution.height.toInt()}',
                          ),
                          _buildMetaChip('Mime', frame.mimeType),
                          _buildMetaChip('Bytes', '${frame.bytes.length}'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: InteractiveViewer(
                              child: Image.memory(
                                frame.bytes,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      'No se pudo renderizar la imagen.\n$error',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCropsDialog({
    required String title,
    required Future<List<BBoxCropData>> future,
    String emptyMessage = 'No crops available.',
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
            child: FutureBuilder<List<BBoxCropData>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _buildDialogShell(
                    title: title,
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                final crops = snapshot.data ?? const <BBoxCropData>[];
                if (crops.isEmpty) {
                  return _buildDialogShell(
                    title: title,
                    child: Text(emptyMessage),
                  );
                }

                return _buildDialogShell(
                  title: title,
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.15,
                        ),
                    itemCount: crops.length,
                    itemBuilder: (context, index) {
                      final crop = crops[index];
                      return _buildCropCard(crop);
                    },
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildDialogShell({required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildMetaChip(String label, String value) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text('$label: $value'),
      ),
    );
  }

  Widget _buildCropCard(BBoxCropData crop) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildMetaChip('Box', '${crop.box.id}'),
                _buildMetaChip(
                  'Size',
                  '${crop.cropSize.width.toInt()}x${crop.cropSize.height.toInt()}',
                ),
                _buildMetaChip('Mime', crop.mimeType),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Image.memory(
                    crop.bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No se pudo renderizar el recorte.\n$error',
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Rect: ${_fmtRect(crop.sourceRect)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _fmtRect(Rect rect) {
    return '(${_fmtDouble(rect.left)}, ${_fmtDouble(rect.top)}) '
        '${_fmtDouble(rect.width)}x${_fmtDouble(rect.height)}';
  }

  String _fmtSize(Size size) =>
      '${_fmtDouble(size.width)} x ${_fmtDouble(size.height)}';

  String _fmtNullableRect(Rect? rect) => rect == null ? '-' : _fmtRect(rect);

  Future<List<BBoxCropData>> _getSelectedCropList() async {
    final selected = _controller.selectedBox;
    if (selected == null) return const <BBoxCropData>[];
    final crop = await _controller.getBoxCrop(selected);
    if (crop == null) return const <BBoxCropData>[];
    return [crop];
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }

  Widget _buildMediaActionsPanel() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Media Actions',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              mainAxisExtent: 40,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildActionButton(
                  icon: Icons.movie_outlined,
                  label: 'Current Frame',
                  onPressed: () => _showFrameDialog(
                    title: 'Current Source Frame',
                    future: _controller.getCurrentSourceFrame(),
                  ),
                ),
                _buildActionButton(
                  icon: Icons.photo_outlined,
                  label: 'Captured Frame',
                  onPressed: () => _showFrameDialog(
                    title: 'Captured Frame',
                    future: _controller.getCapturedSourceFrame(),
                    emptyMessage: 'No captured frame available.',
                  ),
                ),
                _buildActionButton(
                  icon: Icons.crop_free,
                  label: 'Selected Crop',
                  onPressed: () => _showCropsDialog(
                    title: 'Selected Bounding Box Crop',
                    future: _getSelectedCropList(),
                    emptyMessage:
                        'Select a bounding box before requesting its crop.',
                  ),
                ),
                _buildActionButton(
                  icon: Icons.grid_view_outlined,
                  label: 'All Crops',
                  onPressed: () => _showCropsDialog(
                    title: 'All Bounding Box Crops',
                    future: _controller.getAllBoxCrops(),
                    emptyMessage:
                        'No crops available. Create or capture boxes first.',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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

    final viewValues = <MapEntry<String, String>>[
      MapEntry('id', '${selected.id}'),
      MapEntry('tag', _fmtNullableString(selected.tag)),
      MapEntry('color', BBoxEntity.colorToHex(selected.color)),
      MapEntry(
        'viewSize',
        _readLateString(() => _fmtSize(_controller.viewSize)),
      ),
      MapEntry(
        'sourceResolution',
        _readLateString(() => _fmtSize(_controller.sourceResolution)),
      ),
      MapEntry('viewCenter', _fmtOffset(selected.view.center)),
      MapEntry('viewWidth', _fmtDouble(selected.view.width)),
      MapEntry('viewHeight', _fmtDouble(selected.view.height)),
      MapEntry('viewAngle', _fmtDouble(selected.view.angleRadians)),
    ];

    final sourceValues = <MapEntry<String, String>>[
      MapEntry('id', '${selected.id}'),
      MapEntry('tag', _fmtNullableString(selected.tag)),
      MapEntry(
        'viewSize',
        _readLateString(() => _fmtSize(_controller.viewSize)),
      ),
      MapEntry(
        'sourceResolution',
        _readLateString(() => _fmtSize(_controller.sourceResolution)),
      ),
      MapEntry(
        'sourceAbsoluteX',
        _readLateString(() => _fmtDouble(selected.frame.absoluteX!)),
      ),
      MapEntry(
        'sourceAbsoluteY',
        _readLateString(() => _fmtDouble(selected.frame.absoluteY!)),
      ),
      MapEntry(
        'sourceAbsoluteCenterX',
        _readLateString(() => _fmtDouble(selected.frame.absoluteCenterX!)),
      ),
      MapEntry(
        'sourceAbsoluteCenterY',
        _readLateString(() => _fmtDouble(selected.frame.absoluteCenterY!)),
      ),
      MapEntry(
        'sourceWidth',
        _readLateString(() => _fmtDouble(selected.frame.width!)),
      ),
      MapEntry(
        'sourceHeight',
        _readLateString(() => _fmtDouble(selected.frame.height!)),
      ),
      MapEntry(
        'sourceRelativeCenterX',
        _readLateString(() => _fmtDouble(selected.frame.relativeCenterX!)),
      ),
      MapEntry(
        'sourceRelativeCenterY',
        _readLateString(() => _fmtDouble(selected.frame.relativeCenterY!)),
      ),
      MapEntry(
        'sourceAngle',
        _readLateString(() => _fmtDouble(selected.frame.angleDegrees!)),
      ),
      MapEntry(
        'sourceCropRect',
        _fmtNullableRect(selected.frame.sourceCropRect),
      ),
    ];

    Widget buildTabContent(List<MapEntry<String, String>> values) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: values
              .map((entry) => _buildInspectorRow(entry.key, entry.value))
              .toList(),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'View'),
              Tab(text: 'Source'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                buildTabContent(viewValues),
                buildTabContent(sourceValues),
              ],
            ),
          ),
        ],
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
        final demoImage = _demoImage;
        if (demoImage == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return BBoxEditor(
          image: demoImage,
          sourceResolution: _demoImageSize,
          controller: _controller,
          controlsConfig: _controlsConfig,
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
          controlsConfig: _controlsConfig,
          logs: false,
          onSourceReady: () => _pushMessage('Source -> Camera Live ready'),
          onCommitBox: _pushEvent,
        );
      case _DemoSource.cameraCapture:
        return BBoxEditor(
          camera: const BBoxCameraConfig(
            mode: BBoxCameraMode.captureStill,
            resolutionPreset: BBoxCameraResolutionPreset.ultraHigh,
          ),
          controller: _controller,
          controlsConfig: _controlsConfig,
          logs: false,
          onSourceReady: () => _pushMessage('Source -> Camera Capture ready'),
          onCapturedFrame: (frame) => _pushMessage(
            'Captured frame -> '
            '${frame.sourceResolution.width.toInt()}x'
            '${frame.sourceResolution.height.toInt()}',
          ),
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
                  _controller,
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
                          const Text('Rotate'),
                          Switch(
                            value: _showRotateControl,
                            onChanged: _setShowRotateControl,
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Delete'),
                          Switch(
                            value: _showDeleteControl,
                            onChanged: _setShowDeleteControl,
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
                              SizedBox(
                                height: 170,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFD1D5DB),
                                    ),
                                  ),
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: _events.length,
                                    itemBuilder: (context, index) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
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
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildMediaActionsPanel(),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: FilledButton.tonalIcon(
                                              onPressed:
                                                  _controller.cameraCanCapture
                                                  ? () {
                                                      _pushMessage(
                                                        'Action -> Capture',
                                                      );
                                                      _controller
                                                          .captureCameraImage();
                                                    }
                                                  : null,
                                              icon: const Icon(
                                                Icons.camera_alt_outlined,
                                              ),
                                              label: const Text('Capture'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed:
                                                  _controller
                                                      .cameraCanResumePreview
                                                  ? () {
                                                      _pushMessage(
                                                        'Action -> Resume Camera',
                                                      );
                                                      _controller
                                                          .resumeCameraPreview();
                                                    }
                                                  : null,
                                              icon: const Icon(
                                                Icons.videocam_outlined,
                                              ),
                                              label: const Text(
                                                'Resume Camera',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      const Text('Selected Entity'),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        height: 320,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFD1D5DB),
                                            ),
                                          ),
                                          child: AnimatedBuilder(
                                            animation: _controller
                                                .selectedBoxListenable,
                                            builder: (context, _) {
                                              return Padding(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                child:
                                                    _buildSelectedEntityInspector(),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
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
