// Código basado en el paquete 'mjpeg_stream' (MIT License).

class MjpegPreprocessor {
  List<int>? process(List<int> frame) {
    if (frame.isNotEmpty && frame.length > 100) {
      // Ensure frame starts with 0xFF 0xD8 (start of image) and ends with 0xFF 0xD9 (end of image)
      if (frame[0] == 0xFF && frame[1] == 0xD8 && frame[frame.length - 2] == 0xFF && frame[frame.length - 1] == 0xD9) {
        return frame; // Valid JPEG frame
      } else {
        print("Invalid JPEG frame detected: ${frame.length} bytes");
      }
    }
    return null; // Return null if invalid frame
  }
}
