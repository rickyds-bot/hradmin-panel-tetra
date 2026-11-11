import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

// Pustaka Export Excel, PDF, & Web Download Helper
import 'package:excel/excel.dart' as excel_lib;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
//import 'package:printing/printing.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

// Ringkasan perhitungan lembur setelah aturan (hanya pengajuan approved,
// minimal lembur, potongan istirahat, batas hitung 3 jam 30 menit, potongan terlambat).
// Semua dalam satuan menit.
class _LemburSummary {
  int rawWeekday = 0; // total hari biasa (approved) sebelum potongan
  int rawWeekend = 0; // total hari libur (approved) sebelum potongan
  int belowMinCount = 0; // jumlah pengajuan < minimal lembur (tidak dihitung)
  int belowMinMinutes = 0;
  int breakCount = 0; // jumlah potongan istirahat (kelipatan 4 jam)
  int breakMinutes = 0;
  int capCount = 0; // jumlah pengajuan yang kena batas 3 jam 30 menit
  int capMinutes = 0; // total menit kelebihan yang tidak dihitung
  int lateRaw = 0; // total menit terlambat hari biasa
  int lateApplied = 0; // menit terlambat yang benar-benar dikurangkan
  int pendingCount = 0; // pengajuan yang belum approved (belum dihitung)
  int pendingMinutes = 0;
  int rejectedCount = 0; // pengajuan ditolak (tidak dihitung)
  int rejectedMinutes = 0;
  int netWeekday = 0; // total hari biasa setelah potongan
  int netWeekend = 0; // total hari libur setelah aturan minimal lembur
}

// Hasil hitungan aturan lembur untuk satu pengajuan
class _ItemCalc {
  final int minutes; // durasi sesuai pengajuan
  final bool approved;
  final bool rejected;
  final bool libur; // Sabtu/Minggu/hari libur nasional
  final bool berlaku; // aturan lembur berlaku untuk jabatan ini
  int counted = 0; // menit yang dihitung
  int breakCount = 0; // jumlah potongan istirahat 30 menit
  int capMinutes =
      0; // menit kelebihan di atas batas hitung yang tidak dihitung
  bool belowMin = false;
  String? note; // catatan otomatis untuk kolom Notes

