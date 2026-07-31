import 'dart:math';
import 'dart:ui' show Rect;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceNetService {
  FaceNetService._internal();

  static final FaceNetService _instance = FaceNetService._internal();

  factory FaceNetService() => _instance;

  static const int inputSize = 112;

  static const double threshold = 1.0;

  Interpreter? _interpreter;
  Future<void>? _loadingModel;

  bool get isModelLoaded => _interpreter != null;

  Future<void> loadModel() {
    if (_interpreter != null) return Future.value();

    return _loadingModel ??= _loadModel().whenComplete(() {
      _loadingModel = null;
    });
  }

  Future<void> _loadModel() async {
    try {
      final interpreter = await Interpreter.fromAsset(
        'assets/models/mobilefacenet.tflite',
        options: InterpreterOptions(),
      );

      final inputTensor = interpreter.getInputTensor(0);
      final outputTensor = interpreter.getOutputTensor(0);

      if (inputTensor.shape.length != 4 ||
          inputTensor.shape[0] != 1 ||
          inputTensor.shape[1] != inputSize ||
          inputTensor.shape[2] != inputSize ||
          inputTensor.shape[3] != 3) {
        interpreter.close();

        throw Exception(
          'Input model tidak sesuai. '
          'Model harus memakai [1, $inputSize, $inputSize, 3]. '
          'Input aktual: ${inputTensor.shape}',
        );
      }

      if (inputTensor.type != TensorType.float32 ||
          outputTensor.type != TensorType.float32) {
        interpreter.close();

        throw Exception(
          'Model harus memakai tensor float32. '
          'Input: ${inputTensor.type}, Output: ${outputTensor.type}',
        );
      }

      _interpreter = interpreter;

      debugPrint(
        'Model FaceNet berhasil dimuat. '
        'Input=${inputTensor.shape}, Output=${outputTensor.shape}',
      );
    } catch (e) {
      debugPrint('Gagal memuat model FaceNet: $e');
      rethrow;
    }
  }

  Future<List<double>> getFaceEmbedding(
    CameraImage cameraImage,
    Face face, {
    required int rotationDegrees,
    bool mirrorHorizontally = false,
  }) async {
    final interpreter = _interpreter;

    if (interpreter == null) {
      throw Exception(
        'Model wajah belum dimuat. Jalankan FaceNetService().loadModel().',
      );
    }

    final sourceImage = _convertCameraImageToRgb(cameraImage);

    // Harus sama dengan rotasi yang dipakai InputImage ML Kit.
    var imageForCrop = _rotateImage(sourceImage, rotationDegrees);

    if (mirrorHorizontally) {
      imageForCrop = img.flipHorizontal(imageForCrop);
    }

    final croppedFace = _cropFaceWithMargin(
      imageForCrop,
      face.boundingBox,
    );

    final resizedFace = img.copyResize(
      croppedFace,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    final input = _imageToFloat32Input(resizedFace);

    final outputShape = interpreter.getOutputTensor(0).shape;

    if (outputShape.length != 2 || outputShape[0] != 1) {
      throw Exception(
        'Bentuk output model tidak didukung: $outputShape.',
      );
    }

    final embeddingLength = outputShape[1];

    if (embeddingLength <= 0) {
      throw Exception('Output embedding model kosong.');
    }

    final output = List<List<double>>.generate(
      1,
      (_) => List<double>.filled(embeddingLength, 0),
    );

    interpreter.run(input, output);

    return _l2Normalize(output.first);
  }

  bool isFaceMatching(
    List<double> registeredEmbedding,
    List<double> currentEmbedding, {
    double maxDistance = threshold,
  }) {
    if (maxDistance <= 0) {
      throw ArgumentError.value(
        maxDistance,
        'maxDistance',
        'Harus lebih besar dari nol.',
      );
    }

    final registered = _l2Normalize(registeredEmbedding);
    final current = _l2Normalize(currentEmbedding);

    final distance = _euclideanDistance(registered, current);

    debugPrint('Jarak wajah: ${distance.toStringAsFixed(4)}');

    return distance < maxDistance;
  }

  double _euclideanDistance(List<double> first, List<double> second) {
    if (first.length != second.length) {
      throw Exception(
        'Dimensi embedding tidak sama: '
        '${first.length} dan ${second.length}.',
      );
    }

    var sum = 0.0;

    for (var i = 0; i < first.length; i++) {
      final difference = first[i] - second[i];
      sum += difference * difference;
    }

    return sqrt(sum);
  }

  List<double> _l2Normalize(List<double> embedding) {
    if (embedding.isEmpty) {
      throw Exception('Embedding wajah kosong.');
    }

    var squaredSum = 0.0;

    for (final value in embedding) {
      if (!value.isFinite) {
        throw Exception('Embedding berisi nilai tidak valid.');
      }

      squaredSum += value * value;
    }

    final norm = sqrt(squaredSum);

    if (norm <= 0 || !norm.isFinite) {
      throw Exception('Norm embedding tidak valid.');
    }

    return embedding.map((value) => value / norm).toList();
  }

  img.Image _cropFaceWithMargin(
    img.Image image,
    Rect faceBounds,
  ) {
    if (faceBounds.width <= 0 || faceBounds.height <= 0) {
      throw Exception('Bounding box wajah tidak valid.');
    }

    final faceSize = max(faceBounds.width, faceBounds.height);
    final desiredSize = (faceSize * 1.35).round();

    if (desiredSize < 20) {
      throw Exception('Wajah terlalu kecil untuk diverifikasi.');
    }

    final cropSize = min(
      desiredSize,
      min(image.width, image.height),
    );

    final centerX = faceBounds.left + (faceBounds.width / 2);
    final centerY = faceBounds.top + (faceBounds.height / 2);

    final left = (centerX - cropSize / 2)
        .round()
        .clamp(0, max(0, image.width - cropSize))
        .toInt();

    final top = (centerY - cropSize / 2)
        .round()
        .clamp(0, max(0, image.height - cropSize))
        .toInt();

    return img.copyCrop(
      image,
      x: left,
      y: top,
      width: cropSize,
      height: cropSize,
    );
  }

  List<List<List<List<double>>>> _imageToFloat32Input(img.Image image) {
    final input = List<List<List<List<double>>>>.generate(
      1,
      (_) => List<List<List<double>>>.generate(
        inputSize,
        (_) => List<List<double>>.generate(
          inputSize,
          (_) => List<double>.filled(3, 0),
        ),
      ),
    );

    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final pixel = image.getPixel(x, y);

        // Normalisasi RGB ke rentang [-1, 1].
        input[0][y][x][0] = (pixel.r - 127.5) / 127.5;
        input[0][y][x][1] = (pixel.g - 127.5) / 127.5;
        input[0][y][x][2] = (pixel.b - 127.5) / 127.5;
      }
    }

    return input;
  }

  img.Image _rotateImage(img.Image image, int rotationDegrees) {
    final rotation = rotationDegrees % 360;

    switch (rotation) {
      case 0:
        return image;
      case 90:
      case 180:
      case 270:
        return img.copyRotate(
          image,
          angle: rotation.toDouble(),
        );
      default:
        throw ArgumentError.value(
          rotationDegrees,
          'rotationDegrees',
          'Hanya mendukung 0, 90, 180, atau 270.',
        );
    }
  }

  img.Image _convertCameraImageToRgb(CameraImage image) {
    switch (image.format.group) {
      case ImageFormatGroup.nv21:
        return _convertNv21ToRgb(image);

      case ImageFormatGroup.yuv420:
        return _convertYuv420ToRgb(image);

      case ImageFormatGroup.bgra8888:
        return _convertBgra8888ToRgb(image);

      default:
        throw Exception(
          'Format kamera tidak didukung: ${image.format.group}.',
        );
    }
  }

  /// Android NV21: satu plane berisi Y diikuti pasangan VU.
  img.Image _convertNv21ToRgb(CameraImage image) {
    if (image.planes.length != 1) {
      throw Exception(
        'NV21 harus memiliki satu plane, ditemukan ${image.planes.length}.',
      );
    }

    final width = image.width;
    final height = image.height;
    final bytes = image.planes.first.bytes;
    final frameSize = width * height;
    final requiredLength = frameSize + (frameSize ~/ 2);

    if (bytes.length < requiredLength) {
      throw Exception('Data NV21 kamera tidak lengkap.');
    }

    final rgbImage = img.Image(width: width, height: height);

    for (var y = 0; y < height; y++) {
      final uvRow = (y >> 1) * width;

      for (var x = 0; x < width; x++) {
        final yValue = bytes[y * width + x];
        final uvIndex = frameSize + uvRow + (x & ~1);

        final vValue = bytes[uvIndex];
        final uValue = bytes[uvIndex + 1];

        final red = _clampColor(yValue + 1.402 * (vValue - 128));
        final green = _clampColor(
          yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128),
        );
        final blue = _clampColor(yValue + 1.772 * (uValue - 128));

        rgbImage.setPixelRgb(x, y, red, green, blue);
      }
    }

    return rgbImage;
  }

  /// Android YUV_420_888: tiga plane Y, U, dan V.
  img.Image _convertYuv420ToRgb(CameraImage image) {
    if (image.planes.length < 3) {
      throw Exception(
        'YUV420 harus memiliki tiga plane, ditemukan ${image.planes.length}.',
      );
    }

    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    final rgbImage = img.Image(width: width, height: height);

    for (var y = 0; y < height; y++) {
      final yRowOffset = y * yPlane.bytesPerRow;
      final uvRowOffset = (y >> 1) * uPlane.bytesPerRow;

      for (var x = 0; x < width; x++) {
        final yIndex = yRowOffset + x;
        final uvIndex = uvRowOffset + ((x >> 1) * uvPixelStride);

        if (yIndex >= yPlane.bytes.length ||
            uvIndex >= uPlane.bytes.length ||
            uvIndex >= vPlane.bytes.length) {
          throw Exception('Data YUV420 kamera tidak lengkap.');
        }

        final yValue = yPlane.bytes[yIndex];
        final uValue = uPlane.bytes[uvIndex];
        final vValue = vPlane.bytes[uvIndex];

        final red = _clampColor(yValue + 1.402 * (vValue - 128));
        final green = _clampColor(
          yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128),
        );
        final blue = _clampColor(yValue + 1.772 * (uValue - 128));

        rgbImage.setPixelRgb(x, y, red, green, blue);
      }
    }

    return rgbImage;
  }

  /// iOS BGRA8888: satu plane berisi B-G-R-A.
  img.Image _convertBgra8888ToRgb(CameraImage image) {
    if (image.planes.length != 1) {
      throw Exception(
        'BGRA8888 harus memiliki satu plane, ditemukan ${image.planes.length}.',
      );
    }

    final width = image.width;
    final height = image.height;
    final plane = image.planes.first;
    final bytes = plane.bytes;

    final rgbImage = img.Image(width: width, height: height);

    for (var y = 0; y < height; y++) {
      final rowOffset = y * plane.bytesPerRow;

      for (var x = 0; x < width; x++) {
        final index = rowOffset + (x * 4);

        if (index + 2 >= bytes.length) {
          throw Exception('Data BGRA kamera tidak lengkap.');
        }

        final blue = bytes[index];
        final green = bytes[index + 1];
        final red = bytes[index + 2];

        rgbImage.setPixelRgb(x, y, red, green, blue);
      }
    }

    return rgbImage;
  }

  int _clampColor(double value) {
    return value.round().clamp(0, 255).toInt();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
