import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class KameraAbsenPage extends StatefulWidget {
  final CameraDescription camera;
  const KameraAbsenPage({Key? key, required this.camera}) : super(key: key);

  @override
  _KameraAbsenPageState createState() => _KameraAbsenPageState();
}

class _KameraAbsenPageState extends State<KameraAbsenPage> {
  late CameraController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.medium);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized)
      return const Scaffold(backgroundColor: Colors.black);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // 1. AREA KAMERA (Menggunakan AspectRatio agar tidak lonjong)
          Expanded(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CameraPreview(_controller),
                  // Bingkai Wajah (Overlay)
                  // Ganti bagian Container lingkaran sebelumnya dengan ini:
                  Container(
                    width: 250,
                    height:
                        320, // Tinggi lebih besar agar muat wajah & sedikit bahu
                    decoration: BoxDecoration(
                      color: Colors.transparent, // Transparan di tengah
                      border: Border.all(
                        color: Colors.white,
                        width: 3,
                      ), // Garis bingkai
                      borderRadius: BorderRadius.circular(
                        15,
                      ), // Sudut tumpul agar tidak tajam
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. AREA TOMBOL (Hitam di bawah)
          Container(
            height: 120,
            color: Colors.black,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Tombol Batal
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 35),
                  onPressed: () => Navigator.pop(context),
                ),
                // Tombol Jepret
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.blue,
                    size: 30,
                  ),
                  onPressed: () async {
                    final image = await _controller.takePicture();
                    Navigator.pop(context, image.path);
                  },
                ),
                const SizedBox(width: 40), // Spasi penyeimbang
              ],
            ),
          ),
        ],
      ),
    );
  }
}
