import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

// Package Export
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class WebLaporanAbsensiPage extends StatefulWidget {
  const WebLaporanAbsensiPage({super.key});

  @override
  State<WebLaporanAbsensiPage> createState() => _WebLaporanAbsensiPageState();
}

class _WebLaporanAbsensiPageState extends State<WebLaporanAbsensiPage> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _departmentsList = [];

  Map<String, dynamic> _selectedEmployee = {
    'id': 'all',
    'full_name': 'Semua Karyawan',
    'nik': 'ALL',
    'jabatan_name': '-'
  };

  String _selectedDepartmentId = 'all';

  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  final TextEditingController _employeeSearchCtrl = TextEditingController();

  Map<String, List<Map<String, dynamic>>> _groupedAttendanceData = {};
  List<Map<String, dynamic>> _flatAttendanceData = [];

  final Map<int, List<Map<String, DateTime>>> _approvedLeaves = {};
  final Map<String, String> _holidaysMap = {};

  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();

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
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  Future<void> _fetchMasterData() async {
    setState(() => _isLoading = true);
    try {
      final empData = await Supabase.instance.client
          .from('employees')
          .select()
          .order('full_name', ascending: true);

      final locData = await Supabase.instance.client.from('locations').select();

      final deptData = await Supabase.instance.client
          .from('departments')
          .select()
          .order('name', ascending: true);

      setState(() {
        _employees = List<Map<String, dynamic>>.from(empData);
        _locations = List<Map<String, dynamic>>.from(locData);
        _departmentsList = List<Map<String, dynamic>>.from(deptData);
        _selectedDepartmentId = 'all';
        _employeeSearchCtrl.text = _selectedEmployee['full_name'];
      });

      await _fetchAttendance();
    } catch (e) {
      _showSnackBar('Gagal memuat data master: $e', Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchAttendance() async {
    setState(() => _isLoading = true);

    try {
      DateTime startUtc =
          DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0)
              .toUtc();
      // Sampai H+1 jam 12:00 supaya check-out pagi shift security terbawa
      DateTime endUtc =
          DateTime(_endDate.year, _endDate.month, _endDate.day + 1, 12, 0, 0)
              .toUtc();

      final leaveResponse = await Supabase.instance.client
          .from('leave_requests')
          .select('employee_id, start_date, end_date')
          .eq('status', 'approved');

      _approvedLeaves.clear();
      for (var l in leaveResponse) {
        int? eId = int.tryParse(l['employee_id']?.toString() ?? '');
        if (eId != null && l['start_date'] != null && l['end_date'] != null) {
          try {
            DateTime s = DateTime.parse(l['start_date']);
            DateTime e = DateTime.parse(l['end_date']);
            _approvedLeaves
                .putIfAbsent(eId, () => [])
                .add({'start': s, 'end': e});
          } catch (_) {}
        }
      }

      final holidaysResponse = await Supabase.instance.client
          .from('hari_libur')
          .select('holiday_date, description')
          .gte('holiday_date', DateFormat('yyyy-MM-dd').format(_startDate))
          .lte('holiday_date', DateFormat('yyyy-MM-dd').format(_endDate));

      _holidaysMap.clear();
      for (var h in holidaysResponse) {
        if (h['holiday_date'] != null) {
          String rawDate = h['holiday_date'].toString();
          String dateKey = rawDate.contains('T')
              ? rawDate.split('T')[0]
              : rawDate.substring(0, 10);

          _holidaysMap[dateKey] = h['description'] ?? 'Libur Nasional';
        }
      }

      var query = Supabase.instance.client.from('attendance').select('*');

      if (_selectedEmployee['id'] != 'all') {
        final empId = _selectedEmployee['id'];
        query = query.eq('employee_id', empId);
      }

      final response = await query
          .gte('created_at', startUtc.toIso8601String())
          .lte('created_at', endUtc.toIso8601String())
          .order('created_at', ascending: true);

      List<dynamic> rawData = response as List<dynamic>? ?? [];
      _processAttendanceData(rawData);
    } catch (e) {
      debugPrint('Error fetching attendance: $e');
      _processAttendanceData([]);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final c = cos;
    final a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 1000 * 12742 * asin(sqrt(a));
  }

  String _matchLocationName(dynamic latVal, dynamic lonVal) {
    if (latVal == null || lonVal == null || _locations.isEmpty) return '-';

    double? lat = double.tryParse(latVal.toString());
    double? lon = double.tryParse(lonVal.toString());
    if (lat == null || lon == null) return '-';

    for (var loc in _locations) {
      double? locLat = double.tryParse(loc['latitude']?.toString() ?? '');
      double? locLon = double.tryParse(loc['longitude']?.toString() ?? '');
      int radius =
          int.tryParse(loc['radius_meter']?.toString() ?? '100') ?? 100;

      if (locLat != null && locLon != null) {
        double distance = _calculateDistance(lat, lon, locLat, locLon);
        if (distance <= radius) {
          return loc['name']?.toString() ?? 'Lokasi Kantor';
        }
      }
    }
    return 'Luar Area Kantor';
  }

  String _getDepartmentName(dynamic deptId) {
    if (deptId == null) return '-';
    try {
      final dept = _departmentsList.firstWhere(
        (d) => d['id'].toString() == deptId.toString(),
        orElse: () => {},
      );
      return dept['name'] ?? '-';
    } catch (_) {
      return '-';
    }
  }

  String _formatDurasi(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final sec = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  int _sumWorkSeconds(List<Map<String, dynamic>> rows) {
    int total = 0;
    for (var r in rows) {
      total += (r['work_seconds'] as int?) ?? 0;
    }
    return total;
  }

  bool _isSecurityJabatan(dynamic jabatan) {
    return (jabatan ?? '').toString().trim().toLowerCase() == 'security';
  }

  void _processAttendanceData(List<dynamic> rawData) {
    Map<String, Map<String, List<dynamic>>> empDatePunches = {};

    // Peta id karyawan -> apakah security (shift malam 17:00 - 07:00)
    final Map<String, bool> securityMap = {};
    for (var emp in _employees) {
      securityMap[emp['id'].toString()] =
          _isSecurityJabatan(emp['jabatan_name']);
    }

    for (var item in rawData) {
      final empId =
          (item['employee_id'] ?? item['user_id'] ?? 'unknown').toString();
      final createdAtStr = item['created_at']?.toString();
      if (createdAtStr == null) continue;

      DateTime? dt = DateTime.tryParse(createdAtStr)?.toLocal();
      if (dt == null) continue;

      // Security: absen sebelum jam 12:00 masuk ke shift hari sebelumnya
      if ((securityMap[empId] ?? false) && dt.hour < 12) {
        dt = dt.subtract(const Duration(days: 1));
      }
      String dateKey = DateFormat('yyyy-MM-dd').format(dt);

      empDatePunches.putIfAbsent(empId, () => {});
      empDatePunches[empId]!.putIfAbsent(dateKey, () => []);
      empDatePunches[empId]![dateKey]!.add(item);
    }

    Map<String, List<Map<String, dynamic>>> grouped = {};
    List<Map<String, dynamic>> flat = [];

    List<Map<String, dynamic>> targetEmployees = [];
    if (_selectedEmployee['id'] == 'all') {
      targetEmployees = _employees.where((emp) {
        if (_selectedDepartmentId == 'all') return true;
        final empDeptId = emp['department_id']?.toString();
        return empDeptId == _selectedDepartmentId;
      }).toList();
    } else {
      targetEmployees = [_selectedEmployee];
    }

    for (var emp in targetEmployees) {
      final empIdStr = emp['id'].toString();
      final int? empIdInt = int.tryParse(empIdStr);
      final empName = emp['full_name'] ?? 'Karyawan';
      final empNik = emp['nik']?.toString() ?? '-';
      final empJabatan = emp['jabatan_name'] ?? '-';
      final empDeptName = _getDepartmentName(emp['department_id']);

      final bool isFreeLocation = emp['is_free_location'] ?? false;
      final bool isSecurity = _isSecurityJabatan(emp['jabatan_name']);
      final String workHours = isSecurity ? '17:00-07:00' : '08:30-17:30';

      List<Map<String, dynamic>> empRows = [];
      DateTime curr = _startDate;

      while (curr.isBefore(_endDate) || curr.isAtSameMomentAs(_endDate)) {
        String dateKey = DateFormat('yyyy-MM-dd').format(curr);
        String dateFormatted = DateFormat('dd-MM-yyyy').format(curr);
        String dayName = DateFormat('E', 'id_ID').format(curr);
        bool isWeekend = curr.weekday == DateTime.saturday ||
            curr.weekday == DateTime.sunday;

        bool isPublicHoliday = _holidaysMap.containsKey(dateKey);
        String publicHolidayName =
            isPublicHoliday ? _holidaysMap[dateKey]! : '-';

        bool isLeave = false;
        if (empIdInt != null && _approvedLeaves.containsKey(empIdInt)) {
          DateTime dateOnly = DateTime(curr.year, curr.month, curr.day);
          for (var range in _approvedLeaves[empIdInt]!) {
            DateTime s = DateTime(range['start']!.year, range['start']!.month,
                range['start']!.day);
            DateTime e = DateTime(
                range['end']!.year, range['end']!.month, range['end']!.day);
            if ((dateOnly.isAtSameMomentAs(s) || dateOnly.isAfter(s)) &&
                (dateOnly.isAtSameMomentAs(e) || dateOnly.isBefore(e))) {
              isLeave = true;
              break;
            }
          }
        }

        var punches = empDatePunches[empIdStr]?[dateKey];

        if (punches != null && punches.isNotEmpty) {
          punches.sort((a, b) => DateTime.parse(a['created_at'])
              .toLocal()
              .compareTo(DateTime.parse(b['created_at']).toLocal()));

          var firstPunch = punches.first;
          var lastPunch = punches.last;

          DateTime checkInDt =
              DateTime.parse(firstPunch['created_at']).toLocal();
          DateTime? checkOutDt = punches.length > 1
              ? DateTime.parse(lastPunch['created_at']).toLocal()
              : null;

          String checkInTime = DateFormat('HH:mm:ss').format(checkInDt);
          String checkOutTime = checkOutDt != null
              ? DateFormat('HH:mm:ss').format(checkOutDt)
              : '-';

          String lateStr = '-';

          // Batas terlambat: security 17:00, lainnya 08:45
          DateTime limitTime = isSecurity
              ? DateTime(curr.year, curr.month, curr.day, 17, 0, 0)
              : DateTime(
                  checkInDt.year, checkInDt.month, checkInDt.day, 8, 45, 0);

          if (checkInDt.isAfter(limitTime)) {
            Duration diff = checkInDt.difference(limitTime);
            int hours = diff.inHours;
            int minutes = diff.inMinutes % 60;
            int seconds = diff.inSeconds % 60;
            lateStr =
                '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
          } else {
            lateStr = '00:00:00';
          }

          String aktifitas = 'Bekerja';
          String notes = '-';

          if (isLeave) {
            notes = 'Cuti/Izin';
          } else if (isPublicHoliday) {
            notes = 'Masuk di Hari Libur ($publicHolidayName)';
          } else {
            if (checkInDt.isAfter(limitTime)) {
              notes = 'Terlambat';
            }
          }

          if (checkOutDt != null) {
            // Batas pulang: security 07:00 (hari berikutnya), lainnya 17:30
            DateTime earlyLimit = isSecurity
                ? DateTime(curr.year, curr.month, curr.day + 1, 7, 0, 0)
                : DateTime(checkOutDt.year, checkOutDt.month, checkOutDt.day,
                    17, 30, 0);
            if (checkOutDt.isBefore(earlyLimit)) {
              aktifitas = 'Check-out lbh awal';
            } else {
              aktifitas = 'Bekerja';
            }
          } else {
            aktifitas = 'Belum Checkout';
          }

          // Security: kolom aktifitas dikosongkan (kerja setiap hari).
          // Lainnya: Lembur jika absen (check-in & check-out) di Sabtu/Minggu.
          if (isSecurity) {
            aktifitas = '';
          } else if (isWeekend && checkOutDt != null) {
            aktifitas = 'Lembur';
          }

          // Durasi kerja (check-out - check-in), aman untuk shift lewat tengah malam
          int workSeconds = checkOutDt != null
              ? checkOutDt.difference(checkInDt).inSeconds
              : 0;

          String coordinate =
              '${firstPunch['latitude'] ?? '-'}, ${firstPunch['longitude'] ?? '-'}';

          String locationName = isFreeLocation
              ? 'Absen Bebas'
              : _matchLocationName(
                  firstPunch['latitude'], firstPunch['longitude']);

          var row = {
            'employee_id': empIdStr,
            'employee_name': empName,
            'nik': empNik,
            'jabatan': empJabatan,
            'department': empDeptName,
            'day': dayName,
            'date': dateFormatted,
            'work_hours': workHours,
            'check_in': checkInTime,
            'check_out': checkOutTime,
            'coordinate': coordinate,
            'location': locationName,
            'late': lateStr,
            'work_seconds': workSeconds,
            'aktifitas': aktifitas,
            'notes': notes,
          };
          empRows.add(row);
          flat.add(row);
        } else {
          String notes = '-';
          String aktifitas = 'Alpa';

          if (isLeave) {
            notes = 'Cuti/Izin';
            aktifitas = 'Cuti/Izin';
          } else if (isPublicHoliday) {
            notes = publicHolidayName;
            aktifitas = 'Libur';
          } else if (isWeekend && !isSecurity) {
            notes = 'Libur Akhir Pekan';
            aktifitas = 'Libur';
          }

          // Security bekerja setiap hari: kolom aktifitas dikosongkan
          if (isSecurity) {
            aktifitas = '';
          }

          var row = {
            'employee_id': empIdStr,
            'employee_name': empName,
            'nik': empNik,
            'jabatan': empJabatan,
            'department': empDeptName,
            'day': dayName,
            'date': dateFormatted,
            'work_hours': workHours,
            'check_in': '-',
            'check_out': '-',
            'coordinate': '-',
            'location': '-',
            'late': '-',
            'work_seconds': 0,
            'aktifitas': aktifitas,
            'notes': notes,
          };
          empRows.add(row);
          flat.add(row);
        }

        curr = curr.add(const Duration(days: 1));
      }

      grouped[empIdStr] = empRows;
    }

    setState(() {
      _groupedAttendanceData = grouped;
      _flatAttendanceData = flat;
    });
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg, style: const TextStyle(fontSize: 12)),
          backgroundColor: color),
    );
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
      _fetchAttendance();
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
      _fetchAttendance();
    }
  }

  Future<void> _exportAttendancePdf() async {
    if (_groupedAttendanceData.isEmpty) return;

    final pdf = pw.Document();
    final headers = [
      'Hari | Tanggal',
      'Jam Kerja',
      'Jam Check-in',
      'Jam Check-out',
      'Kordinat',
      'Nama Lokasi',
      'Terlambat',
      'Aktifitas',
      'Notes'
    ];

    _groupedAttendanceData.forEach((empId, rows) {
      if (rows.isEmpty) return;
      final firstRow = rows.first;
      final empName = firstRow['employee_name'];
      final empNik = firstRow['nik'];
      final empJabatan = firstRow['jabatan'];
      final empDept = firstRow['department'] ?? '-';

      int totalHariKerja = 0;
      int totalDetikTerlambat = 0;

      final pdfData = rows.map((row) {
        if (row['aktifitas'] == 'Bekerja' ||
            row['aktifitas'] == 'Check-out lbh awal' ||
            row['aktifitas'] == 'Belum Checkout' ||
            (row['check_in'] != '-' && row['check_in'] != null)) {
          totalHariKerja++;
        }
        String lateStr = row['late'] ?? '-';
        if (lateStr != '-' && lateStr != '00:00:00') {
          List<String> parts = lateStr.split(':');
          if (parts.length == 3) {
            int h = int.tryParse(parts[0]) ?? 0;
            int m = int.tryParse(parts[1]) ?? 0;
            int s = int.tryParse(parts[2]) ?? 0;
            totalDetikTerlambat += (h * 3600) + (m * 60) + s;
          }
        }

        return [
          '${row['day']} | ${row['date']}',
          row['work_hours'] ?? '-',
          row['check_in'] ?? '-',
          row['check_out'] ?? '-',
          row['coordinate'] ?? '-',
          row['location'] ?? '-',
          row['late'] ?? '-',
          row['aktifitas'] ?? '-',
          row['notes'] ?? '-',
        ];
      }).toList();

      int th = totalDetikTerlambat ~/ 3600;
      int tm = (totalDetikTerlambat % 3600) ~/ 60;
      int ts = totalDetikTerlambat % 60;
      String totalLateFormatted =
          '${th.toString().padLeft(2, '0')}:${tm.toString().padLeft(2, '0')}:${ts.toString().padLeft(2, '0')}';
      String totalJamKerjaFormatted = _formatDurasi(_sumWorkSeconds(rows));

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (context) {
            return [
              pw.Text('LAPORAN KEHADIRAN KARYAWAN',
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900)),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Nama: $empName',
                          style: pw.TextStyle(
                              fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text('ID / NIK: $empNik',
                          style: pw.TextStyle(fontSize: 10)),
                      pw.Text('Jabatan: $empJabatan',
                          style: pw.TextStyle(fontSize: 10)),
                      pw.Text('Divisi: $empDept',
                          style: pw.TextStyle(
                              fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                          'Periode: ${DateFormat('dd-MM-yyyy').format(_startDate)} s/d ${DateFormat('dd-MM-yyyy').format(_endDate)}',
                          style: pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1, height: 16),
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: pdfData,
                border:
                    pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
                headerStyle: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.blue800),
                cellStyle: pw.TextStyle(fontSize: 8),
                cellAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.all(6),
              ),
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Total Hari Kerja: $totalHariKerja hari',
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Total Jam Terlambat: $totalLateFormatted',
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Total Jam Kerja: $totalJamKerjaFormatted',
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
            ];
          },
        ),
      );
    });

    final bytes = await pdf.save();
    final uint8List = Uint8List.fromList(bytes);
    final blob = web.Blob(
        [uint8List.toJS].toJS, web.BlobPropertyBag(type: 'application/pdf'));
    final url = web.URL.createObjectURL(blob);
    final fileName = _selectedEmployee['id'] == 'all'
        ? "Laporan_Kehadiran_Semua_Karyawan_${DateTime.now().millisecondsSinceEpoch}.pdf"
        : "Laporan_Kehadiran_${(_selectedEmployee['full_name']).replaceAll(' ', '_')}.pdf";
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }

  void _exportAttendanceExcel() {
    if (_groupedAttendanceData.isEmpty) return;

    var excel = Excel.createExcel();
    excel.delete('Sheet1');

    _groupedAttendanceData.forEach((empId, rows) {
      if (rows.isEmpty) return;
      final firstRow = rows.first;
      final empName = firstRow['employee_name'] ?? 'Karyawan';
      String sheetName = empName.replaceAll(RegExp(r'[\/?*\[\]:]'), '_');
      if (sheetName.length > 31) sheetName = sheetName.substring(0, 31);

      Sheet sheetObject = excel[sheetName];
      excel.setDefaultSheet(sheetName);

      sheetObject.appendRow([TextCellValue('LAPORAN KEHADIRAN KARYAWAN')]);
      sheetObject.appendRow([
        TextCellValue('Nama: $empName'),
        TextCellValue('NIK: ${firstRow['nik']}'),
        TextCellValue('Jabatan: ${firstRow['jabatan']}'),
        TextCellValue('Divisi: ${firstRow['department'] ?? '-'}')
      ]);
      sheetObject.appendRow([
        TextCellValue(
            'Periode: ${DateFormat('dd-MM-yyyy').format(_startDate)} s/d ${DateFormat('dd-MM-yyyy').format(_endDate)}')
      ]);
      sheetObject.appendRow([]);

      List<String> headers = [
        'Hari',
        'Tanggal',
        'Jam Kerja',
        'Jam Check-in / Check-out',
        'Kordinat',
        'Nama Lokasi',
        'Terlambat',
        'Aktifitas',
        'Notes'
      ];
      sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

      int totalHariKerja = 0;
      int totalDetikTerlambat = 0;

      for (var row in rows) {
        if (row['aktifitas'] == 'Bekerja' ||
            row['aktifitas'] == 'Check-out lbh awal' ||
            row['aktifitas'] == 'Belum Checkout' ||
            (row['check_in'] != '-' && row['check_in'] != null)) {
          totalHariKerja++;
        }
        String lateStr = row['late'] ?? '-';
        if (lateStr != '-' && lateStr != '00:00:00') {
          List<String> parts = lateStr.split(':');
          if (parts.length == 3) {
            int h = int.tryParse(parts[0]) ?? 0;
            int m = int.tryParse(parts[1]) ?? 0;
            int s = int.tryParse(parts[2]) ?? 0;
            totalDetikTerlambat += (h * 3600) + (m * 60) + s;
          }
        }

        String checkIn = row['check_in'] ?? '-';
        String checkOut = row['check_out'] ?? '-';

        // Baris Pertama: Menampilkan jam Check-in (Terlambat & Notes diisi)
        List<String> rowDataCheckIn = [
          row['day'] ?? '',
          row['date'] ?? '',
          row['work_hours'] ?? '',
          checkIn,
          row['coordinate'] ?? '',
          row['location'] ?? '',
          row['late'] ?? '',
          row['aktifitas'] ?? '',
          row['notes'] ?? '',
        ];
        sheetObject
            .appendRow(rowDataCheckIn.map((e) => TextCellValue(e)).toList());

        // Baris Kedua: Menampilkan jam Check-out (Terlambat & Notes dikosongkan)
        List<String> rowDataCheckOut = [
          row['day'] ?? '',
          row['date'] ?? '',
          row['work_hours'] ?? '',
          checkOut,
          row['coordinate'] ?? '',
          row['location'] ?? '',
          '', // Kolom Terlambat dikosongkan
          row['aktifitas'] ?? '',
          '', // Kolom Notes dikosongkan
        ];
        sheetObject
            .appendRow(rowDataCheckOut.map((e) => TextCellValue(e)).toList());
      }

      int th = totalDetikTerlambat ~/ 3600;
      int tm = (totalDetikTerlambat % 3600) ~/ 60;
      int ts = totalDetikTerlambat % 60;
      String totalLateFormatted =
          '${th.toString().padLeft(2, '0')}:${tm.toString().padLeft(2, '0')}:${ts.toString().padLeft(2, '0')}';
      String totalJamKerjaFormatted = _formatDurasi(_sumWorkSeconds(rows));

      sheetObject.appendRow([]);
      sheetObject.appendRow([
        TextCellValue('Total Hari Kerja:'),
        TextCellValue('$totalHariKerja hari')
      ]);
      sheetObject.appendRow([
        TextCellValue('Total Jam Terlambat:'),
        TextCellValue(totalLateFormatted)
      ]);
      sheetObject.appendRow([
        TextCellValue('Total Jam Kerja:'),
        TextCellValue(totalJamKerjaFormatted)
      ]);
    });

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
      final fileName = _selectedEmployee['id'] == 'all'
          ? "Laporan_Kehadiran_Semua_Karyawan_${DateTime.now().millisecondsSinceEpoch}.xlsx"
          : "Laporan_Kehadiran_${(_selectedEmployee['full_name']).replaceAll(' ', '_')}.xlsx";

      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..download = fileName;

      web.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      web.URL.revokeObjectURL(url);
    }
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
                'Laporan Kehadiran Karyawan',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[900],
                ),
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _flatAttendanceData.isEmpty
                        ? null
                        : _exportAttendanceExcel,
                    icon: const Icon(Icons.table_view, size: 16),
                    label: const Text('Export Excel',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _flatAttendanceData.isEmpty
                        ? null
                        : _exportAttendancePdf,
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('Export PDF',
                        style: TextStyle(fontSize: 12)),
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
                            'jabatan_name': '-'
                          }
                        ];
                        allOptions.addAll(_employees);

                        return allOptions.where((emp) {
                          if (_selectedDepartmentId != 'all' &&
                              emp['id'] != 'all') {
                            final empDeptId = emp['department_id']?.toString();
                            if (empDeptId != _selectedDepartmentId)
                              return false;
                          }

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
                        _fetchAttendance();
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
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            labelText: 'Cari & Pilih Karyawan',
                            labelStyle: const TextStyle(fontSize: 12),
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
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      value: _selectedDepartmentId,
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('Semua Divisi',
                              style: TextStyle(fontSize: 12)),
                        ),
                        ..._departmentsList.map((dept) {
                          return DropdownMenuItem(
                            value: dept['id'].toString(),
                            child: Text(
                              dept['name']?.toString() ?? '-',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedDepartmentId = val;
                            _selectedEmployee = {
                              'id': 'all',
                              'full_name': 'Semua Karyawan',
                              'nik': 'ALL',
                              'jabatan_name': '-'
                            };
                            _employeeSearchCtrl.text = 'Semua Karyawan';
                          });
                          _fetchAttendance();
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Divisi',
                        labelStyle: const TextStyle(fontSize: 12),
                        isDense: true,
                        prefixIcon: const Icon(Icons.business, size: 18),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: InkWell(
                      onTap: () => _selectStartDate(context),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Tanggal Mulai',
                          labelStyle: const TextStyle(fontSize: 12),
                          isDense: true,
                          prefixIcon:
                              const Icon(Icons.calendar_today, size: 16),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          DateFormat('dd-MM-yyyy').format(_startDate),
                          style: const TextStyle(fontSize: 12),
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
                          labelStyle: const TextStyle(fontSize: 12),
                          isDense: true,
                          prefixIcon:
                              const Icon(Icons.calendar_today, size: 16),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          DateFormat('dd-MM-yyyy').format(_endDate),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _fetchAttendance,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Tampilkan',
                        style: TextStyle(
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
                side: BorderSide(color: Colors.grey[300]!),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _flatAttendanceData.isEmpty
                      ? const Center(
                          child: Text('Tidak ada data kehadiran.',
                              style: TextStyle(fontSize: 12)))
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            return ScrollConfiguration(
                              behavior:
                                  ScrollConfiguration.of(context).copyWith(
                                dragDevices: {
                                  PointerDeviceKind.touch,
                                  PointerDeviceKind.mouse,
                                  PointerDeviceKind.trackpad,
                                },
                              ),
                              child: Scrollbar(
                                controller: _horizontalScroll,
                                thumbVisibility: true,
                                trackVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _horizontalScroll,
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth,
                                    ),
                                    child: Scrollbar(
                                      controller: _verticalScroll,
                                      thumbVisibility: true,
                                      child: SingleChildScrollView(
                                        controller: _verticalScroll,
                                        scrollDirection: Axis.vertical,
                                        child: DataTable(
                                          headingRowColor:
                                              WidgetStateProperty.all(
                                            Colors.blue[50],
                                          ),
                                          headingTextStyle: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                          dataTextStyle:
                                              const TextStyle(fontSize: 12),
                                          columns: const [
                                            DataColumn(
                                                label: Text('Nama Karyawan')),
                                            DataColumn(
                                                label: Text('Hari | Tanggal')),
                                            DataColumn(
                                                label: Text('Jam Kerja')),
                                            DataColumn(
                                                label: Text('Jam Check-in')),
                                            DataColumn(
                                                label: Text('Jam Check-out')),
                                            DataColumn(label: Text('Kordinat')),
                                            DataColumn(
                                                label: Text('Nama Lokasi')),
                                            DataColumn(
                                                label: Text('Terlambat')),
                                            DataColumn(
                                                label: Text('Aktifitas')),
                                            DataColumn(label: Text('Notes')),
                                          ],
                                          rows: _flatAttendanceData.map((row) {
                                            return DataRow(
                                              cells: [
                                                DataCell(Text(
                                                    row['employee_name'] ??
                                                        '-')),
                                                DataCell(Text(
                                                    '${row['day']} | ${row['date']}')),
                                                DataCell(Text(
                                                    row['work_hours'] ?? '-')),
                                                DataCell(Text(
                                                    row['check_in'] ?? '-')),
                                                DataCell(Text(
                                                    row['check_out'] ?? '-')),
                                                DataCell(Text(
                                                    row['coordinate'] ?? '-')),
                                                DataCell(Text(
                                                    row['location'] ?? '-')),
                                                DataCell(
                                                    Text(row['late'] ?? '-')),
                                                DataCell(Text(
                                                    row['aktifitas'] ?? '-')),
                                                DataCell(
                                                  Text(
                                                    row['notes'] ?? '-',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: row['notes'] ==
                                                              'Cuti/Izin'
                                                          ? Colors.green
                                                          : (row['notes'] ==
                                                                      'Terlambat' ||
                                                                  row['aktifitas'] ==
                                                                      'Libur'
                                                              ? Colors.red
                                                              : Colors.black87),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
