import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Halaman ambil foto sederhana untuk mode absen "Foto + GPS"
/// (tanpa face detection / liveness). Mengembalikan path file foto.
class KameraFotoPage extends StatefulWidget {
  final CameraDescription camera;
  const KameraFotoPage({super.key, required this.camera});

  @override
  State<KameraFotoPage> createState() => _KameraFotoPageState();
}

class _KameraFotoPageState extends State<KameraFotoPage> {
  CameraController? _controller;
  Future<void>? _initFuture;
  bool _isTaking = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _initFuture = _controller!.initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_isTaking || _controller == null) return;
    setState(() => _isTaking = true);
    try {
      await _initFuture;
      final XFile file = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.pop(context, file.path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTaking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengambil foto: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Ambil Foto Absen'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Kamera tidak bisa dibuka: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white)),
            );
          }
          return Stack(
            children: [
              Center(child: CameraPreview(_controller!)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: Center(
                  child: GestureDetector(
                    onTap: _capture,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isTaking ? Colors.grey : Colors.white,
                        border: Border.all(color: Colors.white54, width: 4),
                      ),
                      child: _isTaking
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : const Icon(Icons.camera_alt, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
