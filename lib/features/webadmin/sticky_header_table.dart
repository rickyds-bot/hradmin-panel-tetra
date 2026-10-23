import 'package:flutter/material.dart';

/// Membungkus [DataTable] agar baris header-nya "freeze" (tidak ikut
/// bergeser) saat isi tabel di-scroll ke bawah.
///
/// Cara kerja: tabel yang sama ditampilkan dua kali. Lapisan bawah ikut
/// scroll vertikal seperti biasa, lapisan atas hanya menampilkan baris
/// header (di-clip setinggi header) dan tidak ikut scroll vertikal.
/// Karena isinya identik, lebar kolom selalu sinkron, dan scroll
/// horizontal tetap ikut bersama (karena widget ini ditaruh di dalam
/// SingleChildScrollView horizontal).
class StickyHeaderTable extends StatelessWidget {
  /// DataTable yang akan dibekukan header-nya.
  final DataTable table;

  /// Controller scroll vertikal (opsional).
  final ScrollController? controller;

  /// Tinggi baris header. Samakan dengan `headingRowHeight` pada DataTable
  /// (default DataTable = 56).
  final double headingHeight;

  const StickyHeaderTable({
    super.key,
    required this.table,
    this.controller,
    this.headingHeight = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Lapisan isi: scroll vertikal normal.
        SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.vertical,
          child: table,
        ),
        // Lapisan header: selalu menempel di atas.
        Positioned(
          top: 0,
          left: 0,
          child: Material(
            elevation: 1,
            color: Colors.grey[50],
            child: SizedBox(
              height: headingHeight,
              child: ClipRect(
                // Scroll vertikal dimatikan: selalu menampilkan baris
                // paling atas (header) dari tabel yang sama.
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  physics: const NeverScrollableScrollPhysics(),
                  child: table,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
