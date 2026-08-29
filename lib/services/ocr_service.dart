import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// A service to handle Object Character Recognition (OCR) using Google ML Kit.
class OcrService {
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Processes an image from the given file path and returns the recognized text.
  Future<String> recognizeText(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);

      return recognizedText.text;
    } catch (e) {
      debugPrint('OCR Error: $e');
      return '';
    }
  }

  /// Closes the underlying ML Kit text recognizer resources.
  void dispose() {
    _textRecognizer.close();
  }
}
