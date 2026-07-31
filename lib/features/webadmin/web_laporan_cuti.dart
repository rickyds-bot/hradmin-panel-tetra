import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

// Pustaka Export Excel, PDF, & Web Download Helper
import 'package:excel/excel.dart' as excel_lib;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:convert';

class LaporanCutiPage extends StatefulWidget {
  const LaporanCutiPage({super.key});

  @override
  State<LaporanCutiPage> createState() => _LaporanCutiPageState();
}

class _LaporanCutiPageState extends State<LaporanCutiPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _employees = [];
  Map<String, dynamic> _selectedEmployee = {
    'id': 'all',
    'full_name': 'Semua Karyawan',
    'nik': 'ALL',
    'jabatan_name': '-',
  };

  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  final TextEditingController _employeeSearchCtrl = TextEditingController();
  List<dynamic> _laporanList = [];
  final ScrollController _horizontalScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('id_ID', null).then((_) {
      _fetchMasterData();
    });
  }

  @override
  void dispose() {
    _employeeSearchCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchMasterData() async {
    setState(() => _isLoading = true);
    try {
      final empData = await Supabase.instance.client
          .from('employees')
          .select()
          .order('full_name', ascending: true);

      setState(() {
        _employees = List<Map<String, dynamic>>.from(empData);
        _employeeSearchCtrl.text = _selectedEmployee['full_name'];
      });

      await _fetchLaporanCuti();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal memuat data master: $e',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchLaporanCuti() async {
    setState(() => _isLoading = true);
    try {
      final startStr = DateFormat('yyyy-MM-dd').format(_startDate);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate);

      var query = Supabase.instance.client.from('leave_requests').select('*');

      if (_selectedEmployee['id'] != 'all') {
        query = query.eq('employee_id', _selectedEmployee['id']);
      }

      // Logika overlapping agar semua cuti yang beririsan dengan filter tanggal tetap muncul
      final response = await query
          .lte('start_date', '$endStr 23:59:59')
          .gte('end_date', '$startStr 00:00:00')
          .order('start_date', ascending: true);

      Map<dynamic, Map<String, dynamic>> empMap = {
        for (var emp in _employees) emp['id']: emp,
      };

      List<dynamic> processedList = [];
      for (var item in (response as List<dynamic>)) {
        var newItem = Map<String, dynamic>.from(item);

        var empId = item['employee_id'];
        newItem['employees'] = empMap[empId] ??
            {'full_name': '-', 'nik': '-', 'jabatan_name': '-'};

        var approverId = item['approved_by'];
        newItem['approver'] = empMap[approverId] ?? {'full_name': '-'};

        processedList.add(newItem);
      }

      setState(() {
        _laporanList = processedList;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal memuat laporan cuti: $e',
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

  Future<void> _selectStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  // Pemisah tanggal diubah dari titik (.) menjadi strip (-)
  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd-MM-yyyy').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  // Export ke file .xlsx asli menggunakan Blob
  Future<void> _exportToExcel() async {
    if (_laporanList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data untuk diexport')),
      );
      return;
    }

    var excel = excel_lib.Excel.createExcel();
    String sheetName = 'Laporan Cuti';
    excel.rename(excel.getDefaultSheet() ?? 'Sheet1', sheetName);
    var sheet = excel[sheetName];

    // Header Tabel
    sheet.appendRow([
      excel_lib.TextCellValue('NO'),
      excel_lib.TextCellValue('JENIS CUTI'),
      excel_lib.TextCellValue('TANGGAL MULAI'),
      excel_lib.TextCellValue('TANGGAL SELESAI'),
      excel_lib.TextCellValue('NAMA KARYAWAN'),
      excel_lib.TextCellValue('ALASAN'),
      excel_lib.TextCellValue('STATUS'),
      excel_lib.TextCellValue('APPROVED BY'),
    ]);

    int no = 1;
    for (var item in _laporanList) {
      final emp = item['employees'] ?? {};
      final approver =
          item['approver'] is Map ? item['approver']['full_name'] ?? '-' : '-';

      sheet.appendRow([
        excel_lib.IntCellValue(no++),
        excel_lib.TextCellValue(item['leave_type'] ?? '-'),
        excel_lib.TextCellValue(_formatDate(item['start_date'])),
        excel_lib.TextCellValue(_formatDate(item['end_date'])),
        excel_lib.TextCellValue(emp['full_name'] ?? '-'),
        excel_lib.TextCellValue(item['reason'] ?? '-'),
        excel_lib.TextCellValue(item['status'] ?? 'Pending'),
        excel_lib.TextCellValue(approver),
      ]);
    }

    // Penamaan file dinamis berdasarkan Karyawan dan Tanggal
    String empName = _selectedEmployee['id'] == 'all'
        ? 'Semua_Karyawan'
        : (_selectedEmployee['full_name'] ?? 'Karyawan')
            .replaceAll(RegExp(r'[^\w\s]+'), '')
            .replaceAll(' ', '_');
    String dateStartStr = DateFormat('dd-MM-yyyy').format(_startDate);
    String dateEndStr = DateFormat('dd-MM-yyyy').format(_endDate);
    String fileName =
        'laporan_cuti_${empName}_${dateStartStr}_sd_${dateEndStr}.xlsx';

    final List<int>? rawBytes = excel.save();
    final Uint8List? fileBytes =
        rawBytes != null ? Uint8List.fromList(rawBytes) : null;

    if (fileBytes != null) {
      final blob = html.Blob([
        fileBytes,
      ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
    }
  }

  // Export PDF Stabil secara langsung via Blob
  Future<void> _exportToPDF() async {
    if (_laporanList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data untuk dicetak')),
      );
      return;
    }

    String subHeaderTitle = _selectedEmployee['id'] == 'all'
        ? 'Semua Karyawan'
        : 'Karyawan: ${_selectedEmployee['full_name']}';

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Laporan Cuti & Izin Karyawan',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        subHeaderTitle,
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Periode: ${DateFormat('dd MMM yyyy').format(_startDate)} s/d ${DateFormat('dd MMM yyyy').format(_endDate)}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: [
                'No',
                'Jenis Cuti',
                'Tanggal Mulai',
                'Tanggal Selesai',
                'Nama Karyawan',
                'Alasan',
                'Status',
                'Approved By',
              ],
              data: List<List<String>>.generate(_laporanList.length, (index) {
                final item = _laporanList[index];
                final emp = item['employees'] ?? {};
                final approver = item['approver'] is Map
                    ? item['approver']['full_name'] ?? '-'
                    : '-';

                return [
                  '${index + 1}',
                  item['leave_type'] ?? '-',
                  _formatDate(item['start_date']),
                  _formatDate(item['end_date']),
                  emp['full_name'] ?? '-',
                  item['reason'] ?? '-',
                  item['status'] ?? 'Pending',
                  approver,
                ];
              }),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blue800,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FixedColumnWidth(30),
                1: const pw.FixedColumnWidth(70),
                2: const pw.FixedColumnWidth(70),
                3: const pw.FixedColumnWidth(70),
                4: const pw.FlexColumnWidth(1.5),
                5: const pw.FlexColumnWidth(2),
                6: const pw.FixedColumnWidth(60),
                7: const pw.FlexColumnWidth(1.2),
              },
            ),
          ];
        },
      ),
    );

    // Penamaan file dinamis berdasarkan Karyawan dan Tanggal
    String empName = _selectedEmployee['id'] == 'all'
        ? 'Semua_Karyawan'
        : (_selectedEmployee['full_name'] ?? 'Karyawan')
            .replaceAll(RegExp(r'[^\w\s]+'), '')
            .replaceAll(' ', '_');
    String dateStartStr = DateFormat('dd-MM-yyyy').format(_startDate);
    String dateEndStr = DateFormat('dd-MM-yyyy').format(_endDate);
    String fileName =
        'laporan_cuti_${empName}_${dateStartStr}_sd_${dateEndStr}.pdf';

    final Uint8List bytes = await pdf.save();
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Laporan Cuti & Izin Karyawan',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _selectedEmployee['id'] == 'all'
                        ? 'Semua Karyawan'
                        : '${_selectedEmployee['full_name']}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _laporanList.isEmpty ? null : _exportToExcel,
                    icon: const Icon(Icons.table_view, size: 16),
                    label: Text(
                      'Export Excel',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _laporanList.isEmpty ? null : _exportToPDF,
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: Text(
                      'Export PDF',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey[300]!),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: Autocomplete<Map<String, dynamic>>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        List<Map<String, dynamic>> allOptions = [
                          {
                            'id': 'all',
                            'full_name': 'Semua Karyawan',
                            'nik': 'ALL',
                            'jabatan_name': '-',
                          },
                        ];
                        allOptions.addAll(_employees);
                        if (textEditingValue.text == '') return allOptions;
                        return allOptions.where((emp) {
                          final name =
                              (emp['full_name'] ?? '').toString().toLowerCase();
                          final nik =
                              (emp['nik'] ?? '').toString().toLowerCase();
                          final query = textEditingValue.text.toLowerCase();
                          return name.contains(query) || nik.contains(query);
                        });
                      },
                      displayStringForOption: (option) => option['id'] == 'all'
                          ? 'Semua Karyawan'
                          : '${option['full_name'] ?? ''} (${option['nik'] ?? '-'})',
                      onSelected: (selection) {
                        setState(() {
                          _selectedEmployee = selection;
                          _employeeSearchCtrl.text = selection['id'] == 'all'
                              ? 'Semua Karyawan'
                              : '${selection['full_name']} (${selection['nik']})';
                        });
                        _fetchLaporanCuti();
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                        if (controller.text.isEmpty) {
                          controller.text = _selectedEmployee['id'] == 'all'
                              ? 'Semua Karyawan'
                              : '${_selectedEmployee['full_name']} (${_selectedEmployee['nik']})';
                        }
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: GoogleFonts.plusJakartaSans(fontSize: 12),
                          decoration: InputDecoration(
                            labelText: 'Cari & Pilih Karyawan',
                            labelStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                            ),
                            isDense: true,
                            prefixIcon: const Icon(
                              Icons.person_search,
                              size: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: InkWell(
                      onTap: () => _selectStartDate(context),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Tanggal Mulai',
                          labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                          isDense: true,
                          prefixIcon: const Icon(
                            Icons.calendar_today,
                            size: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          DateFormat('dd-MM-yyyy').format(_startDate),
                          style: GoogleFonts.plusJakartaSans(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: InkWell(
                      onTap: () => _selectEndDate(context),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Tanggal Selesai',
                          labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                          isDense: true,
                          prefixIcon: const Icon(
                            Icons.calendar_today,
                            size: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          DateFormat('dd-MM-yyyy').format(_endDate),
                          style: GoogleFonts.plusJakartaSans(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _fetchLaporanCuti,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Tampilkan',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey[300]!),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _laporanList.isEmpty
                      ? Center(
                          child: Text(
                            'Tidak ada data laporan cuti.',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12),
                          ),
                        )
                      : Scrollbar(
                          controller: _horizontalScrollCtrl,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _horizontalScrollCtrl,
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth:
                                    MediaQuery.of(context).size.width - 80,
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    Colors.blue[50],
                                  ),
                                  headingTextStyle: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                  dataTextStyle: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                  ),
                                  columns: const [
                                    DataColumn(label: Text('No')),
                                    DataColumn(label: Text('Jenis Cuti')),
                                    DataColumn(label: Text('Tanggal Mulai')),
                                    DataColumn(label: Text('Tanggal Selesai')),
                                    DataColumn(label: Text('Nama Karyawan')),
                                    DataColumn(label: Text('Alasan')),
                                    DataColumn(label: Text('Status')),
                                    DataColumn(label: Text('Approved By')),
                                  ],
                                  rows: List<DataRow>.generate(
                                    _laporanList.length,
                                    (index) {
                                      final item = _laporanList[index];
                                      final emp = item['employees'] ?? {};
                                      final startDateStr = _formatDate(
                                        item['start_date'],
                                      );
                                      final endDateStr = _formatDate(
                                        item['end_date'],
                                      );
                                      final approverName = item['approver']
                                              is Map
                                          ? (item['approver']['full_name'] ??
                                              '-')
                                          : '-';

                                      final status = item['status']
                                              ?.toString()
                                              .toLowerCase() ??
                                          'pending';
                                      Color badgeColor = Colors.orange;
                                      if (status == 'approved' ||
                                          status == 'disetujui') {
                                        badgeColor = Colors.green;
                                      } else if (status == 'rejected' ||
                                          status == 'ditolak') {
                                        badgeColor = Colors.red;
                                      }

                                      return DataRow(
                                        cells: [
                                          DataCell(Text('${index + 1}')),
                                          DataCell(
                                              Text(item['leave_type'] ?? '-')),
                                          DataCell(Text(startDateStr)),
                                          DataCell(Text(endDateStr)),
                                          DataCell(
                                            Text(
                                              emp['full_name'] ?? '-',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataCell(Text(item['reason'] ?? '-')),
                                          DataCell(
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color:
                                                    badgeColor.withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  6,
                                                ),
                                              ),
                                              child: Text(
                                                item['status'] ?? 'Pending',
                                                style:
                                                    GoogleFonts.plusJakartaSans(
                                                  fontSize: 11,
                                                  color: badgeColor,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              approverName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
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
          ),
        ],
      ),
    );
  }
}
