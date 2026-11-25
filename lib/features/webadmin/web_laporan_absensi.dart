import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:math';
// Border & BorderStyle disembunyikan dari Flutter karena namanya bentrok
// dengan Border & BorderStyle milik package excel (dipakai di export Excel).
import 'package:flutter/material.dart' hide Border, BorderStyle;
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
        // User administrator tidak dimasukkan ke laporan (tabel, PDF, Excel)
        _employees = List<Map<String, dynamic>>.from(empData)
            .where((emp) => !_isAdminRole(emp['role']))
            .toList();
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
      DateTime startUtc = DateTime(
              _startDate.year, _startDate.month, _startDate.day - 1, 12, 0, 0)
          .toUtc();
      DateTime endUtc =
          DateTime(_endDate.year, _endDate.month, _endDate.day + 1, 12, 0, 0)
              .toUtc();

      // Cuti approved juga diambil per halaman (batas 1000 baris per request)
      final List<dynamic> leaveResponse = [];
      int leaveFrom = 0;
      while (true) {
        final List<dynamic> leavePage = await Supabase.instance.client
            .from('leave_requests')
            .select('employee_id, start_date, end_date')
            .eq('status', 'approved')
            .order('id', ascending: true)
            .range(leaveFrom, leaveFrom + 999);
        leaveResponse.addAll(leavePage);
        if (leavePage.length < 1000) break;
        leaveFrom += 1000;
      }

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

      // Supabase membatasi 1 request maksimal 1000 baris. Untuk "Semua
      // Karyawan" 1 bulan, jumlah absen bisa lebih dari 1000 sehingga data
      // paling akhir terpotong. Karena itu data diambil per halaman (1000
      // baris) sampai habis.
      const int pageSize = 1000;
      final List<dynamic> rawData = [];
      int from = 0;

      while (true) {
        var query = Supabase.instance.client.from('attendance').select('*');

        if (_selectedEmployee['id'] != 'all') {
          final empId = _selectedEmployee['id'];
          query = query.eq('employee_id', empId);
        }

        final List<dynamic> page = await query
            .gte('created_at', startUtc.toIso8601String())
            .lte('created_at', endUtc.toIso8601String())
            .order('created_at', ascending: true)
            .order('id', ascending: true) // urutan stabil antar halaman
            .range(from, from + pageSize - 1);

        rawData.addAll(page);
        if (page.length < pageSize) break;
        from += pageSize;
      }

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

  bool _isAdminRole(dynamic role) {
    final r = (role ?? '').toString().trim().toLowerCase();
    return r == 'admin' || r == 'administrator';
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

  bool _isDriverJabatan(dynamic jabatan) {
    final j = (jabatan ?? '').toString().trim().toLowerCase();
    return const ['driver', 'ob', 'cs'].contains(j);
  }

  String? _punchKind(dynamic item) {
    final st = (item['status'] ?? '').toString().toLowerCase();
    if (st.contains('out') || st.contains('pulang') || st.contains('keluar')) {
      return 'out';
    }
    if (st.contains('in') || st.contains('masuk') || st.contains('hadir')) {
      return 'in';
    }
    return null;
  }

  Map<String, Map<String, dynamic>> _groupSecurityShifts(List<dynamic> list,
      {bool isSec = true}) {
    final Map<String, Map<String, dynamic>> result = {};
    list.sort((x, y) => DateTime.parse(x['created_at'])
        .compareTo(DateTime.parse(y['created_at'])));

    List<dynamic> current = [];
    bool currentHasIn = false;

    void finalizeShift() {
      if (current.isEmpty) return;
      final firstDt = DateTime.parse(current.first['created_at']).toLocal();
      DateTime shiftDay = DateTime(firstDt.year, firstDt.month, firstDt.day);
      String shift;
      if (currentHasIn) {
        shift = firstDt.hour < 12 ? 'day' : 'night';
      } else {
        shift = isSec && firstDt.hour < 12 ? 'night' : 'day';
        if (isSec && firstDt.hour < 12) {
          shiftDay = shiftDay.subtract(const Duration(days: 1));
        }
      }
      final key = DateFormat('yyyy-MM-dd').format(shiftDay);
      if (result.containsKey(key)) {
        (result[key]!['punches'] as List<dynamic>).addAll(current);
      } else {
        result[key] = {
          'punches': List<dynamic>.from(current),
          'hasIn': currentHasIn,
          'shift': shift,
        };
      }
      current = [];
      currentHasIn = false;
    }

    for (var p in list) {
      final dt = DateTime.parse(p['created_at']).toLocal();
      final kind = _punchKind(p) ?? (current.isEmpty ? 'in' : 'out');
      if (kind == 'in') {
        finalizeShift();
        current = [p];
        currentHasIn = true;
      } else {
        if (currentHasIn &&
            dt
                    .difference(
                        DateTime.parse(current.first['created_at']).toLocal())
                    .inHours <=
                20) {
          current.add(p);
          finalizeShift();
        } else {
          finalizeShift();
          current = [p];
          currentHasIn = false;
          finalizeShift();
        }
      }
    }
    finalizeShift();
    return result;
  }

  void _processAttendanceData(List<dynamic> rawData) {
    Map<String, Map<String, List<dynamic>>> empDatePunches = {};

    final Map<String, bool> securityMap = {};
    final Map<String, List<dynamic>> secRaw = {};
    final Map<String, Map<String, Map<String, dynamic>>> secShifts = {};
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

      secRaw.putIfAbsent(empId, () => []).add(item);
    }

    secRaw.forEach((empId, list) {
      final groups =
          _groupSecurityShifts(list, isSec: securityMap[empId] == true);
      secShifts[empId] = groups;
      empDatePunches[empId] = {};
      groups.forEach((dk, g) {
        empDatePunches[empId]![dk] = g['punches'] as List<dynamic>;
      });
    });

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
      final bool isDriver = _isDriverJabatan(emp['jabatan_name']);
      final String workHours = isSecurity
          ? '17:00-07:00'
          : (isDriver ? '08:00-17:00' : '08:30-17:30');

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

        Map<String, dynamic>? secInfo;
        if (isSecurity) {
          final secByDate = secShifts[empIdStr];
          if (secByDate != null) {
            secInfo = secByDate[dateKey];
          }
        }
        final bool isNightShift =
            isSecurity && (secInfo == null || secInfo['shift'] == 'night');
        final bool onlyCheckOut =
            isSecurity && secInfo != null && secInfo['hasIn'] == false;

        if (punches != null && punches.isNotEmpty) {
          punches.sort((a, b) => DateTime.parse(a['created_at'])
              .toLocal()
              .compareTo(DateTime.parse(b['created_at']).toLocal()));

          var firstPunch = punches.first;
          var lastPunch = punches.last;

          DateTime checkInDt =
              DateTime.parse(firstPunch['created_at']).toLocal();
          DateTime? checkOutDt = onlyCheckOut
              ? checkInDt
              : (punches.length > 1
                  ? DateTime.parse(lastPunch['created_at']).toLocal()
                  : null);

          String checkInTime =
              onlyCheckOut ? '-' : DateFormat('HH:mm:ss').format(checkInDt);
          String checkOutTime = checkOutDt != null
              ? DateFormat('HH:mm:ss').format(checkOutDt)
              : '-';

          String lateStr = '-';

          DateTime limitTime = isSecurity
              ? DateTime(
                  curr.year, curr.month, curr.day, isNightShift ? 17 : 7, 15, 0)
              : DateTime(checkInDt.year, checkInDt.month, checkInDt.day, 8,
                  isDriver ? 15 : 45, 0);

          final bool skipLate = (isWeekend && !isSecurity) || onlyCheckOut;

          if (!skipLate && checkInDt.isAfter(limitTime)) {
            Duration diff = checkInDt.difference(limitTime);
            int hours = diff.inHours;
            int minutes = diff.inMinutes % 60;
            int seconds = diff.inSeconds % 60;
            lateStr =
                '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
          } else {
            lateStr = skipLate ? '-' : '00:00:00';
          }

          String aktifitas = 'Bekerja';
          String notes = '-';

          if (isLeave) {
            notes = 'Cuti/Izin';
          } else if (isPublicHoliday) {
            notes = 'Masuk di Hari Libur ($publicHolidayName)';
          } else {
            if (!skipLate && checkInDt.isAfter(limitTime)) {
              notes = 'Terlambat';
            }
          }

          if (checkOutDt != null) {
            DateTime earlyLimit = isSecurity
                ? (isNightShift
                    ? DateTime(curr.year, curr.month, curr.day + 1, 7, 0, 0)
                    : DateTime(curr.year, curr.month, curr.day, 17, 0, 0))
                : DateTime(
                    curr.year, curr.month, curr.day, 17, isDriver ? 0 : 30, 0);
            if (checkOutDt.isBefore(earlyLimit)) {
              aktifitas = 'Check-out lbh awal';
            } else {
              aktifitas = 'Bekerja';
            }
          } else {
            aktifitas = 'Belum Checkout';
          }

          if (isSecurity) {
            aktifitas = '';
          } else if (isWeekend && checkOutDt != null) {
            aktifitas = 'Lembur';
          }

          int workSeconds = 0;
          if (checkOutDt != null && !onlyCheckOut) {
            workSeconds = checkOutDt.difference(checkInDt).inSeconds;

            DateTime breakStart = DateTime(
                checkInDt.year, checkInDt.month, checkInDt.day, 12, 0, 0);
            DateTime breakEnd = DateTime(
                checkInDt.year, checkInDt.month, checkInDt.day, 13, 0, 0);

            if (checkInDt.isBefore(breakStart) &&
                checkOutDt.isAfter(breakEnd)) {
              workSeconds -= 3600;
            } else if (checkInDt.isBefore(breakEnd) &&
                checkOutDt.isAfter(breakStart)) {
              DateTime overlapStart =
                  checkInDt.isAfter(breakStart) ? checkInDt : breakStart;
              DateTime overlapEnd =
                  checkOutDt.isBefore(breakEnd) ? checkOutDt : breakEnd;
              int overlapSeconds =
                  overlapEnd.difference(overlapStart).inSeconds;

              if (overlapSeconds > 0) {
                workSeconds -= overlapSeconds;
              }
            }
          }

          // Koordinat & Lokasi Check-in
          String coordinateIn = onlyCheckOut
              ? '-'
              : '${firstPunch['latitude'] ?? '-'}, ${firstPunch['longitude'] ?? '-'}';
          String locationIn = onlyCheckOut
              ? '-'
              : (isFreeLocation
                  ? 'Absen Bebas'
                  : _matchLocationName(
                      firstPunch['latitude'], firstPunch['longitude']));

          // Koordinat & Lokasi Check-out (diambil dari lastPunch)
          String coordinateOut = checkOutDt != null
              ? '${lastPunch['latitude'] ?? '-'}, ${lastPunch['longitude'] ?? '-'}'
              : '-';
          String locationOut = checkOutDt != null
              ? (isFreeLocation
                  ? 'Absen Bebas'
                  : _matchLocationName(
                      lastPunch['latitude'], lastPunch['longitude']))
              : '-';

          var row = {
            'employee_id': empIdStr,
            'employee_name': empName,
            'nik': empNik,
            'jabatan': empJabatan,
            'department': empDeptName,
            'day': dayName,
            'date': dateFormatted,
            'work_hours': isSecurity
                ? (isNightShift ? 'Shift Malam' : 'Shift Pagi')
                : workHours,
            'check_in': checkInTime,
            'check_out': checkOutTime,
            'coordinate': coordinateIn,
            'location': locationIn,
            'coordinate_out': coordinateOut,
            'location_out': locationOut,
            'late': lateStr,
            'work_seconds': workSeconds,
            'work_total': workSeconds > 0 ? _formatDurasi(workSeconds) : '-',
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
            'work_hours': isSecurity ? '-' : workHours,
            'check_in': '-',
            'check_out': '-',
            'coordinate': '-',
            'location': '-',
            'coordinate_out': '-',
            'location_out': '-',
            'late': '-',
            'work_seconds': 0,
            'work_total': '-',
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
      'Jam Check-in / Check-out',
      'Kordinat',
      'Nama Lokasi',
      'Terlambat',
      'Total Jam Kerja',
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

      // 2 baris per tanggal: Baris 1 = Check-in, Baris 2 = Check-out (beserta kordinat & lokasi check-out)
      final List<List<String>> pdfData = [];
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

        // Baris 1: Check-in
        pdfData.add([
          '${row['day']} | ${row['date']}',
          row['work_hours'] ?? '-',
          row['check_in'] ?? '-',
          row['coordinate'] ?? '-',
          row['location'] ?? '-',
          lateStr,
          row['work_total'] ?? '-',
          row['aktifitas'] ?? '-',
          row['notes'] ?? '-',
        ]);

        // Baris 2: Check-out
        pdfData.add([
          '',
          '',
          row['check_out'] ?? '-',
          row['coordinate_out'] ?? '-',
          row['location_out'] ?? '-',
          '',
          '',
          '',
          '',
        ]);
      }

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
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.blue800),
                cellStyle: const pw.TextStyle(fontSize: 7.5),
                cellAlignment: pw.Alignment.centerLeft,
                cellPadding:
                    const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
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
    const String sheetName = 'Laporan Kehadiran';
    excel.rename('Sheet1', sheetName);
    Sheet sheetObject = excel[sheetName];
    excel.setDefaultSheet(sheetName);

    // Semua sel ditulis dengan nomor baris eksplisit (bukan appendRow).
    // appendRow selalu menempel di baris terakhir yang berisi data, sehingga
    // baris kosong pemisah antar karyawan tidak pernah muncul dan posisi
    // style/merge bisa bergeser. Dengan nomor baris eksplisit, baris kosong
    // cukup dibuat dengan menaikkan currentRow.
    int currentRow = 0;

    CellIndex idx(int col, int row) =>
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);

    void putCell(int col, int row, String value, CellStyle style) {
      sheetObject.updateCell(idx(col, row), TextCellValue(value),
          cellStyle: style);
    }

    void styleCell(int col, int row, CellStyle style) {
      sheetObject.cell(idx(col, row)).cellStyle = style;
    }

    void mergeCells(int c1, int r1, int c2, int r2) {
      sheetObject.merge(idx(c1, r1), idx(c2, r2));
    }

    // ---------- Border ----------
    final Border sideBorder = Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: ExcelColor.fromHexString('#BDBDBD'),
    );
    final Border groupDividerBorder = Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: ExcelColor.fromHexString('#9E9E9E'),
    );
    final Border innerDashedBorder = Border(
      borderStyle: BorderStyle.Dotted,
      borderColorHex: ExcelColor.fromHexString('#E0E0E0'),
    );

    // ---------- Style ----------
    final titleStyle = CellStyle(
      bold: true,
      fontSize: 13,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#0D47A1'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
    );

    final infoLabelStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#333333'),
      backgroundColorHex: ExcelColor.fromHexString('#E3F2FD'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      topBorder: sideBorder,
      bottomBorder: sideBorder,
      leftBorder: sideBorder,
      rightBorder: sideBorder,
    );

    final infoValueStyle = CellStyle(
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      topBorder: sideBorder,
      bottomBorder: sideBorder,
      leftBorder: sideBorder,
      rightBorder: sideBorder,
    );

    final headerStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1565C0'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: sideBorder,
      bottomBorder: sideBorder,
      leftBorder: sideBorder,
      rightBorder: sideBorder,
    );

    CellStyle buildBodyStyle({
      required Border top,
      required Border bottom,
      HorizontalAlign align = HorizontalAlign.Left,
      String bgHex = '#FFFFFF',
      String fontHex = '#212121',
      bool isBold = false,
    }) {
      return CellStyle(
        bold: isBold,
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString(fontHex),
        backgroundColorHex: ExcelColor.fromHexString(bgHex),
        horizontalAlign: align,
        verticalAlign: VerticalAlign.Center,
        topBorder: top,
        bottomBorder: bottom,
        leftBorder: sideBorder,
        rightBorder: sideBorder,
      );
    }

    final summaryLabelStyle = CellStyle(
      bold: true,
      fontSize: 10,
      backgroundColorHex: ExcelColor.fromHexString('#ECEFF1'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      topBorder: sideBorder,
      bottomBorder: sideBorder,
      leftBorder: sideBorder,
      rightBorder: sideBorder,
    );

    final summaryValueStyle = CellStyle(
      bold: true,
      fontSize: 10,
      backgroundColorHex: ExcelColor.fromHexString('#ECEFF1'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: sideBorder,
      bottomBorder: sideBorder,
      leftBorder: sideBorder,
      rightBorder: sideBorder,
    );

    final List<String> headers = [
      'Hari',
      'Tanggal',
      'Jam Kerja',
      'Jam Check-in / Check-out',
      'Kordinat',
      'Nama Lokasi',
      'Terlambat',
      'Total Jam Kerja',
      'Aktifitas',
      'Notes',
    ];
    final int lastCol = headers.length - 1;

    // Kolom yang di-merge ke bawah (2 baris check-in & check-out jadi 1 sel)
    const List<int> mergedCols = [0, 1, 2, 6, 7, 8, 9];
    // Kolom yang rata tengah
    const List<int> centerCols = [0, 1, 2, 3, 6, 7, 8];

    // Baris info identitas karyawan: label (kolom A-B) + isi (kolom C-F)
    void addInfoRow(String label, String value) {
      mergeCells(0, currentRow, 1, currentRow);
      mergeCells(2, currentRow, 5, currentRow);
      putCell(0, currentRow, label, infoLabelStyle);
      styleCell(1, currentRow, infoLabelStyle);
      putCell(2, currentRow, value, infoValueStyle);
      for (int c = 3; c <= 5; c++) {
        styleCell(c, currentRow, infoValueStyle);
      }
      sheetObject.setRowHeight(currentRow, 19);
      currentRow++;
    }

    // Baris ringkasan: label (kolom A-B) + nilai (kolom C)
    void addSummaryRow(String label, String value) {
      mergeCells(0, currentRow, 1, currentRow);
      putCell(0, currentRow, label, summaryLabelStyle);
      styleCell(1, currentRow, summaryLabelStyle);
      putCell(2, currentRow, value, summaryValueStyle);
      sheetObject.setRowHeight(currentRow, 20);
      currentRow++;
    }

    bool isFirstEmployee = true;

    _groupedAttendanceData.forEach((empId, rows) {
      if (rows.isEmpty) return;
      final firstRow = rows.first;
      final empName = firstRow['employee_name'] ?? 'Karyawan';

      // 2 baris kosong sebagai pemisah antar karyawan
      if (!isFirstEmployee) {
        currentRow += 2;
      }
      isFirstEmployee = false;

      // ---- Judul ----
      mergeCells(0, currentRow, lastCol, currentRow);
      putCell(0, currentRow, 'LAPORAN KEHADIRAN KARYAWAN', titleStyle);
      for (int c = 1; c <= lastCol; c++) {
        styleCell(c, currentRow, titleStyle);
      }
      sheetObject.setRowHeight(currentRow, 24);
      currentRow++;

      // ---- Identitas ----
      addInfoRow('Nama Karyawan', '$empName');
      addInfoRow('ID / NIK', '${firstRow['nik'] ?? '-'}');
      addInfoRow('Jabatan', '${firstRow['jabatan'] ?? '-'}');
      addInfoRow('Divisi', '${firstRow['department'] ?? '-'}');
      addInfoRow(
        'Periode',
        '${DateFormat('dd-MM-yyyy').format(_startDate)} s/d ${DateFormat('dd-MM-yyyy').format(_endDate)}',
      );
      currentRow++; // 1 baris kosong sebelum tabel

      // ---- Header tabel ----
      for (int c = 0; c < headers.length; c++) {
        putCell(c, currentRow, headers[c], headerStyle);
      }
      sheetObject.setRowHeight(currentRow, 24);
      currentRow++;

      int totalHariKerja = 0;
      int totalDetikTerlambat = 0;

      // ---- Data: tiap tanggal = 2 baris (check-in & check-out) ----
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];

        if (row['aktifitas'] == 'Bekerja' ||
            row['aktifitas'] == 'Check-out lbh awal' ||
            row['aktifitas'] == 'Belum Checkout' ||
            (row['check_in'] != '-' && row['check_in'] != null)) {
          totalHariKerja++;
        }

        final String lateStr = row['late'] ?? '-';
        if (lateStr != '-' && lateStr != '00:00:00') {
          List<String> parts = lateStr.split(':');
          if (parts.length == 3) {
            int h = int.tryParse(parts[0]) ?? 0;
            int m = int.tryParse(parts[1]) ?? 0;
            int s = int.tryParse(parts[2]) ?? 0;
            totalDetikTerlambat += (h * 3600) + (m * 60) + s;
          }
        }

        final String aktifitas = row['aktifitas'] ?? '-';
        final String notes = row['notes'] ?? '-';

        String rowBg = i.isEven ? '#FFFFFF' : '#F4F7FA';
        if (aktifitas == 'Libur') {
          rowBg = '#FFF8E1';
        } else if (aktifitas == 'Cuti/Izin') {
          rowBg = '#E8F5E9';
        } else if (aktifitas == 'Alpa') {
          rowBg = '#FFEBEE';
        }

        final int topRow = currentRow;
        final int bottomRow = currentRow + 1;

        // Nilai baris atas (check-in) untuk semua kolom
        final List<String> rowDataCheckIn = [
          row['day'] ?? '-',
          row['date'] ?? '-',
          row['work_hours'] ?? '-',
          row['check_in'] ?? '-',
          row['coordinate'] ?? '-',
          row['location'] ?? '-',
          lateStr,
          row['work_total'] ?? '-',
          aktifitas,
          notes,
        ];

        // Nilai baris bawah (check-out) hanya untuk kolom 3, 4, 5
        final Map<int, String> rowDataCheckOut = {
          3: row['check_out'] ?? '-',
          4: row['coordinate_out'] ?? '-',
          5: row['location_out'] ?? '-',
        };

        for (int c = 0; c < headers.length; c++) {
          final HorizontalAlign align = centerCols.contains(c)
              ? HorizontalAlign.Center
              : HorizontalAlign.Left;

          String fontHex = '#212121';
          bool isBold = false;
          if (c == 6 && lateStr != '-' && lateStr != '00:00:00') {
            fontHex = '#C62828';
            isBold = true;
          } else if (c == 9 && notes == 'Terlambat') {
            fontHex = '#C62828';
            isBold = true;
          } else if (c == 9 && notes == 'Cuti/Izin') {
            fontHex = '#2E7D32';
            isBold = true;
          }

          if (mergedCols.contains(c)) {
            // 1 sel setinggi 2 baris
            mergeCells(c, topRow, c, bottomRow);
            final style = buildBodyStyle(
              top: groupDividerBorder,
              bottom: groupDividerBorder,
              align: align,
              bgHex: rowBg,
              fontHex: fontHex,
              isBold: isBold,
            );
            putCell(c, topRow, rowDataCheckIn[c], style);
            styleCell(c, bottomRow, style);
          } else {
            putCell(
              c,
              topRow,
              rowDataCheckIn[c],
              buildBodyStyle(
                top: groupDividerBorder,
                bottom: innerDashedBorder,
                align: align,
                bgHex: rowBg,
                fontHex: fontHex,
                isBold: isBold,
              ),
            );
            putCell(
              c,
              bottomRow,
              rowDataCheckOut[c] ?? '-',
              buildBodyStyle(
                top: innerDashedBorder,
                bottom: groupDividerBorder,
                align: align,
                bgHex: rowBg,
              ),
            );
          }
        }

        sheetObject.setRowHeight(topRow, 19);
        sheetObject.setRowHeight(bottomRow, 19);
        currentRow += 2;
      }

      // ---- Ringkasan ----
      int th = totalDetikTerlambat ~/ 3600;
      int tm = (totalDetikTerlambat % 3600) ~/ 60;
      int ts = totalDetikTerlambat % 60;
      final String totalLateFormatted =
          '${th.toString().padLeft(2, '0')}:${tm.toString().padLeft(2, '0')}:${ts.toString().padLeft(2, '0')}';
      final String totalJamKerjaFormatted =
          _formatDurasi(_sumWorkSeconds(rows));

      currentRow++; // 1 baris kosong sebelum ringkasan
      addSummaryRow('Total Hari Kerja', '$totalHariKerja hari');
      addSummaryRow('Total Jam Terlambat', totalLateFormatted);
      addSummaryRow('Total Jam Kerja', totalJamKerjaFormatted);
    });

    final List<double> colWidths = [
      12, // 0: Hari
      15, // 1: Tanggal
      16, // 2: Jam Kerja
      24, // 3: Jam Check-in / Check-out
      26, // 4: Kordinat
      26, // 5: Nama Lokasi
      14, // 6: Terlambat
      18, // 7: Total Jam Kerja
      20, // 8: Aktifitas
      32, // 9: Notes
    ];
    for (int c = 0; c < colWidths.length; c++) {
      sheetObject.setColumnWidth(c, colWidths[c]);
    }

    final fileBytes = excel.encode();
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
                        final List<Map<String, dynamic>> allOptions = [
                          {
                            'id': 'all',
                            'full_name': 'Semua Karyawan',
                            'nik': 'ALL',
                            'jabatan_name': '-'
                          },
                          ..._employees,
                        ];

                        return allOptions.where((emp) {
                          if (_selectedDepartmentId != 'all' &&
                              emp['id'] != 'all') {
                            final empDeptId = emp['department_id']?.toString();
                            if (empDeptId != _selectedDepartmentId) {
                              return false;
                            }
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
                                                label: Text('Total Jam Kerja')),
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
                                                    row['work_total'] ?? '-')),
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
