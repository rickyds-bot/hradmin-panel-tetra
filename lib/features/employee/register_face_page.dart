import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'face_net_service.dart';

enum LivenessStep {
  lookStraight,
  blink,
  turnFirstSide,
  turnOppositeSide,
  extracting,
  success,
}

class RegisterFacePage extends StatefulWidget {
  final CameraDescription camera;

  const RegisterFacePage({
    super.key,
    required this.camera,
  });

  @override
  State<RegisterFacePage> createState() => _RegisterFacePageState();
}

class _RegisterFacePageState extends State<RegisterFacePage> {
  static const double _turnThreshold = 12.0;

  late final CameraController _controller;
  late final FaceDetector _faceDetector;

  bool _isDetecting = false;
  bool _isSaving = false;
  bool _hasBlinkedClosed = false;

  DateTime? _lastProcessedAt;
  double? _firstTurnDirection;

  LivenessStep _currentStep = LivenessStep.lookStraight;
  String _instructionText = 'Posisikan wajah Anda di dalam bingkai';

  @override
  void initState() {
    super.initState();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,

      // google_mlkit_commons 0.11.1 Android hanya mendukung NV21.
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

      await _startLiveFeed();
    } catch (e) {
      debugPrint('Gagal menginisialisasi kamera: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kamera tidak dapat digunakan: $e')),
      );

      Navigator.pop(context, false);
    }
  }

  Future<void> _startLiveFeed() async {
    if (!_controller.value.isInitialized ||
        _controller.value.isStreamingImages ||
        _isSaving) {
      return;
    }

    await _controller.startImageStream((CameraImage image) async {
      if (_isDetecting || _isSaving) return;

      final now = DateTime.now();
      if (_lastProcessedAt != null &&
          now.difference(_lastProcessedAt!) <
              const Duration(milliseconds: 350)) {
        return;
      }
      _lastProcessedAt = now;

      _isDetecting = true;

      try {
        await _processCameraImage(image);
      } finally {
        _isDetecting = false;
      }
    });
  }

  Future<void> _processCameraImage(CameraImage image) async {
    try {
      final inputImage = _convertCameraImageToInputImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        _updateInstruction('Wajah tidak terdeteksi');
        return;
      }

      if (faces.length > 1) {
        _updateInstruction('Pastikan hanya ada satu wajah di layar');
        return;
      }

      final face = faces.first;

      if (face.boundingBox.width < image.width * 0.25 ||
          face.boundingBox.height < image.height * 0.25) {
        _updateInstruction('Dekatkan wajah ke dalam bingkai');
        return;
      }

      await _checkLiveness(face, image);
    } catch (e, stackTrace) {
      debugPrint('Face detector error: $e');
      debugPrintStack(stackTrace: stackTrace);

      _updateInstruction(
        'Deteksi kamera gagal. Periksa format kamera.',
      );
    }
  }

  Future<void> _checkLiveness(Face face, CameraImage image) async {
    final eulerY = face.headEulerAngleY;
    final leftEye = face.leftEyeOpenProbability;
    final rightEye = face.rightEyeOpenProbability;

    switch (_currentStep) {
      case LivenessStep.lookStraight:
        if (eulerY != null && eulerY > -10 && eulerY < 10) {
          _setStep(
            LivenessStep.blink,
            'Bagus. Sekarang silakan berkedip',
          );
        } else {
          _updateInstruction('Mohon lihat lurus ke depan');
        }
        break;

      case LivenessStep.blink:
        if (leftEye == null || rightEye == null) {
          _updateInstruction('Pastikan wajah terlihat jelas dan cukup terang');
          return;
        }

        if (leftEye < 0.25 && rightEye < 0.25) {
          _hasBlinkedClosed = true;
          _updateInstruction('Bagus, sekarang buka mata kembali');
        } else if (_hasBlinkedClosed && leftEye > 0.75 && rightEye > 0.75) {
          // --- getar 1 (Kedip Berhasil) ---
          if (await Vibration.hasVibrator() ?? false) {
            Vibration.vibrate(
                duration: 200, amplitude: 128); // Getar tegas selama 0.2 detik
          }

          _setStep(
            LivenessStep.turnFirstSide,
            'Bagus. Sekarang toleh ke salah satu sisi',
          );
        } else {
          _updateInstruction('Silakan berkedip satu kali');
        }
        break;

      case LivenessStep.turnFirstSide:
      case LivenessStep.turnOppositeSide:
        await _checkTurnDirection(
          image: image,
          face: face,
          eulerY: eulerY,
        );
        break;

      case LivenessStep.extracting:
      case LivenessStep.success:
        break;
    }
  }

  Future<void> _checkTurnDirection({
    required CameraImage image,
    required Face face,
    required double? eulerY,
  }) async {
    if (eulerY == null) {
      _updateInstruction('Pastikan wajah terlihat jelas');
      return;
    }

    // Putaran pertama boleh ke sisi mana saja.
    if (_currentStep == LivenessStep.turnFirstSide) {
      if (eulerY.abs() >= _turnThreshold) {
        _firstTurnDirection = eulerY.sign;

        // --- Getar 2 (Toleh Sisi Pertama Berhasil) ---
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(
              duration: 200, amplitude: 128); // Getar tegas selama 0.2 detik
        }

        _setStep(
          LivenessStep.turnOppositeSide,
          'Bagus. Sekarang toleh ke sisi sebaliknya',
        );
      } else {
        _updateInstruction('Toleh ke salah satu sisi');
      }
      return;
    }

    // Putaran kedua wajib ke arah kebalikan dari putaran pertama.
    final direction = _firstTurnDirection;

    if (direction == null) {
      _resetLiveness('Arah wajah tidak terbaca. Silakan ulangi.');
      return;
    }

    final hasTurnedToOppositeSide = eulerY * direction <= -_turnThreshold;

    if (hasTurnedToOppositeSide) {
      // --- Getar 3 (Toleh Sisi Kedua Berhasil) ---
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(
            duration: 200, amplitude: 128); // Getar tegas selama 0.2 detik
      }
      await _extractAndSaveFaceEmbedding(image, face);
    } else {
      _updateInstruction('Sekarang toleh ke sisi sebaliknya');
    }
  }

  Future<void> _extractAndSaveFaceEmbedding(
    CameraImage image,
    Face face,
  ) async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _currentStep = LivenessStep.extracting;
      _instructionText = 'Memproses dan menyimpan data wajah...';
    });

    try {
      final embedding = await FaceNetService().getFaceEmbedding(
        image,
        face,
        rotationDegrees: widget.camera.sensorOrientation,
      );

      if (embedding.isEmpty || embedding.any((value) => !value.isFinite)) {
        throw Exception('Embedding wajah dari model tidak valid.');
      }

      if (_controller.value.isStreamingImages) {
        await _controller.stopImageStream();
      }

      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) {
        throw Exception('Sesi login tidak ditemukan. Silakan login kembali.');
      }

      await Supabase.instance.client
          .from('employees')
          .update({
            'face_embedding': jsonEncode(embedding),
            'is_face_registered': true,
          })
          .eq('email', user.email!)
          .select('id')
          .single();

      if (!mounted) return;

      setState(() {
        _currentStep = LivenessStep.success;
        _instructionText = 'Wajah berhasil didaftarkan!';
      });

      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e, stackTrace) {
      debugPrint('Gagal menyimpan embedding wajah: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      _resetLiveness('Pendaftaran gagal. Silakan coba lagi.');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mendaftarkan wajah: $e'),
          backgroundColor: Colors.red,
        ),
      );

      try {
        await _startLiveFeed();
      } catch (streamError) {
        debugPrint('Gagal memulai ulang stream kamera: $streamError');
      }
    }
  }

  void _setStep(LivenessStep step, String instruction) {
    if (!mounted) return;

    setState(() {
      _currentStep = step;
      _instructionText = instruction;
    });
  }

  void _resetLiveness(String instruction) {
    if (!mounted) return;

    setState(() {
      _isSaving = false;
      _hasBlinkedClosed = false;
      _firstTurnDirection = null;
      _currentStep = LivenessStep.lookStraight;
      _instructionText = instruction;
    });
  }

  void _updateInstruction(String instruction) {
    if (!mounted || _instructionText == instruction) return;

    setState(() {
      _instructionText = instruction;
    });
  }

  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    try {
      // NV21 Android dan BGRA iOS masing-masing memakai satu plane.
      if (image.planes.length != 1) {
        debugPrint(
          'Jumlah plane tidak sesuai: ${image.planes.length}. '
          'Frame seharusnya memakai satu plane.',
        );
        return null;
      }

      final rotation = InputImageRotationValue.fromRawValue(
        widget.camera.sensorOrientation,
      );

      if (rotation == null) {
        debugPrint(
          'Orientasi kamera tidak didukung: '
          '${widget.camera.sensorOrientation}',
        );
        return null;
      }

      final format = Platform.isAndroid
          ? InputImageFormat.nv21
          : InputImageFormat.bgra8888;

      final Uint8List bytes = image.planes.first.bytes;

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(
            image.width.toDouble(),
            image.height.toDouble(),
          ),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Gagal mengonversi frame kamera: $e');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
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
      body: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: CameraPreview(_controller),
            ),
          ),
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.7),
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(
                  color: Colors.transparent,
                  child: Align(
                    alignment: Alignment.center,
                    child: ClipPath(
                      clipper: OvalClipper(),
                      child: Container(
                        width: 260,
                        height: 380,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _instructionText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (_isSaving ||
              _currentStep == LivenessStep.extracting ||
              _currentStep == LivenessStep.success)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _currentStep == LivenessStep.success
                        ? const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 80,
                          )
                        : const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 4,
                          ),
                    const SizedBox(height: 20),
                    Text(
                      _instructionText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            bottom: 40,
            child: IconButton(
              icon: const Icon(
                Icons.cancel,
                color: Colors.red,
                size: 50,
              ),
              onPressed: _isSaving ? null : () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

class OvalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.addOval(Rect.fromLTWH(0, 0, size.width, size.height));
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
