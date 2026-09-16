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

class LaporanLemburPage extends StatefulWidget {
  const LaporanLemburPage({super.key});

  @override
  State<LaporanLemburPage> createState() => _LaporanLemburPageState();
}

class _LaporanLemburPageState extends State<LaporanLemburPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _employees = [];
  Map<String, dynamic> _selectedEmployee = {
    'id': 'all',
    'full_name': 'Semua Karyawan',
    'nik': 'ALL',
    'jabatan_name': '-'
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

      await _fetchLaporanLembur();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Gagal memuat data master: $e',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              backgroundColor: Colors.red),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  DateTime? _parseLocalDateTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      if (dateStr.length == 8 &&
          !dateStr.contains('T') &&
          !dateStr.contains('-')) {
        final now = DateTime.now();
        final parts = dateStr.split(':');
        return DateTime(now.year, now.month, now.day, int.parse(parts[0]),
            int.parse(parts[1]), int.parse(parts[2]));
      }

      DateTime parsed = DateTime.parse(dateStr);

      if (dateStr.endsWith('Z') || dateStr.contains('+00:00')) {
        return parsed.toLocal();
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  String _formatTime(String? timestampStr) {
    if (timestampStr == null || timestampStr.isEmpty) return '-';
    try {
      if (!timestampStr.contains('T') &&
          !timestampStr.contains('-') &&
          timestampStr.contains(':')) {
        List<String> parts = timestampStr.split(':');
        if (parts.length >= 2) {
          return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
        }
      }

      if (timestampStr.contains('T')) {
        String timePart = timestampStr.split('T')[1];
        List<String> timeComponents = timePart.split(':');
        if (timeComponents.length >= 2) {
          return '${timeComponents[0].padLeft(2, '0')}:${timeComponents[1].padLeft(2, '0')}';
        }
      }

      DateTime dt = DateTime.parse(timestampStr);
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      return '${twoDigits(dt.hour)}:${twoDigits(dt.minute)}';
    } catch (_) {
      return '-';
    }
  }

  Future<void> _fetchLaporanLembur() async {
    setState(() => _isLoading = true);
    try {
      final startStr = DateFormat('yyyy-MM-dd').format(_startDate);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate);

      var query =
          Supabase.instance.client.from('overtime_requests').select('*');

      if (_selectedEmployee['id'] != 'all') {
        query = query.eq('employee_id', _selectedEmployee['id']);
      }

      final response = await query
          .gte('created_at', '$startStr 00:00:00')
          .lte('created_at', '$endStr 23:59:59')
          .order('created_at', ascending: true);

      Map<dynamic, Map<String, dynamic>> empMap = {
        for (var emp in _employees) emp['id']: emp
      };

      List<dynamic> processedList = [];
      for (var item in (response as List<dynamic>)) {
        var newItem = Map<String, dynamic>.from(item);

        var empId = item['employee_id'];
        newItem['employees'] = empMap[empId] ??
            {'full_name': '-', 'nik': '-', 'jabatan_name': '-'};

        var approverId = item['approved_by'];
        newItem['approver'] = empMap[approverId] ?? {'full_name': '-'};

        try {
          if (item['start_time'] != null && item['end_time'] != null) {
            DateTime? startDt = _parseLocalDateTime(item['start_time']);
            DateTime? endDt = _parseLocalDateTime(item['end_time']);
            if (startDt != null && endDt != null) {
              if (endDt.isBefore(startDt)) {
                endDt = endDt.add(const Duration(days: 1));
              }
              double calculatedHours =
                  endDt.difference(startDt).inMinutes / 60.0;
              newItem['duration_hours'] =
                  double.parse(calculatedHours.toStringAsFixed(1));
            }
          }
        } catch (_) {}

        processedList.add(newItem);
      }

      setState(() {
        _laporanList = processedList;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Gagal memuat laporan lembur: $e',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              backgroundColor: Colors.red),
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

  String _formatDate(String? timestampStr) {
    DateTime? dt = _parseLocalDateTime(timestampStr);
    if (dt == null) return '-';
    return DateFormat('dd-MM-yyyy').format(dt);
  }

  String _getDayName(String? timestampStr) {
    DateTime? dt = _parseLocalDateTime(timestampStr);
    if (dt == null) return '-';
    return DateFormat('EEEE', 'id_ID').format(dt);
  }

  Map<String, double> _calculateTotalHours() {
    double weekdayTotal = 0.0;
    double weekendTotal = 0.0;
    for (var item in _laporanList) {
      double hours =
          double.tryParse(item['duration_hours']?.toString() ?? '0') ?? 0.0;
      String dayName = _getDayName(item['start_time']).toLowerCase();
      if (dayName == 'sabtu' || dayName == 'minggu') {
        weekendTotal += hours;
      } else {
        weekdayTotal += hours;
      }
    }
    return {'weekday': weekdayTotal, 'weekend': weekendTotal};
  }

  Future<void> _exportToExcel() async {
    if (_laporanList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada data untuk diexport')));
      return;
    }

    var excel = excel_lib.Excel.createExcel();
    String sheetName = 'Laporan Lembur';
    excel.rename(excel.getDefaultSheet() ?? 'Sheet1', sheetName);
    var sheet = excel[sheetName];

    sheet.appendRow([
      excel_lib.TextCellValue('No'),
      excel_lib.TextCellValue('Hari'),
      excel_lib.TextCellValue('Tanggal'),
      excel_lib.TextCellValue('Nama Karyawan'),
      excel_lib.TextCellValue('Pekerjaan Lembur'),
      excel_lib.TextCellValue('Jam Mulai'),
      excel_lib.TextCellValue('Jam Selesai'),
      excel_lib.TextCellValue('Total Jam'),
      excel_lib.TextCellValue('Status'),
      excel_lib.TextCellValue('Approved By'),
      excel_lib.TextCellValue('Notes'), // Tambahan header Notes
    ]);

    int no = 1;
    for (var item in _laporanList) {
      final emp = item['employees'] ?? {};
      final approver =
          item['approver'] is Map ? item['approver']['full_name'] ?? '-' : '-';

      sheet.appendRow([
        excel_lib.IntCellValue(no++),
        excel_lib.TextCellValue(_getDayName(item['start_time'])),
        excel_lib.TextCellValue(_formatDate(item['start_time'])),
        excel_lib.TextCellValue(emp['full_name'] ?? '-'),
        excel_lib.TextCellValue(item['reason'] ?? '-'),
        excel_lib.TextCellValue(_formatTime(item['start_time'])),
        excel_lib.TextCellValue(_formatTime(item['end_time'])),
        excel_lib.TextCellValue('${item['duration_hours'] ?? '-'} Jam'),
        excel_lib.TextCellValue(item['status'] ?? 'Pending'),
        excel_lib.TextCellValue(approver),
        excel_lib.TextCellValue(
            item['notes']?.toString() ?? '-'), // Tambahan isi Notes
      ]);
    }

    final totals = _calculateTotalHours();

    // Sesuaikan panjang array agar pas dengan 11 kolom
    List<excel_lib.CellValue?> totalRow = List.filled(11, null);
    totalRow[6] = excel_lib.TextCellValue('Total Jam Lembur:');
    totalRow[7] =
        excel_lib.TextCellValue('${totals['weekday']?.toStringAsFixed(1)} Jam');
    sheet.appendRow(totalRow);

    List<excel_lib.CellValue?> totalWeekendRow = List.filled(11, null);
    totalWeekendRow[6] =
        excel_lib.TextCellValue('Total Jam Lembur (Hari Libur):');
    totalWeekendRow[7] =
        excel_lib.TextCellValue('${totals['weekend']?.toStringAsFixed(1)} Jam');
    sheet.appendRow(totalWeekendRow);

    String empName = _selectedEmployee['id'] == 'all'
        ? 'Semua_Karyawan'
        : (_selectedEmployee['full_name'] ?? 'Karyawan')
            .replaceAll(RegExp(r'[^\w\s]+'), '')
            .replaceAll(' ', '_');
    String dateStartStr = DateFormat('dd-MM-yyyy').format(_startDate);
    String dateEndStr = DateFormat('dd-MM-yyyy').format(_endDate);
    String fileName =
        'laporan_lembur_${empName}_${dateStartStr}_sd_${dateEndStr}.xlsx';

    final List<int>? rawBytes = excel.save();
    final Uint8List? fileBytes =
        rawBytes != null ? Uint8List.fromList(rawBytes) : null;

    if (fileBytes != null) {
      final blob = html.Blob([fileBytes],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
    }
  }

  Future<void> _exportToPDF() async {
    if (_laporanList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada data untuk dicetak')));
      return;
    }

    String subHeaderTitle = _selectedEmployee['id'] == 'all'
        ? 'Semua Karyawan'
        : 'Karyawan: ${_selectedEmployee['full_name']}';
    final totals = _calculateTotalHours();

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
                      pw.Text('Laporan Pekerjaan Lembur',
                          style: pw.TextStyle(
                              fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text(subHeaderTitle,
                          style: pw.TextStyle(
                              fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                          'Periode: ${DateFormat('dd MMM yyyy').format(_startDate)} s/d ${DateFormat('dd MMM yyyy').format(_endDate)}',
                          style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: [
                'No',
                'Hari',
                'Tanggal',
                'Nama Karyawan',
                'Pekerjaan Lembur',
                'Jam Mulai',
                'Jam Selesai',
                'Total Jam',
                'Status',
                'Approved By',
                'Notes' // Tambahan header Notes
              ],
              data: List<List<String>>.generate(_laporanList.length, (index) {
                final item = _laporanList[index];
                final emp = item['employees'] ?? {};
                final approver = item['approver'] is Map
                    ? item['approver']['full_name'] ?? '-'
                    : '-';

                return [
                  '${index + 1}',
                  _getDayName(item['start_time']),
                  _formatDate(item['start_time']),
                  emp['full_name'] ?? '-',
                  item['reason'] ?? '-',
                  _formatTime(item['start_time']),
                  _formatTime(item['end_time']),
                  '${item['duration_hours'] ?? '-'} Jam',
                  item['status'] ?? 'Pending',
                  approver,
                  item['notes']?.toString() ?? '-', // Tambahan data Notes
                ];
              }),
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                  color: PdfColors.white),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blue800),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FixedColumnWidth(25),
                1: const pw.FixedColumnWidth(45),
                2: const pw.FixedColumnWidth(60),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(1.5),
                5: const pw.FixedColumnWidth(50),
                6: const pw.FixedColumnWidth(50),
                7: const pw.FixedColumnWidth(60),
                8: const pw.FixedColumnWidth(55),
                9: const pw.FlexColumnWidth(1),
                10: const pw.FlexColumnWidth(1.2), // Lebar untuk kolom Notes
              },
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      child: pw.Text(
                        'Total Jam Lembur: ${totals['weekday']?.toStringAsFixed(1)} Jam',
                        style: pw.TextStyle(
                            fontSize: 11, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      child: pw.Text(
                        'Total Jam Lembur (Hari Libur): ${totals['weekend']?.toStringAsFixed(1)} Jam',
                        style: pw.TextStyle(
                            fontSize: 11, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    String empName = _selectedEmployee['id'] == 'all'
        ? 'Semua_Karyawan'
        : (_selectedEmployee['full_name'] ?? 'Karyawan')
            .replaceAll(RegExp(r'[^\w\s]+'), '')
            .replaceAll(' ', '_');
    String dateStartStr = DateFormat('dd-MM-yyyy').format(_startDate);
    String dateEndStr = DateFormat('dd-MM-yyyy').format(_endDate);
    String fileName =
        'laporan_lembur_${empName}_${dateStartStr}_sd_${dateEndStr}.pdf';

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
    final totals = _calculateTotalHours();

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
                    'Laporan Pekerjaan Lembur',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[900]),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _selectedEmployee['id'] == 'all'
                        ? 'Semua Karyawan'
                        : '${_selectedEmployee['full_name']}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700]),
                  ),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _laporanList.isEmpty ? null : _exportToExcel,
                    icon: const Icon(Icons.table_view, size: 16),
                    label: Text('Export Excel',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _laporanList.isEmpty ? null : _exportToPDF,
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: Text('Export PDF',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        foregroundColor: Colors.white),
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
                side: BorderSide(color: Colors.grey[300]!)),
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
                            'jabatan_name': '-'
                          }
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
                        _fetchLaporanLembur();
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
                            labelStyle:
                                GoogleFonts.plusJakartaSans(fontSize: 12),
                            isDense: true,
                            prefixIcon:
                                const Icon(Icons.person_search, size: 18),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
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
                          prefixIcon:
                              const Icon(Icons.calendar_today, size: 16),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(DateFormat('dd-MM-yyyy').format(_startDate),
                            style: GoogleFonts.plusJakartaSans(fontSize: 12)),
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
                          prefixIcon:
                              const Icon(Icons.calendar_today, size: 16),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(DateFormat('dd-MM-yyyy').format(_endDate),
                            style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _fetchLaporanLembur,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 20),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                    child: Text('Tampilkan',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, fontWeight: FontWeight.bold)),
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
                  side: BorderSide(color: Colors.grey[300]!)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _laporanList.isEmpty
                            ? Center(
                                child: Text('Tidak ada data laporan lembur.',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12)))
                            : Scrollbar(
                                controller: _horizontalScrollCtrl,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _horizontalScrollCtrl,
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                        minWidth:
                                            MediaQuery.of(context).size.width -
                                                80),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.vertical,
                                      child: DataTable(
                                        headingRowColor:
                                            WidgetStateProperty.all(
                                                Colors.blue[50]),
                                        headingTextStyle:
                                            GoogleFonts.plusJakartaSans(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue),
                                        dataTextStyle:
                                            GoogleFonts.plusJakartaSans(
                                                fontSize: 12),
                                        columns: const [
                                          DataColumn(label: Text('No')),
                                          DataColumn(label: Text('Hari')),
                                          DataColumn(label: Text('Tanggal')),
                                          DataColumn(
                                              label: Text('Nama Karyawan')),
                                          DataColumn(
                                              label: Text('Pekerjaan Lembur')),
                                          DataColumn(label: Text('Jam Mulai')),
                                          DataColumn(
                                              label: Text('Jam Selesai')),
                                          DataColumn(label: Text('Total Jam')),
                                          DataColumn(label: Text('Status')),
                                          DataColumn(
                                              label: Text('Approved By')),
                                          DataColumn(
                                              label: Text(
                                                  'Notes')), // Tambahan DataColumn Notes
                                        ],
                                        rows: List<DataRow>.generate(
                                            _laporanList.length, (index) {
                                          final item = _laporanList[index];
                                          final emp = item['employees'] ?? {};
                                          final startTimeStr =
                                              _formatTime(item['start_time']);
                                          final endTimeStr =
                                              _formatTime(item['end_time']);
                                          final dateStr =
                                              _formatDate(item['start_time']);
                                          final dayStr =
                                              _getDayName(item['start_time']);
                                          final approverName =
                                              item['approver'] is Map
                                                  ? (item['approver']
                                                          ['full_name'] ??
                                                      '-')
                                                  : '-';

                                          final status = item['status']
                                                  ?.toString()
                                                  .toLowerCase() ??
                                              'pending';
                                          Color badgeColor = Colors.orange;
                                          if (status == 'approved' ||
                                              status == 'disetujui')
                                            badgeColor = Colors.green;
                                          else if (status == 'rejected' ||
                                              status == 'ditolak')
                                            badgeColor = Colors.red;

                                          return DataRow(
                                            cells: [
                                              DataCell(Text('${index + 1}')),
                                              DataCell(Text(dayStr)),
                                              DataCell(Text(dateStr)),
                                              DataCell(Text(
                                                  emp['full_name'] ?? '-',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                              DataCell(
                                                  Text(item['reason'] ?? '-')),
                                              DataCell(Text(startTimeStr)),
                                              DataCell(Text(endTimeStr)),
                                              DataCell(Text(
                                                  '${item['duration_hours'] ?? '-'} Jam')),
                                              DataCell(
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                      color: badgeColor
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6)),
                                                  child: Text(
                                                      item['status'] ??
                                                          'Pending',
                                                      style: GoogleFonts
                                                          .plusJakartaSans(
                                                              fontSize: 11,
                                                              color: badgeColor,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold)),
                                                ),
                                              ),
                                              DataCell(Text(approverName,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w500))),
                                              DataCell(Text(item['notes']
                                                      ?.toString() ??
                                                  '-')), // Tambahan DataCell Notes
                                            ],
                                          );
                                        }),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                  ),
                  if (!_isLoading && _laporanList.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        border:
                            Border(top: BorderSide(color: Colors.grey[300]!)),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(10),
                          bottomRight: Radius.circular(10),
                        ),
                      ),
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Total Jam Lembur: ${totals['weekday']?.toStringAsFixed(1)} Jam',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[900],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total Jam Lembur (Hari Libur): ${totals['weekend']?.toStringAsFixed(1)} Jam',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[900],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
