import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:typed_data';

// Package Export
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class WebLaporanKaryawanPage extends StatefulWidget {
  const WebLaporanKaryawanPage({super.key});

  @override
  State<WebLaporanKaryawanPage> createState() => _WebLaporanKaryawanPageState();
}

class _WebLaporanKaryawanPageState extends State<WebLaporanKaryawanPage> {
  List<dynamic> _karyawanList = [];
  List<dynamic> _filteredList = [];
  bool _isLoading = true;

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _horizontalScrollCtrl = ScrollController();

  String _selectedStatus = 'Semua';
  final List<String> _statusOptions = ['Semua', 'Tetap', 'Kontrak', 'Magang'];

  @override
  void initState() {
    super.initState();
    _fetchKaryawan();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    super.dispose();
  }

  // --- FORMATTER TANGGAL (YYYY-MM-DD / DD-MM-YYYY ke DD-MM-YYYY) ---
  String _formatTanggal(String? tgl) {
    if (tgl == null || tgl.trim().isEmpty || tgl == '-' || tgl == 'null') {
      return '-';
    }
    try {
      if (tgl.contains('-')) {
        var parts = tgl.split('-');
        if (parts.length == 3) {
          if (parts[0].length == 2 && parts[2].length == 4) {
            return tgl;
          }
          if (parts[0].length == 4) {
            return '${parts[2]}-${parts[1]}-${parts[0]}';
          }
        }
      }
      DateTime dt = DateTime.parse(tgl.contains('T') ? tgl.split('T')[0] : tgl);
      return DateFormat('dd-MM-yyyy').format(dt);
    } catch (e) {
      return tgl;
    }
  }

  // --- PARSER DATA ANAK YANG LEBIH TANGGUH ---
  List<Map<String, String>> _parseChildrenData(dynamic rawChildren) {
    List<Map<String, String>> parsedList = [];
    if (rawChildren == null ||
        rawChildren.toString() == 'null' ||
        rawChildren.toString().isEmpty) {
      return parsedList;
    }

    try {
      dynamic decodedData = rawChildren;

      if (rawChildren is String) {
        try {
          decodedData = jsonDecode(rawChildren);
        } catch (_) {
          parsedList.add({'name': rawChildren, 'birth_date': '-'});
          return parsedList;
        }
      }

      if (decodedData is List) {
        for (var item in decodedData) {
          if (item is Map) {
            String name = item['name'] ??
                item['NAME'] ??
                item['nama'] ??
                item['info'] ??
                '-';
            String rawDate = item['birth_date'] ??
                item['BIRTH_DATE'] ??
                item['tanggal_lahir'] ??
                item['birthDate'] ??
                '-';
            String bDate = _formatTanggal(rawDate.toString());
            parsedList.add({'name': name.toString(), 'birth_date': bDate});
          } else if (item != null) {
            parsedList.add({'name': item.toString(), 'birth_date': '-'});
          }
        }
      } else if (decodedData is Map) {
        String name = decodedData['name'] ??
            decodedData['NAME'] ??
            decodedData['nama'] ??
            decodedData['info'] ??
            '-';
        String rawDate = decodedData['birth_date'] ??
            decodedData['BIRTH_DATE'] ??
            decodedData['tanggal_lahir'] ??
            decodedData['birthDate'] ??
            '-';
        String bDate = _formatTanggal(rawDate.toString());
        parsedList.add({'name': name.toString(), 'birth_date': bDate});
      }
    } catch (e) {
      parsedList.add({'name': rawChildren.toString(), 'birth_date': '-'});
    }

    return parsedList;
  }

  Future<void> _fetchKaryawan() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('employees')
          .select()
          .order('full_name', ascending: true);

      setState(() {
        _karyawanList = data;
        _filteredList = data;
      });
      _applyFilter();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal mengambil data: $e',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    setState(() {
      final query = _searchCtrl.text.toLowerCase();

