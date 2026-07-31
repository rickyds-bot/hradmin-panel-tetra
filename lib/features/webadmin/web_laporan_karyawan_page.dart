import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';

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

  // --- FORMATTER TANGGAL ---
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

  // --- PARSER DATA ANAK ---
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

  // --- POPUP PREVIEW BIODATA FULL DENGAN RIWAYAT KONTRAK ---
  void _showBiodataDialog(Map<String, dynamic> karyawan) {
    showDialog(
      context: context,
      builder: (context) {
        return _DetailLaporanKaryawanDialog(karyawan: karyawan);
      },
    );
  }

  // --- EXPORT KE EXCEL ---
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

  // --- EXPORT REKAP TABEL KE PDF ---
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

// ============================================================================
// WIDGET DIALOG DETAIL / PREVIEW LAPORAN DENGAN RIWAYAT KONTRAK
// ============================================================================

class _DetailLaporanKaryawanDialog extends StatefulWidget {
  final Map<String, dynamic> karyawan;
  const _DetailLaporanKaryawanDialog({required this.karyawan});

  @override
  State<_DetailLaporanKaryawanDialog> createState() =>
      _DetailLaporanKaryawanDialogState();
}

class _DetailLaporanKaryawanDialogState
    extends State<_DetailLaporanKaryawanDialog> {
  bool _isLoadingContracts = true;
  List<dynamic> _contractHistory = [];

  @override
  void initState() {
    super.initState();
    _fetchContractHistory();
  }

  Future<void> _fetchContractHistory() async {
    try {
      final res = await Supabase.instance.client
          .from('employee_contracts')
          .select()
          .eq('employee_id', widget.karyawan['id'])
          .order('contract_start', ascending: false);

      setState(() {
        _contractHistory = res;
        _isLoadingContracts = false;
      });
    } catch (_) {
      setState(() => _isLoadingContracts = false);
    }
  }

  Future<void> _downloadFile(String? fileUrl) async {
    if (fileUrl != null && fileUrl.isNotEmpty) {
      final uri = Uri.parse(fileUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

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

  Future<void> _exportSinglePdf() async {
    final pdf = pw.Document();
    final k = widget.karyawan;

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
    String childrenStr = '-';
    if (widget.karyawan['children_data'] != null) {
      if (widget.karyawan['children_data'] is String) {
        childrenStr = widget.karyawan['children_data'];
      } else {
        childrenStr = jsonEncode(widget.karyawan['children_data']);
      }
    }

    final photoUrl = widget.karyawan['photo_url'] ?? widget.karyawan['photo'];

    String rawEmpStatus =
        widget.karyawan['employee_status']?.toString().toLowerCase() ?? 'tetap';
    String displayStatus = 'Tetap';
    if (rawEmpStatus == 'kontrak') {
      displayStatus = 'Kontrak';
    } else if (rawEmpStatus == 'magang') {
      displayStatus = 'Magang';
    }

    String emergencyText = '-';
    final eName = widget.karyawan['emergency_name'] ?? '';
    final ePhone = widget.karyawan['emergency_phone'] ?? '';
    if (eName.toString().isNotEmpty || ePhone.toString().isNotEmpty) {
      emergencyText = '$eName ($ePhone)';
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 650, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Preview Biodata Karyawan & Riwayat',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900]),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.blue[100],
                            backgroundImage: (photoUrl != null &&
                                    photoUrl.toString().isNotEmpty)
                                ? NetworkImage(photoUrl.toString())
                                : null,
                            child: (photoUrl == null ||
                                    photoUrl.toString().isEmpty)
                                ? const Icon(Icons.person,
                                    size: 40, color: Colors.blue)
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.karyawan['full_name'] ?? '-',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${widget.karyawan['jabatan_name'] ?? '-'} | Status: ${displayStatus.toUpperCase()}',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSectionTitle('Informasi Akun & Pekerjaan'),
                    _buildInfoRow('NIK', widget.karyawan['nik']),
                    _buildInfoRow('Email', widget.karyawan['email']),
                    _buildInfoRow('No. Telepon', widget.karyawan['phone']),
                    _buildInfoRow('Jabatan', widget.karyawan['jabatan_name']),
                    _buildInfoRow('Status Karyawan Saat Ini', displayStatus),
                    _buildInfoRow(
                        'Status Akun',
                        (widget.karyawan['is_active'] ?? true)
                            ? 'Aktif'
                            : 'Non-Aktif'),
                    if (displayStatus.toLowerCase() == 'kontrak' ||
                        displayStatus.toLowerCase() == 'magang') ...[
                      _buildInfoRow(
                          'No. Kontrak', widget.karyawan['contract_number']),
                      _buildInfoRow('Mulai Periode',
                          _formatTanggal(widget.karyawan['contract_start'])),
                      _buildInfoRow('Selesai Periode',
                          _formatTanggal(widget.karyawan['contract_end'])),
                    ],
                    if (displayStatus.toLowerCase() == 'kontrak' &&
                        widget.karyawan['contract_file'] != null &&
                        widget.karyawan['contract_file'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 160,
                              child: Text('Surat Kontrak',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w500)),
                            ),
                            const Text(': '),
                            ElevatedButton.icon(
                              onPressed: () => _downloadFile(
                                  widget.karyawan['contract_file']),
                              icon: const Icon(Icons.download, size: 14),
                              label: Text('Download Dokumen PDF',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    _buildSectionTitle('Informasi Pribadi & Identitas'),
                    _buildInfoRow('Jenis Kelamin', widget.karyawan['gender']),
                    _buildInfoRow('Agama', widget.karyawan['religion']),
                    _buildInfoRow('Tempat, Tanggal Lahir',
                        '${widget.karyawan['birth_place'] ?? '-'}, ${_formatTanggal(widget.karyawan['birth_date'])}'),
                    _buildInfoRow('Nomor KTP', widget.karyawan['ktp_number']),
                    _buildInfoRow('Nomor NPWP', widget.karyawan['npwp_number']),
                    _buildInfoRow('Pendidikan', widget.karyawan['education']),
                    _buildInfoRow('Tanggal Join',
                        _formatTanggal(widget.karyawan['join_date'])),
                    const SizedBox(height: 16),
                    _buildSectionTitle('Alamat & Keluarga (Termasuk Anak)'),
                    _buildInfoRow('Alamat KTP', widget.karyawan['address_ktp']),
                    _buildInfoRow(
                        'Alamat Domisili', widget.karyawan['address_now']),
                    _buildInfoRow(
                        'Status Pernikahan', widget.karyawan['marital_status']),
                    _buildInfoRow(
                        'Nama Pasangan', widget.karyawan['spouse_name']),
                    _buildInfoRow('Tgl Lahir Pasangan',
                        _formatTanggal(widget.karyawan['spouse_birth_date'])),
                    _buildInfoRow('Data Anak', childrenStr),
                    _buildInfoRow('Kontak Darurat', emergencyText),
                    const SizedBox(height: 16),
                    _buildSectionTitle('Riwayat Kontrak / Perubahan Status'),
                    _isLoadingContracts
                        ? const Center(child: CircularProgressIndicator())
                        : _contractHistory.isEmpty
                            ? Text(
                                displayStatus == 'Tetap'
                                    ? 'Karyawan langsung berstatus Tetap (Tidak ada riwayat kontrak sebelumnya).'
                                    : 'Belum ada riwayat kontrak.',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12, color: Colors.grey[600]),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _contractHistory.length,
                                itemBuilder: (context, index) {
                                  final c = _contractHistory[index];
                                  return Card(
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: ListTile(
                                      title: Text(
                                          'Periode: ${_formatTanggal(c['contract_start'])} s/d ${_formatTanggal(c['contract_end'])}',
                                          style: GoogleFonts.plusJakartaSans(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold)),
                                      trailing: c['contract_file'] != null &&
                                              c['contract_file']
                                                  .toString()
                                                  .isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.download,
                                                  color: Colors.teal),
                                              onPressed: () => _downloadFile(
                                                  c['contract_file']),
                                            )
                                          : Text('Tanpa Dokumen / Magang',
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                      fontSize: 10,
                                                      color: Colors.grey)),
                                    ),
                                  );
                                },
                              ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                  ),
                  onPressed: _exportSinglePdf,
                  icon: const Icon(Icons.picture_as_pdf, size: 16),
                  label: Text(
                    'Download PDF Biodata Ini',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Tutup',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
      child: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue[800]),
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500)),
          ),
          const Text(': '),
          Expanded(
            child: Text(
                value?.toString().isNotEmpty == true ? value.toString() : '-',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}
