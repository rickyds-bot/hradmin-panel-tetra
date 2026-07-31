import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'face_net_service.dart';

class KameraAbsenPage extends StatefulWidget {
  final CameraDescription camera;
  final List<double> registeredEmbedding;

  const KameraAbsenPage({
    super.key,
    required this.camera,
    required this.registeredEmbedding,
  });

  @override
  State<KameraAbsenPage> createState() => _KameraAbsenPageState();
}

class _KameraAbsenPageState extends State<KameraAbsenPage> {
  static const _deviceOrientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  late final CameraController _controller;
  late final FaceDetector _faceDetector;

  bool _isDetecting = false;
  bool _isVerifying = false;
  bool _isMatched = false;

  DateTime? _lastProcessedAt;

  String _statusText = 'Posisikan wajah Anda di dalam bingkai';
  Color _statusColor = Colors.blue;

  @override
  void initState() {
    super.initState();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification:
            false, // Dimatikan karena tidak perlu cek kedip mata
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      await _controller.initialize();

      if (!mounted) return;
      setState(() {});

      await _startLiveRecognition();
    } catch (e) {
      debugPrint('Gagal inisialisasi kamera: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kamera tidak dapat digunakan: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _startLiveRecognition() async {
    if (!_controller.value.isInitialized ||
        _controller.value.isStreamingImages ||
        _isMatched ||
        _isVerifying) {
      return;
    }

    await _controller.startImageStream((CameraImage image) async {
      if (_isDetecting || _isMatched || _isVerifying) return;

      final now = DateTime.now();
      if (_lastProcessedAt != null &&
          now.difference(_lastProcessedAt!) <
              const Duration(milliseconds: 350)) {
        return;
      }
      _lastProcessedAt = now;

      _isDetecting = true;
      try {
        await _processFrame(image);
      } finally {
        _isDetecting = false;
      }
    });
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      final frameInput = _convertCameraImageToInputImage(image);
      if (frameInput == null) return;

      final faces = await _faceDetector.processImage(frameInput.inputImage);

      if (faces.isEmpty) {
        _updateStatus('Mencari wajah...', Colors.blue);
        return;
      }

      if (faces.length > 1) {
        _updateStatus('Pastikan hanya satu wajah di kamera', Colors.orange);
        return;
      }

      final face = faces.first;

      if (min(face.boundingBox.width, face.boundingBox.height) < 100) {
        _updateStatus('Dekatkan wajah ke kamera', Colors.orange);
        return;
      }

      await _verifyFace(
        image: image,
        face: face,
        rotationDegrees: frameInput.rotationDegrees,
      );
    } catch (e) {
      debugPrint('Gagal memproses frame: $e');
      _updateStatus('Gagal memproses wajah. Coba lagi.', Colors.red);
    }
  }

  Future<void> _verifyFace({
    required CameraImage image,
    required Face face,
    required int rotationDegrees,
  }) async {
    if (_isVerifying || _isMatched) return;

    setState(() {
      _isVerifying = true;
      _statusText = 'Memverifikasi wajah...';
      _statusColor = Colors.amber;
    });

    try {
      final currentEmbedding = await FaceNetService().getFaceEmbedding(
        image,
        face,
        rotationDegrees: rotationDegrees,
      );

      final isMatch = FaceNetService().isFaceMatching(
        widget.registeredEmbedding,
        currentEmbedding,
      );

      if (!isMatch) {
        _resetState('Wajah tidak cocok. Silakan paskan posisi Anda.');
        return;
      }

      if (!mounted) return;

      setState(() {
        _isMatched = true;
        _statusText = 'Wajah cocok. Menyimpan bukti absensi...';
        _statusColor = Colors.green;
      });

      if (_controller.value.isStreamingImages) {
        await _controller.stopImageStream();
      }

      final imageFile = await _controller.takePicture();

      if (mounted) {
        Navigator.pop(context, imageFile.path);
      }
    } catch (e) {
      debugPrint('Gagal verifikasi wajah: $e');

      _resetState('Verifikasi gagal. Coba lagi.');

      try {
        await _startLiveRecognition();
      } catch (streamError) {
        debugPrint('Gagal memulai ulang stream kamera: $streamError');
      }
    } finally {
      if (mounted && !_isMatched) {
        setState(() => _isVerifying = false);
      }
    }
  }

  void _resetState(String message) {
    if (!mounted) return;

    setState(() {
      _statusText = message;
      _statusColor = Colors.red;
    });
  }

  void _updateStatus(String text, Color color) {
    if (!mounted || (_statusText == text && _statusColor == color)) return;

    setState(() {
      _statusText = text;
      _statusColor = color;
    });
  }

  _FrameInput? _convertCameraImageToInputImage(CameraImage image) {
    try {
      final rotationDegrees = _getRotationDegrees();
      if (rotationDegrees == null) return null;

      final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
      final format = InputImageFormatValue.fromRawValue(image.format.raw);

      if (rotation == null || format == null) {
        debugPrint(
          'Format/rotasi kamera tidak didukung. '
          'format=${image.format.raw}, rotation=$rotationDegrees',
        );
        return null;
      }

      final allBytes = WriteBuffer();
      for (final plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }

      return _FrameInput(
        inputImage: InputImage.fromBytes(
          bytes: allBytes.done().buffer.asUint8List(),
          metadata: InputImageMetadata(
            size: Size(
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            rotation: rotation,
            format: format,
            bytesPerRow: image.planes.first.bytesPerRow,
          ),
        ),
        rotationDegrees: rotationDegrees,
      );
    } catch (e) {
      debugPrint('Gagal membuat InputImage: $e');
      return null;
    }
  }

  int? _getRotationDegrees() {
    final sensorOrientation = widget.camera.sensorOrientation;

    if (Platform.isIOS) {
      return sensorOrientation;
    }

    final deviceOrientation =
        _deviceOrientations[_controller.value.deviceOrientation];

    if (deviceOrientation == null) return null;

    if (widget.camera.lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + deviceOrientation) % 360;
    }

    return (sensorOrientation - deviceOrientation + 360) % 360;
  }

  @override
  void dispose() {
    if (_controller.value.isInitialized &&
        _controller.value.isStreamingImages) {
      _controller.stopImageStream();
    }

    _controller.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CameraPreview(_controller),
                  Container(
                    width: 250,
                    height: 320,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _statusColor,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  if (_isMatched)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.green,
                            strokeWidth: 5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Container(
            height: 150,
            width: double.infinity,
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _statusColor),
                  ),
                  child: Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 40,
                  ),
                  onPressed: (_isMatched || _isVerifying)
                      ? null
                      : () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameInput {
  final InputImage inputImage;
  final int rotationDegrees;

  const _FrameInput({
    required this.inputImage,
    required this.rotationDegrees,
  });
}
