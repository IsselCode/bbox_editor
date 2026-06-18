import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';

import 'mjpeg_stream_processor.dart';

// Código basado en el paquete 'mjpeg_stream' (MIT License).

class MJPEGStreamScreen extends StatefulWidget {
  final String streamUrl;
  final BoxFit fit;
  final double width;
  final double height;
  final Duration timeout;
  // final Decoration? decoration;
  final bool showLogs;
  final bool showWatermark;
  final String watermarkText;
  final Widget? watermarkWidget;
  final bool showLiveIcon;

  final bool blurSensitiveContent;

  final double? borderRadius;

  // Callbacks agregados
  final VoidCallback? onRetry;
  final VoidCallback? onError;
  final VoidCallback? onStartCamera;

  MJPEGStreamScreen({
    required this.streamUrl,
    this.fit = BoxFit.cover,
    this.width = double.infinity,
    this.height = 300.0,
    this.timeout = const Duration(seconds: 5),

    // this.decoration,
    this.borderRadius = 15,
    this.showLogs = true,
    this.showWatermark = false,
    this.watermarkText = "MOKZ Studio",
    this.watermarkWidget,
    required this.showLiveIcon,
    this.blurSensitiveContent = false,
    // Calbacks agregados
    this.onRetry,
    this.onError,
    this.onStartCamera,
  });

  @override
  _MJPEGStreamScreenState createState() => _MJPEGStreamScreenState();
}

class _MJPEGStreamScreenState extends State<MJPEGStreamScreen> {
  late final String stream;
  late final MjpegPreprocessor preprocessor;
  ValueNotifier<MemoryImage?> image = ValueNotifier<MemoryImage?>(null);
  ValueNotifier<List<dynamic>?> errorState = ValueNotifier<List<dynamic>?>(
    null,
  );
  ValueNotifier<bool> showLiveIcon = ValueNotifier<bool>(false);
  ValueNotifier<bool> showLodingIndicator = ValueNotifier<bool>(true);
  ValueNotifier<bool> blurSensitiveContent = ValueNotifier<bool>(
    false,
  ); // Add blur state
  StreamSubscription? _subscription;
  bool _didNotifyStart = false;

  @override
  void initState() {
    super.initState();
    stream = widget.streamUrl;
    preprocessor = MjpegPreprocessor();

    blurSensitiveContent.value = widget.blurSensitiveContent;
    _startStream();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    image.dispose();
    errorState.dispose();
    showLiveIcon.dispose();
    showLodingIndicator.dispose();
    blurSensitiveContent.dispose(); // Dispose blur notifier
    super.dispose();
  }

  Future<void> _startStream() async {
    try {
      _didNotifyStart = false;
      final request = Request("GET", Uri.parse(stream));
      final response = await Client().send(request).timeout(widget.timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (widget.showLogs) print("Stream started successfully.");
        showLiveIcon.value = true;
        showLodingIndicator.value = false;
        List<int> _carry = [];
        _subscription = response.stream.listen(
          (chunk) {
            if (_carry.isNotEmpty &&
                _carry.last == 0xFF &&
                chunk.first == 0xD9) {
              _carry.add(chunk.first);
              _sendImage(_carry);
              _carry = [];
            }

            for (var i = 0; i < chunk.length - 1; i++) {
              final d = chunk[i];
              final d1 = chunk[i + 1];

              if (d == 0xFF && d1 == 0xD8) {
                _carry = [d];
              } else if (d == 0xFF && d1 == 0xD9 && _carry.isNotEmpty) {
                _carry.addAll([d, d1]);
                _sendImage(_carry);
                _carry = [];
              } else if (_carry.isNotEmpty) {
                _carry.add(d);
                if (i == chunk.length - 2) {
                  _carry.add(d1);
                }
              }
            }
          },
          onError: (error, stack) {
            if (widget.showLogs) print("Stream error: $error");
            errorState.value = [error, stack];
            image.value = null;
            showLiveIcon.value = false;
            showLodingIndicator.value = false;
            // callback de error agregado
            widget.onError?.call();
          },
          cancelOnError: true,
        );
      } else {
        if (widget.showLogs)
          print('Stream returned error status: ${response.statusCode}');
        errorState.value = [
          HttpException('Stream returned ${response.statusCode} status'),
        ];
        image.value = null;
        showLiveIcon.value = false;
        showLodingIndicator.value = false;
        // callback de error agregado
        widget.onError?.call();
      }
    } catch (error, stack) {
      if (widget.showLogs) print("Error during HTTP request: $error");
      errorState.value = [error, stack];
      image.value = null;
      showLiveIcon.value = false;
      showLodingIndicator.value = false;
      // callback de error agregado
      widget.onError?.call();
    }
  }