  _ItemCalc(
      this.minutes, this.approved, this.rejected, this.libur, this.berlaku);
}

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
  // Total menit terlambat hari biasa per karyawan dalam periode laporan
  Map<String, int> _lateMinutesByEmp = {};
  // Tanggal hari libur nasional (yyyy-MM-dd) pada periode laporan
  Set<String> _holidayDates = {};
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

      String cleanStr = dateStr;
      if (cleanStr.contains('+')) {
        cleanStr = cleanStr.substring(0, cleanStr.indexOf('+'));
      }
      cleanStr = cleanStr.replaceAll('Z', '');

      DateTime parsed = DateTime.parse(cleanStr);
      return parsed;
    } catch (_) {
      return null;
    }
  }

  String _formatTime(String? timestampStr) {
    if (timestampStr == null || timestampStr.isEmpty) return '-';
    try {
      DateTime? dt = _parseLocalDateTime(timestampStr);
      if (dt != null) {
        String twoDigits(int n) => n.toString().padLeft(2, '0');
        return '${twoDigits(dt.hour)}:${twoDigits(dt.minute)}';
      }
      return '-';
    } catch (_) {
      return '-';
    }
  }

  Future<void> _fetchLaporanLembur() async {
    setState(() => _isLoading = true);
    try {
      final startFilter =
          DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0);
      final endFilter =
          DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

      final startStr = startFilter.toIso8601String();
      final endStr = endFilter.toIso8601String();

      var query =
          Supabase.instance.client.from('overtime_requests').select('*');

      if (_selectedEmployee['id'] != 'all') {
        query = query.eq('employee_id', _selectedEmployee['id']);
      }

      // Filter berdasarkan waktu pelaksanaan lembur (start_time)
      final response = await query
          .gte('start_time', startStr)
          .lte('start_time', endStr)
          .order('start_time', ascending: true);

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
              final int totalMinutes = endDt.difference(startDt).inMinutes;
              newItem['duration_minutes'] = totalMinutes;
              newItem['duration_hours'] =
                  double.parse((totalMinutes / 60.0).toStringAsFixed(1));
            }
          }
        } catch (_) {}

        processedList.add(newItem);
      }

      await _loadHolidays();
      final lateMap = await _loadLateMinutes(processedList);

      setState(() {
        _laporanList = processedList;
        _lateMinutesByEmp = lateMap;
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

  // ===================== ATURAN LEMBUR =====================
  // Berlaku untuk semua jabatan kecuali CS & Security.
  static const List<String> _jabatanTanpaAturanLembur = ['security', 'cs'];
  static const int _minLemburMenit = 60; // minimal lembur
  static const int _intervalIstirahatMenit = 240; // tiap 4 jam lembur
  static const int _potonganIstirahatMenit = 30; // dikurangi 30 menit istirahat
  // Hari biasa: lembur kurang dari 4 jam maksimal dihitung 3 jam 30 menit
  // (mis. 3 jam 44 menit tetap dihitung 3 jam 30 menit)
  static const int _batasHitungMenit = 210;

  bool _aturanLemburBerlaku(dynamic jabatan) {
    final j = (jabatan ?? '').toString().trim().toLowerCase();
    return !_jabatanTanpaAturanLembur.contains(j);
  }

  // Driver, OB, CS masuk 08:00 (batas terlambat 08:15); lainnya masuk 08:30 (batas 08:45)
  bool _isDriverJabatan(dynamic jabatan) {
    final j = (jabatan ?? '').toString().trim().toLowerCase();
    return const ['driver', 'ob', 'cs'].contains(j);
  }

  // Hari libur = Sabtu/Minggu atau hari libur nasional (tabel hari_libur).
  // Lembur di hari libur tidak kena potongan istirahat & terlambat.
  bool _isHariLibur(dynamic item) {
    final d = _getDayName(item['start_time']).toLowerCase();
    if (d == 'sabtu' || d == 'minggu') return true;
    final dt = _parseLocalDateTime(item['start_time']?.toString());
    if (dt == null) return false;
    return _holidayDates.contains(DateFormat('yyyy-MM-dd').format(dt));
  }

  // Ambil daftar hari libur nasional pada periode laporan
  Future<void> _loadHolidays() async {
    try {
      final res = await Supabase.instance.client
          .from('hari_libur')
          .select('holiday_date')
          .gte('holiday_date', DateFormat('yyyy-MM-dd').format(_startDate))
          .lte('holiday_date', DateFormat('yyyy-MM-dd').format(_endDate));
      final Set<String> dates = {};
      for (var h in res) {
        final raw = h['holiday_date']?.toString();
        if (raw == null || raw.length < 10) continue;
        dates.add(raw.substring(0, 10));
      }
      _holidayDates = dates;
    } catch (e) {
      _holidayDates = {};
    }
  }

  // Jenis absen: 'in' (check-in), 'out' (check-out), atau null (sama dengan laporan absensi)
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

  // Ambil data attendance per halaman (batas 1000 baris per request)
  Future<List<Map<String, dynamic>>> _fetchAttendancePages(
      DateTime from, DateTime to,
      {dynamic employeeId}) async {
    final List<Map<String, dynamic>> all = [];
    const int pageSize = 1000;
    int offset = 0;
    while (true) {
      var q = Supabase.instance.client
          .from('attendance')
          .select('employee_id, status, created_at');
      if (employeeId != null) {
        q = q.eq('employee_id', employeeId);
      }
      final page = await q
          .gte('created_at', from.toUtc().toIso8601String())
          .lte('created_at', to.toUtc().toIso8601String())
          .order('created_at', ascending: true)
          .range(offset, offset + pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(page);
      all.addAll(rows);
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    return all;
  }

  // Hitung total menit terlambat hari biasa per karyawan (id -> menit).
  // Rumus sama dengan laporan absensi: terlambat dihitung dari batas toleransi
  // 15 menit (driver 08:15, lainnya 08:45); Sabtu/Minggu tidak dihitung.
  Future<Map<String, int>> _loadLateMinutes(List<dynamic> items) async {
    final Map<String, dynamic> eligible = {}; // id karyawan -> jabatan
    for (var item in items) {
      final empId = item['employee_id']?.toString();
      if (empId == null) continue;
      final jabatan = (item['employees'] ?? {})['jabatan_name'];
      if (_aturanLemburBerlaku(jabatan)) eligible[empId] = jabatan;
    }
    if (eligible.isEmpty) return {};

    try {
      final from = DateTime(_startDate.year, _startDate.month, _startDate.day);
      final to =
          DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
      final rows = await _fetchAttendancePages(from, to,
          employeeId: _selectedEmployee['id'] == 'all'
              ? null
              : _selectedEmployee['id']);

      // Check-in pertama tiap karyawan per tanggal
      final Map<String, Map<String, DateTime>> firstIn = {};
      for (var r in rows) {
        final empId = r['employee_id']?.toString();
        if (empId == null || !eligible.containsKey(empId)) continue;
        if (_punchKind(r) != 'in') continue;
        final dt =
            DateTime.tryParse(r['created_at']?.toString() ?? '')?.toLocal();
        if (dt == null) continue;
        final key = DateFormat('yyyy-MM-dd').format(dt);
        final byDate = firstIn.putIfAbsent(empId, () => {});
        final existing = byDate[key];
        if (existing == null || dt.isBefore(existing)) byDate[key] = dt;
      }

      final Map<String, int> result = {};
      firstIn.forEach((empId, byDate) {
        final bool isDriver = _isDriverJabatan(eligible[empId]);
        int seconds = 0;
        byDate.forEach((dateKey, checkIn) {
          // Sabtu/Minggu & hari libur nasional tidak dihitung terlambat
          if (checkIn.weekday == DateTime.saturday ||
              checkIn.weekday == DateTime.sunday ||
              _holidayDates.contains(dateKey)) {
            return;
          }
          final limit = DateTime(
              checkIn.year, checkIn.month, checkIn.day, 8, isDriver ? 15 : 45);
          if (checkIn.isAfter(limit)) {
            seconds += checkIn.difference(limit).inSeconds;
          }
        });
        result[empId] = seconds ~/ 60;
      });
      return result;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Gagal memuat data keterlambatan: $e',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              backgroundColor: Colors.orange),
        );
      }
      return {};
    }
  }

  // Terapkan aturan lembur ke satu pengajuan
  _ItemCalc _calcItem(dynamic item) {
    final int minutes =
        int.tryParse(item['duration_minutes']?.toString() ?? '0') ?? 0;
    final String status =
        (item['status'] ?? 'pending').toString().trim().toLowerCase();
    final bool approved = status == 'approved' || status == 'disetujui';
    final bool rejected = status == 'rejected' || status == 'ditolak';
    final c = _ItemCalc(
      minutes,
      approved,
      rejected,
      _isHariLibur(item),
      _aturanLemburBerlaku((item['employees'] ?? {})['jabatan_name']),
    );

    // Hanya pengajuan yang sudah approved yang dihitung
    if (!approved) {
      c.note = rejected
          ? 'Ditolak, tidak dihitung'
          : 'Menunggu approval, belum dihitung';
      return c;
    }

    c.counted = minutes;
    if (!c.berlaku) return c;

    if (minutes < _minLemburMenit) {
      // Lembur di bawah minimal tidak dihitung
      c.belowMin = true;
      c.counted = 0;
      c.note = 'Kurang dari $_minLemburMenit menit, tidak dihitung';
      return c;
    }

    if (!c.libur) {
      // Hari biasa: lembur kurang dari 4 jam maksimal dihitung 3 jam 30 menit;
      // mulai 4 jam, tiap kelipatan 4 jam dikurangi 30 menit istirahat
      final int blok = minutes ~/ _intervalIstirahatMenit;
      c.breakCount = blok;
      if (blok == 0) {
        c.counted = minutes > _batasHitungMenit ? _batasHitungMenit : minutes;
        c.capMinutes = minutes - c.counted;
        if (c.capMinutes > 0) {
          c.note =
              'Lebih dari ${_formatDuration(_batasHitungMenit)}, dihitung ${_formatDuration(_batasHitungMenit)}';
        }
      } else {
        c.counted = minutes - (blok * _potonganIstirahatMenit);
      }
    }
    return c;
  }

  // Isi kolom Notes: catatan HR/admin + catatan otomatis perhitungan lembur
  String _notesText(dynamic item) {
    final parts = <String>[];
    final hr = (item['notes'] ?? '').toString().trim();
    if (hr.isNotEmpty && hr != 'null') parts.add(hr);
    final auto = _calcItem(item).note;
    if (auto != null) parts.add(auto);
    return parts.isEmpty ? '-' : parts.join(' | ');
  }

  // Terapkan aturan lembur ke seluruh data laporan
  _LemburSummary _buildSummary() {
    final s = _LemburSummary();
    final Map<String, int> weekdayByEmp = {};
    final Map<String, bool> ruleByEmp = {};

    for (var item in _laporanList) {
      final c = _calcItem(item);
      final String empId = item['employee_id']?.toString() ?? '-';

      // Pengajuan yang belum approved / ditolak tidak ikut dihitung
      if (!c.approved) {
        if (c.rejected) {
          s.rejectedCount++;
          s.rejectedMinutes += c.minutes;
        } else {
          s.pendingCount++;
          s.pendingMinutes += c.minutes;
        }
        continue;
      }

      if (c.libur) {
        s.rawWeekend += c.minutes;
      } else {
        s.rawWeekday += c.minutes;
      }

      if (c.belowMin) {
        s.belowMinCount++;
        s.belowMinMinutes += c.minutes;
      }
      s.breakCount += c.breakCount;
      s.breakMinutes += c.breakCount * _potonganIstirahatMenit;
      if (c.capMinutes > 0) {
        s.capCount++;
        s.capMinutes += c.capMinutes;
      }

      if (c.libur) {
        s.netWeekend += c.counted;
      } else {
        weekdayByEmp[empId] = (weekdayByEmp[empId] ?? 0) + c.counted;
        if (c.berlaku) ruleByEmp[empId] = true;
      }
    }

    // Menit terlambat mengurangi total lembur hari biasa (per karyawan, min 0)
    weekdayByEmp.forEach((empId, counted) {
      int deduct = 0;
      if (ruleByEmp[empId] == true) {
        final int late = _lateMinutesByEmp[empId] ?? 0;
        s.lateRaw += late;
        deduct = late < counted ? late : counted;
        s.lateApplied += deduct;
      }
      s.netWeekday += counted - deduct;
    });

    return s;
  }

  // Catatan potongan yang ditampilkan di bawah laporan
  List<String> _catatanLines(_LemburSummary s) {
    final lines = <String>[];
    if (s.rawWeekday != s.netWeekday) {
      lines.add(
          'Total lembur (hari biasa) sebelum potongan: ${_formatDuration(s.rawWeekday)}');
    }
    if (s.belowMinCount > 0) {
      lines.add(
          'Lembur kurang dari $_minLemburMenit menit tidak dihitung: ${s.belowMinCount} pengajuan (${_formatDuration(s.belowMinMinutes)})');
    }
    if (s.breakCount > 0) {
      lines.add(
          'Potongan istirahat (hari biasa): ${s.breakCount} x $_potonganIstirahatMenit menit = ${_formatDuration(s.breakMinutes)}');
    }
    if (s.capCount > 0) {
      lines.add(
          'Batas hitung ${_formatDuration(_batasHitungMenit)} untuk lembur kurang dari 4 jam (hari biasa): ${s.capCount} pengajuan, kelebihan ${_formatDuration(s.capMinutes)} tidak dihitung');
    }
    if (s.lateRaw > 0) {
      var t =
          'Potongan terlambat (hari biasa): ${_formatDuration(s.lateApplied)}';
      if (s.lateRaw > s.lateApplied) {
        t +=
            ' (total terlambat ${_formatDuration(s.lateRaw)}, sisanya tidak dapat dikurangkan)';
      }
      lines.add(t);
    }
    if (s.pendingCount > 0) {
      lines.add(
          'Belum approved (belum dihitung): ${s.pendingCount} pengajuan (${_formatDuration(s.pendingMinutes)})');
    }
    if (s.rejectedCount > 0) {
      lines.add(
          'Ditolak (tidak dihitung): ${s.rejectedCount} pengajuan (${_formatDuration(s.rejectedMinutes)})');
    }
    return lines;
  }

  // Ubah total menit menjadi teks, contoh: 90 -> "1 Jam 30 Menit"
  String _formatDuration(dynamic minutesValue) {
    if (minutesValue == null) return '-';
    final int totalMinutes = minutesValue is num
        ? minutesValue.round()
        : (int.tryParse(minutesValue.toString()) ?? 0);
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;
    if (hours == 0 && minutes == 0) return '0 Menit';
    if (hours == 0) return '$minutes Menit';
    if (minutes == 0) return '$hours Jam';
    return '$hours Jam $minutes Menit';
  }

  // Total (menit) setelah aturan lembur diterapkan
  Map<String, int> _calculateTotalMinutes() {
    final s = _buildSummary();
    return {'weekday': s.netWeekday, 'weekend': s.netWeekend};
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
      excel_lib.TextCellValue('Notes'),
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
        excel_lib.TextCellValue(_formatDuration(item['duration_minutes'])),
        excel_lib.TextCellValue(item['status'] ?? 'Pending'),
        excel_lib.TextCellValue(approver),
        excel_lib.TextCellValue(_notesText(item)),
      ]);
    }

    final totals = _calculateTotalMinutes();

    List<excel_lib.CellValue?> totalRow = List.filled(11, null);
    totalRow[6] = excel_lib.TextCellValue('Total Jam Lembur:');
    totalRow[7] = excel_lib.TextCellValue(_formatDuration(totals['weekday']));
    sheet.appendRow(totalRow);

    List<excel_lib.CellValue?> totalWeekendRow = List.filled(11, null);
    totalWeekendRow[6] =
        excel_lib.TextCellValue('Total Jam Lembur (Hari Libur):');
    totalWeekendRow[7] =
        excel_lib.TextCellValue(_formatDuration(totals['weekend']));
    sheet.appendRow(totalWeekendRow);

    final catatan = _catatanLines(_buildSummary());
    if (catatan.isNotEmpty) {
      sheet.appendRow(List<excel_lib.CellValue?>.filled(11, null));
      List<excel_lib.CellValue?> catatanHeader = List.filled(11, null);
      catatanHeader[6] = excel_lib.TextCellValue('Catatan:');
      sheet.appendRow(catatanHeader);
      for (final line in catatan) {
        List<excel_lib.CellValue?> noteRow = List.filled(11, null);
        noteRow[6] = excel_lib.TextCellValue(line);
        sheet.appendRow(noteRow);
      }
    }

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
    final totals = _calculateTotalMinutes();
    final catatan = _catatanLines(_buildSummary());

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
                'Notes'
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
                  _formatDuration(item['duration_minutes']),
                  item['status'] ?? 'Pending',
                  approver,
                  _notesText(item),
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
                10: const pw.FlexColumnWidth(1.2),
              },
            ),
            pw.SizedBox(height: 11),
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
                        'Total Jam Lembur: ${_formatDuration(totals['weekday'])}',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      child: pw.Text(
                        'Total Jam Lembur (Hari Libur): ${_formatDuration(totals['weekend'])}',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    if (catatan.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      pw.Text('Catatan:',
                          style: pw.TextStyle(
                              fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      ...catatan.map((line) => pw.Text(line,
                          style: const pw.TextStyle(fontSize: 9))),
                    ],
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
    final totals = _calculateTotalMinutes();
    final catatan = _catatanLines(_buildSummary());

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
                                          DataColumn(label: Text('Notes')),
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
                                              status == 'disetujui') {
                                            badgeColor = Colors.green;
                                          } else if (status == 'rejected' ||
                                              status == 'ditolak') {
                                            badgeColor = Colors.red;
                                          }

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
                                              DataCell(Text(_formatDuration(
                                                  item['duration_minutes']))),
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
                                              DataCell(SizedBox(
                                                width: 260,
                                                child: Tooltip(
                                                  message: _notesText(item),
                                                  child: Text(
                                                    _notesText(item),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              )),
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
                            'Total Jam Lembur: ${_formatDuration(totals['weekday'])}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[900],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total Jam Lembur (Hari Libur): ${_formatDuration(totals['weekend'])}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[900],
                            ),
                          ),
                          if (catatan.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Catatan:',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                            for (final line in catatan)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  line,
                                  textAlign: TextAlign.end,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                          ],
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