      _filteredList = _karyawanList.where((item) {
        final name = (item['full_name'] ?? '').toString().toLowerCase();
        final nik = (item['nik'] ?? '').toString().toLowerCase();
        final matchSearch = name.contains(query) || nik.contains(query);

        final statusDB =
            (item['employee_status'] ?? '').toString().toLowerCase();
        final matchStatus = _selectedStatus == 'Semua' ||
            statusDB == _selectedStatus.toLowerCase();

        return matchSearch && matchStatus;
      }).toList();
    });
  }

  // --- POPUP PREVIEW BIODATA FULL ---
  void _showBiodataDialog(Map<String, dynamic> karyawan) {
    final childrenList = _parseChildrenData(
        karyawan['children_data'] ?? karyawan['childern_data']);

    String emergencyText = '-';
    final eName = karyawan['emergency_name'] ?? '';
    final ePhone = karyawan['emergency_phone'] ?? '';
    if (eName.toString().isNotEmpty || ePhone.toString().isNotEmpty) {
      emergencyText = '$eName ($ePhone)';
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 650),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Preview Biodata Karyawan',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 10),
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.blueGrey[50],
                    backgroundImage: (karyawan['photo_url'] != null &&
                            karyawan['photo_url'].toString().isNotEmpty)
                        ? NetworkImage(karyawan['photo_url'])
                        : null,
                    child: (karyawan['photo_url'] == null ||
                            karyawan['photo_url'].toString().isEmpty)
                        ? const Icon(
                            Icons.person,
                            size: 36,
                            color: Colors.blueGrey,
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    karyawan['full_name'] ?? 'Nama Tidak Tersedia',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${karyawan['jabatan_name'] ?? '-'} | Status: ${(karyawan['employee_status'] ?? '-').toString().toUpperCase()}',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.grey[700],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _buildBiodataRow('NIK', karyawan['nik']),
                            _buildBiodataRow('No. KTP', karyawan['ktp_number']),
                            _buildBiodataRow(
                                'No. NPWP', karyawan['npwp_number']),
                            _buildBiodataRow(
                              'Tempat, Tgl Lahir',
                              '${karyawan['birth_place'] ?? '-'}, ${_formatTanggal(karyawan['birth_date'])}',
                            ),
                            _buildBiodataRow(
                                'Jenis Kelamin', karyawan['gender']),
                            _buildBiodataRow('Agama', karyawan['religion']),
                            _buildBiodataRow(
                                'Pendidikan', karyawan['education']),
                            _buildBiodataRow('Tanggal Join',
                                _formatTanggal(karyawan['join_date'])),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            _buildBiodataRow('No. Telepon', karyawan['phone']),
                            _buildBiodataRow(
                                'Alamat KTP', karyawan['address_ktp']),
                            _buildBiodataRow(
                                'Alamat Domisili', karyawan['address_now']),
                            _buildBiodataRow(
                                'Status Menikah', karyawan['marital_status']),
                            _buildBiodataRow(
                                'Nama Pasangan', karyawan['spouse_name']),
                            _buildBiodataRow(
                                'Data Anak',
                                childrenList.isEmpty
                                    ? '-'
                                    : childrenList
                                        .asMap()
                                        .entries
                                        .map((e) =>
                                            'Anak ke-${e.key + 1}: ${e.value['name']} (${e.value['birth_date']})')
                                        .join('\n')),
                            _buildBiodataRow('Kontak Darurat', emergencyText),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        _exportSinglePdf(karyawan);
                      },
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: Text(
                        'Download PDF Biodata Ini',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBiodataRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.black54,
              ),
            ),
          ),
          const Text(': '),
          Expanded(
            flex: 3,
            child: Text(
              value ?? '-',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 3. EXPORT KE EXCEL (Modern package:web version) ---
  void _exportToExcel() {
    if (_filteredList.isEmpty) return;

    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Laporan Karyawan'];
    excel.setDefaultSheet('Laporan Karyawan');

    List<String> headers = [
      'No',
      'NIK',
      'Nama Lengkap',
      'Jabatan',
      'Status Kerja',
      'Tanggal Masuk',
      'No. NPWP',
      'Jenis Kelamin',
      'Agama',
      'No. HP',
      'Alamat KTP',
      'Kontak Darurat'
    ];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    for (int i = 0; i < _filteredList.length; i++) {
      String emergencyText = '-';
      final eName = _filteredList[i]['emergency_name'] ?? '';
      final ePhone = _filteredList[i]['emergency_phone'] ?? '';
      if (eName.toString().isNotEmpty || ePhone.toString().isNotEmpty) {
        emergencyText = '$eName ($ePhone)';
      }

      final k = _filteredList[i];
      List<String> rowData = [
        '${i + 1}',
        k['nik']?.toString() ?? '-',
        k['full_name']?.toString() ?? '-',
        k['jabatan_name']?.toString() ?? '-',
        k['employee_status']?.toString().toUpperCase() ?? '-',
        _formatTanggal(k['join_date']),
        k['npwp_number']?.toString() ?? '-',
        k['gender']?.toString() ?? '-',
        k['religion']?.toString() ?? '-',
        k['phone']?.toString() ?? '-',
        k['address_ktp']?.toString() ?? '-',
        emergencyText,
      ];
      sheetObject.appendRow(rowData.map((e) => TextCellValue(e)).toList());
    }

    final fileBytes = excel.save();
    if (fileBytes != null) {
      // Konversi List<int> menjadi Uint8List agar .toJS dikenali
      final uint8List = Uint8List.fromList(fileBytes);
      final blob = web.Blob(
        [uint8List.toJS].toJS,
        web.BlobPropertyBag(
            type:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
      );
      final url = web.URL.createObjectURL(blob);
      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..download =
            "Laporan_Data_Karyawan_${_selectedStatus.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.xlsx";

      web.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      web.URL.revokeObjectURL(url);
    }
  }

  // --- 4. EXPORT REKAP TABEL KE PDF (Modern package:web version) ---
  Future<void> _exportToPdf() async {
    if (_filteredList.isEmpty) return;

    final pdf = pw.Document();

    final headers = [
      'No',
      'NIK',
      'Nama Lengkap',
      'Jabatan',
      'Status',
      'Tgl Masuk',
      'No. HP'
    ];
    final data = List<List<String>>.generate(
      _filteredList.length,
      (index) {
        final k = _filteredList[index];
        return [
          '${index + 1}',
          k['nik']?.toString() ?? '-',
          k['full_name']?.toString() ?? '-',
          k['jabatan_name']?.toString() ?? '-',
          k['employee_status']?.toString().toUpperCase() ?? '-',
          _formatTanggal(k['join_date']),
          k['phone']?.toString() ?? '-',
        ];
      },
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                  'Laporan Rekapitulasi Data Karyawan ($_selectedStatus)',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
                'Tanggal Cetak: ${DateFormat('dd-MM-yyyy').format(DateTime.now())} | Total Data: ${_filteredList.length} Karyawan',
                style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 15),
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: data,
              border: pw.TableBorder.all(width: 0.5),
              headerStyle: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blue800),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(5),
            ),
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    // Konversi List<int> menjadi Uint8List
    final uint8List = Uint8List.fromList(bytes);
    final blob = web.Blob(
      [uint8List.toJS].toJS,
      web.BlobPropertyBag(type: 'application/pdf'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download =
          "Laporan_Rekap_Karyawan_${DateTime.now().millisecondsSinceEpoch}.pdf";

    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }

  // --- EXPORT PDF PROFESIONAL (BIODATA SATU KARYAWAN) ---
  Future<void> _exportSinglePdf(Map<String, dynamic> k) async {
    final pdf = pw.Document();

    pw.MemoryImage? netImage;
    if (k['photo_url'] != null && k['photo_url'].toString().isNotEmpty) {
      try {
        final uri = Uri.parse(k['photo_url']);
        final networkImageBytes = await NetworkAssetBundle(uri).load("");
        netImage = pw.MemoryImage(networkImageBytes.buffer.asUint8List());
      } catch (_) {
        netImage = null;
      }
    }

    final childrenList =
        _parseChildrenData(k['children_data'] ?? k['childern_data']);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('PT TETRA',
                          style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue900)),
                      pw.Text('FORMULIR BIODATA KARYAWAN',
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Text(
                      'Tanggal Cetak: ${DateFormat('dd-MM-yyyy').format(DateTime.now())}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey700)),
                ],
              ),
              pw.Divider(thickness: 1.5, color: PdfColors.blue900, height: 20),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: 70,
                    height: 85,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: netImage != null
                        ? pw.ClipRRect(
                            horizontalRadius: 4,
                            verticalRadius: 4,
                            child: pw.Image(netImage, fit: pw.BoxFit.cover),
                          )
                        : pw.Center(
                            child: pw.Text('FOTO',
                                style: const pw.TextStyle(
                                    fontSize: 8, color: PdfColors.grey))),
                  ),
                  pw.SizedBox(width: 15),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(k['full_name'] ?? '-',
                          style: pw.TextStyle(
                              fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text('Jabatan: ${k['jabatan_name'] ?? '-'}',
                          style: const pw.TextStyle(fontSize: 11)),
                      pw.Text(
                          'Status Kerja: ${(k['employee_status'] ?? '-').toUpperCase()}',
                          style: const pw.TextStyle(fontSize: 11)),
                      pw.Text('Divisi/Role: ${k['role'] ?? '-'}',
                          style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 15),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(5),
                color: PdfColors.grey200,
                child: pw.Text('I. INFORMASI PRIBADI',
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                children: [
                  pw.Expanded(
                      child: pw.Paragraph(
                          text: 'NIK: ${k['nik'] ?? '-'}',
                          style: const pw.TextStyle(fontSize: 10))),
                  pw.Expanded(
                      child: pw.Paragraph(
                          text: 'No. KTP: ${k['ktp_number'] ?? '-'}',
                          style: const pw.TextStyle(fontSize: 10))),
                ],
              ),
              pw.Row(
                children: [
                  pw.Expanded(
                      child: pw.Paragraph(
                          text: 'No. NPWP: ${k['npwp_number'] ?? '-'}',
                          style: const pw.TextStyle(fontSize: 10))),
                  pw.Expanded(
                      child: pw.Paragraph(
                          text: 'Jenis Kelamin: ${k['gender'] ?? '-'}',
                          style: const pw.TextStyle(fontSize: 10))),
                ],
              ),
              pw.Row(
                children: [
                  pw.Expanded(
                      child: pw.Paragraph(
                          text:
                              'Tempat, Tgl Lahir: ${k['birth_place'] ?? '-'}, ${_formatTanggal(k['birth_date'])}',
                          style: const pw.TextStyle(fontSize: 10))),
                  pw.Expanded(
                      child: pw.Paragraph(
                          text: 'Agama: ${k['religion'] ?? '-'}',
                          style: const pw.TextStyle(fontSize: 10))),
                ],
              ),
              pw.Row(
                children: [
                  pw.Expanded(
                      child: pw.Paragraph(
                          text: 'Pendidikan: ${k['education'] ?? '-'}',
                          style: const pw.TextStyle(fontSize: 10))),
                  pw.Expanded(
                      child: pw.Paragraph(
                          text: 'No. HP: ${k['phone'] ?? '-'}',
                          style: const pw.TextStyle(fontSize: 10))),
                ],
              ),
              pw.Paragraph(
                  text: 'Tanggal Join: ${_formatTanggal(k['join_date'])}',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Paragraph(
                  text: 'Alamat KTP: ${k['address_ktp'] ?? '-'}',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Paragraph(
                  text: 'Alamat Domisili: ${k['address_now'] ?? '-'}',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 10),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(5),
                color: PdfColors.grey200,
                child: pw.Text('II. DATA KELUARGA & KONTAK DARURAT',
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                children: [
                  pw.Expanded(
                      child: pw.Paragraph(
                          text: 'Status Nikah: ${k['marital_status'] ?? '-'}',
                          style: const pw.TextStyle(fontSize: 10))),
                  pw.Expanded(
                      child: pw.Paragraph(
                          text: 'Nama Pasangan: ${k['spouse_name'] ?? '-'}',
                          style: const pw.TextStyle(fontSize: 10))),
                ],
              ),
              pw.Paragraph(
                  text:
                      'Kontak Darurat: ${k['emergency_name'] ?? '-'} (${k['emergency_phone'] ?? '-'})',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 4),
              pw.Text('Data Anak:',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              if (childrenList.isEmpty)
                pw.Paragraph(
                    text: '- Tidak ada data anak -',
                    style: const pw.TextStyle(fontSize: 10))
              else
                ...childrenList.asMap().entries.map((entry) {
                  int idx = entry.key;
                  var child = entry.value;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 10, top: 2),
                    child: pw.Text(
                        '${idx + 1}. ${child['name']} (Tgl Lahir: ${child['birth_date']})',
                        style: const pw.TextStyle(fontSize: 10)),
                  );
                }),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    // Konversi List<int> menjadi Uint8List
    final uint8List = Uint8List.fromList(bytes);
    final blob = web.Blob(
      [uint8List.toJS].toJS,
      web.BlobPropertyBag(type: 'application/pdf'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = "Biodata_${k['full_name'] ?? 'Karyawan'}.pdf";

    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Laporan Data Karyawan',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _filteredList.isEmpty ? null : _exportToPdf,
                    icon: const Icon(Icons.picture_as_pdf,
                        color: Colors.red, size: 16),
                    label: Text('Export Rekap PDF',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _filteredList.isEmpty ? null : _exportToExcel,
                    icon: const Icon(Icons.table_view, size: 16),
                    label: Text('Export Rekap Excel',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 16),

          // --- FILTER SECTION ---
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey[300]!),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (value) => _applyFilter(),
                      style: GoogleFonts.plusJakartaSans(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Cari berdasarkan Nama / NIK...',
                        hintStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: Colors.grey),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<String>(
                      value: _selectedStatus,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Filter Status Kerja',
                        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      items: _statusOptions.map((status) {
                        return DropdownMenuItem(
                            value: status,
                            child: Text(status,
                                style:
                                    GoogleFonts.plusJakartaSans(fontSize: 12)));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedStatus = val);
                          _applyFilter();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // --- PREVIEW TABEL ---
          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey[300]!),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredList.isEmpty
                      ? Center(
                          child: Text('Data tidak ditemukan.',
                              style: GoogleFonts.plusJakartaSans(fontSize: 12)))
                      : Scrollbar(
                          controller: _horizontalScrollCtrl,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _horizontalScrollCtrl,
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: DataTable(
                                showCheckboxColumn: false,
                                headingRowColor:
                                    WidgetStateProperty.all(Colors.blue[50]),
                                dataRowMaxHeight: 52,
                                headingTextStyle: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[900],
                                ),
                                dataTextStyle:
                                    GoogleFonts.plusJakartaSans(fontSize: 12),
                                columns: const [
                                  DataColumn(label: Text('No')),
                                  DataColumn(label: Text('Foto')),
                                  DataColumn(label: Text('NIK')),
                                  DataColumn(label: Text('Nama Lengkap')),
                                  DataColumn(label: Text('Jabatan')),
                                  DataColumn(label: Text('Status Kerja')),
                                  DataColumn(label: Text('Tanggal Masuk')),
                                  DataColumn(label: Text('No. HP')),
                                ],
                                rows: List<DataRow>.generate(
                                  _filteredList.length,
                                  (index) {
                                    final k = _filteredList[index];
                                    final photoUrl = k['photo_url'];
                                    return DataRow(
                                      onSelectChanged: (selected) {
                                        _showBiodataDialog(k);
                                      },
                                      cells: [
                                        DataCell(Text('${index + 1}')),
                                        DataCell(
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor:
                                                Colors.blueGrey[50],
                                            backgroundImage:
                                                (photoUrl != null &&
                                                        photoUrl
                                                            .toString()
                                                            .isNotEmpty)
                                                    ? NetworkImage(photoUrl)
                                                    : null,
                                            child: (photoUrl == null ||
                                                    photoUrl.toString().isEmpty)
                                                ? const Icon(Icons.person,
                                                    size: 16,
                                                    color: Colors.blueGrey)
                                                : null,
                                          ),
                                        ),
                                        DataCell(Text(k['nik'] ?? '-')),
                                        DataCell(Text(k['full_name'] ?? '-')),
                                        DataCell(
                                            Text(k['jabatan_name'] ?? '-')),
                                        DataCell(Text(
                                            (k['employee_status'] ?? '-')
                                                .toString()
                                                .toUpperCase())),
                                        DataCell(Text(
                                            _formatTanggal(k['join_date']))),
                                        DataCell(Text(k['phone'] ?? '-')),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