  void _reloadStream() {
    errorState.value = null;
    image.value = null;
    showLiveIcon.value = true;
    showLodingIndicator.value = true;
    if (widget.showLogs) print("Reloading stream...");
    // Callback agregado
    widget.onRetry?.call();
    _startStream();
  }

  void _sendImage(List<int> chunks) {
    final List<int>? imageData = preprocessor.process(chunks);
    if (imageData != null) {
      // Check if the frame has valid JPEG data
      if (imageData.length > 10 &&
          imageData[0] == 0xFF &&
          imageData[1] == 0xD8 &&
          imageData.last == 0xD9) {
        image.value = MemoryImage(Uint8List.fromList(imageData));
        if (!_didNotifyStart) {
          _didNotifyStart = true;
          widget.onStartCamera?.call();
        }
        if (widget.showLogs) print("Image processed and updated.");
      } else {
        if (widget.showLogs) print("Invalid JPEG frame detected.");
      }
    }
  }

  // Toggle blur effect
  void _toggleBlur() {
    blurSensitiveContent.value = !blurSensitiveContent.value;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius!),
        color: Colors.black,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 8, spreadRadius: 2),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ValueListenableBuilder<MemoryImage?>(
            valueListenable: image,
            builder: (context, currentImage, child) {
              if (currentImage == null && errorState.value == null) {
                return Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                );
              }

              if (errorState.value != null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 40),
                      SizedBox(height: 10),
                      Text(
                        'Stream Error',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 15),
                      CupertinoButton(
                        onPressed: _reloadStream,
                        child: Text("Retry"),
                        color: CupertinoColors.activeBlue,
                        padding: EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 20,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ],
                  ),
                );
              }

              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(widget.borderRadius!),
                      child: Image(
                        isAntiAlias: true,
                        filterQuality: FilterQuality.high,
                        image: currentImage!,

                        width: widget.width,
                        height: widget.height,
                        fit: widget.fit,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: blurSensitiveContent,
                    builder: (context, blur, child) {
                      if (blur && widget.blurSensitiveContent) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(
                            widget.borderRadius!,
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                            child: Container(
                              width: widget.width,
                              height: widget.height,
                              child: CupertinoButton(
                                onPressed: _toggleBlur,
                                child: CircleAvatar(
                                  backgroundColor: Color.fromARGB(
                                    44,
                                    255,
                                    255,
                                    255,
                                  ),
                                  child: Icon(
                                    blurSensitiveContent.value
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.white,
                                  ),
                                ),
                                padding: EdgeInsets.all(10),
                                color: Colors.black.withOpacity(0.5),
                              ),
                              color: Colors.black.withOpacity(0.3),
                            ),
                          ),
                        );
                      }
                      return SizedBox();
                    },
                  ),
                ],
              );
            },
          ),
          ValueListenableBuilder<List<dynamic>?>(
            valueListenable: errorState,
            builder: (context, error, child) {
              if (error != null) {
                return Container(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 40),
                      SizedBox(height: 10),
                      Text(
                        'Stream Error',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 15),
                      CupertinoButton(
                        onPressed: _reloadStream,
                        child: Text("Retry"),
                        color: CupertinoColors.activeBlue,
                        padding: EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 20,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ],
                  ),
                );
              }
              return SizedBox.shrink();
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: showLiveIcon,
            builder: (context, showLive, child) {
              if (showLive) {
                return Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Color.fromARGB(255, 244, 67, 54),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    // child: Center(child: Icon(Icons.live_tv_rounded,color: Colors.white,size: 25,)),
                  ),
                );
              }
              return SizedBox();
            },
          ),
          if (widget.showWatermark)
            Positioned(
              bottom: 10,
              right: 10,
              child:
                  widget.watermarkWidget ??
                  Text(
                    widget.watermarkText,
                    style: TextStyle(
                      color: Color.fromARGB(99, 255, 255, 255),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
            ),
          // if (widget.blurSensitiveContent)
          //   Positioned(
          //     bottom: 15,
          //     left: 15,
          //     child: CupertinoButton(
          //       onPressed: _toggleBlur,
          //       child: Icon(
          //         blurSensitiveContent.value
          //             ? Icons.visibility_off
          //             : Icons.visibility,
          //         color: Colors.white,
          //       ),
          //       padding: EdgeInsets.all(10),
          //       color: Colors.black.withOpacity(0.5),
          //       borderRadius: BorderRadius.circular(30),
          //     ),
          //   ),
        ],
      ),
    );
  }
}
