import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

class WebDashboardContent extends StatefulWidget {
  const WebDashboardContent({super.key});

  @override
  State<WebDashboardContent> createState() => _WebDashboardContentState();
}

class _WebDashboardContentState extends State<WebDashboardContent> {
  bool _isLoading = true;

  // Statistik Utama
  int _totalKaryawan = 0;
  int _totalLakiLaki = 0;
  int _totalPerempuan = 0;
  int _totalTetap = 0;
  int _totalKontrak = 0;
  int _totalMagang = 0;
  int _totalHadirHariIni = 0;
  int _totalTidakHadirHariIni = 0;
  List<Map<String, dynamic>> _tidakHadirList = [];
  int _totalCutiHariIni = 0;
  int _totalPendingLembur = 0;

  // Data Grafik (Dot Chart Custom)
  List<Map<String, dynamic>> _dotChartData = [];

  // Data Kalender & Hari Libur
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final Map<String, String> _holidaysMap = {};

  // Variabel untuk Karyawan Kontrak
  List<Map<String, dynamic>> _expiringContracts = [];

  // =========================================================
  // Variabel Baru Khusus Top 10 Karyawan Paling Tepat Waktu
  // =========================================================
  List<Map<String, dynamic>> _topEmployees = [];
  String _topEmployeesPeriod = '';
  DateTime _top10CurrentDate =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _isLoadingTop10 = false;

  // Top 10 Paling Sering Terlambat (navigasi bulan sendiri)
  List<Map<String, dynamic>> _topLateEmployees = [];
  String _topLatePeriod = '';
  DateTime _topLateCurrentDate =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _isLoadingTopLate = false;
  List<dynamic> _nonAdminIds = [];

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Ambil data hari libur dari Supabase
      final holidaysRes = await Supabase.instance.client
          .from('hari_libur')
          .select('holiday_date, description');

      _holidaysMap.clear();
      for (var h in holidaysRes) {
        if (h['holiday_date'] != null) {
          String rawDate = h['holiday_date'].toString();
          String dateKey = rawDate.contains('T')
              ? rawDate.split('T')[0]
              : rawDate.substring(0, 10);

          _holidaysMap[dateKey] = h['description'] ?? 'Libur Nasional';
        }
      }

      // 2. Ambil data karyawan
      final karyawanRes = await Supabase.instance.client.from('employees').select(
          'id, full_name, gender, employee_status, role, contract_number, contract_end, is_active, jabatan_name');

      int l = 0, p = 0, tetap = 0, kontrak = 0, magang = 0;
      _nonAdminIds.clear();
      List<Map<String, dynamic>> tempExpiring = [];
      final List<Map<String, dynamic>> activeEmps = [];

      final DateTime now = DateTime.now();
      final DateTime todayLocal = DateTime(now.year, now.month, now.day);

      for (var emp in karyawanRes) {
        final role = (emp['role'] ?? '').toString().trim().toLowerCase();
        if (role == 'admin') continue;

        _nonAdminIds.add(emp['id']);

        // Karyawan non-aktif tidak ikut dihitung sebagai "tidak hadir"
        if (emp['is_active'] != false) {
          activeEmps.add({
            'id': emp['id'],
            'name': emp['full_name'] ?? 'Tanpa Nama',
            'jabatan': (emp['jabatan_name'] ?? '-').toString(),
          });
        }

        final gender = (emp['gender'] ?? '').toString().trim().toLowerCase();
        if (gender == 'l' ||
            gender.contains('laki') ||
            gender == 'male' ||
            gender == 'pria') {
          l++;
        } else if (gender == 'p' ||
            gender.contains('perempuan') ||
            gender == 'female' ||
            gender == 'wanita') {
          p++;
        }

        final empStatus =
            (emp['employee_status'] ?? '').toString().trim().toLowerCase();
        if (empStatus == 'tetap') {
          tetap++;
        } else if (empStatus == 'kontrak') {
          kontrak++;
          if (emp['contract_end'] != null) {
            try {
              DateTime endDate = DateTime.parse(emp['contract_end'].toString());
              DateTime endDay =
                  DateTime(endDate.year, endDate.month, endDate.day);
              int diffDays = endDay.difference(todayLocal).inDays;

              if (diffDays <= 30) {
                tempExpiring.add({
                  'name': emp['full_name'] ?? 'Tanpa Nama',
                  'contract_number': emp['contract_number'] ?? '-',
                  'end_date': emp['contract_end'],
                  'diff_days': diffDays,
                });
              }
            } catch (_) {}
          }
        } else if (empStatus == 'magang') {
          magang++;
        }
      }

      tempExpiring.sort((a, b) => a['diff_days'].compareTo(b['diff_days']));
      _expiringContracts = tempExpiring;

      _totalKaryawan = _nonAdminIds.length;
      _totalLakiLaki = l;
      _totalPerempuan = p;
      _totalTetap = tetap;
      _totalKontrak = kontrak;
      _totalMagang = magang;

      // 3. Absen Hari Ini (Check-In)
      final String startOfTodayUtcStr = todayLocal.toUtc().toIso8601String();
      final absensiRes = await Supabase.instance.client
          .from('attendance')
          .select('employee_id')
          .gte('created_at', startOfTodayUtcStr);

      Set uniqueHadir = absensiRes
          .map((e) => e['employee_id'])
          .where((id) => _nonAdminIds.contains(id))
          .toSet();
      _totalHadirHariIni = uniqueHadir.length;

      // 4. Cuti Hari Ini
      final todayStr = todayLocal.toIso8601String().split('T')[0];
      final cutiRes = await Supabase.instance.client
          .from('leave_requests')
          .select('employee_id')
          .eq('status', 'approved')
          .lte('start_date', todayStr)
          .gte('end_date', todayStr);

      _totalCutiHariIni =
          cutiRes.where((e) => _nonAdminIds.contains(e['employee_id'])).length;

      // 4.5 Karyawan aktif yang belum check-in hari ini
      final Set cutiIds = cutiRes.map((e) => e['employee_id']).toSet();
      final tidakHadir = activeEmps
          .where((e) => !uniqueHadir.contains(e['id']))
          .map((e) => {
                'name': e['name'],
                'jabatan': e['jabatan'],
                'on_leave': cutiIds.contains(e['id']),
              })
          .toList();
      tidakHadir.sort((a, b) => a['name']
          .toString()
          .toLowerCase()
          .compareTo(b['name'].toString().toLowerCase()));
      _tidakHadirList = tidakHadir;
      _totalTidakHadirHariIni = tidakHadir.length;

      // 5. Lembur Pending
      final lemburRes = await Supabase.instance.client
          .from('overtime_requests')
          .select('employee_id')
          .eq('status', 'pending');

      _totalPendingLembur = lemburRes
          .where((e) => _nonAdminIds.contains(e['employee_id']))
          .length;

      // 6. Data Grafik Tren Kehadiran
      await _fetchChartData(_nonAdminIds);

      // 7. Ambil Data Top 10 Paling Tepat Waktu
      await _fetchTop10Data();

      // 8. Top 10 Paling Sering Terlambat
      await _fetchTopLateData();
    } catch (e) {
      debugPrint('Error fetching dashboard stats: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchTop10Data() async {
    setState(() => _isLoadingTop10 = true);
    try {
      DateTime firstDay =
          DateTime(_top10CurrentDate.year, _top10CurrentDate.month, 1);
      DateTime lastDay = DateTime(
          _top10CurrentDate.year, _top10CurrentDate.month + 1, 0, 23, 59, 59);

      String startUtc = firstDay.toUtc().toIso8601String();
      String endUtc = lastDay.toUtc().toIso8601String();

      const List<String> namaBulan = [
        'Januari',
        'Februari',
        'Maret',
        'April',
        'Mei',
        'Juni',
        'Juli',
        'Agustus',
        'September',
        'Oktober',
        'November',
        'Desember'
      ];
      _topEmployeesPeriod = '${namaBulan[firstDay.month - 1]} ${firstDay.year}';

      final empRes = await Supabase.instance.client
          .from('employees')
          .select('id, jabatan_name');

      List<dynamic> excludedIds = [];
      for (var e in empRes) {
        String jab = (e['jabatan_name'] ?? '').toString().toLowerCase().trim();
        if (jab == 'driver' ||
            jab == 'ob' ||
            jab == 'cs' ||
            jab == 'security' ||
            jab == 'cleaning service') {
          excludedIds.add(e['id']);
        }
      }

      final allAttRes = await Supabase.instance.client
          .from('attendance')
          .select('employee_id, created_at, status')
          .gte('created_at', startUtc)
          .lte('created_at', endUtc);

      Map<String, int> onTimeCounts = {};

      for (var r in allAttRes) {
        final eId = r['employee_id'];

        if ((r['status'] ?? '').toString().toLowerCase().contains('out')) {
          continue;
        }

        if (_nonAdminIds.contains(eId) && !excludedIds.contains(eId)) {
          final String eIdStr = eId.toString();
          final createdAtStr = r['created_at'];

          if (createdAtStr != null) {
            try {
              DateTime checkInTimeLocal =
                  DateTime.parse(createdAtStr.toString()).toLocal();
              int totalMinutes =
                  checkInTimeLocal.hour * 60 + checkInTimeLocal.minute;
              const int limitMinutes = 8 * 60 + 45;

              if (totalMinutes <= limitMinutes) {
                onTimeCounts[eIdStr] = (onTimeCounts[eIdStr] ?? 0) + 1;
              }
            } catch (_) {}
          }
        }
      }

      var sortedKeys = onTimeCounts.keys.toList()
        ..sort((a, b) => onTimeCounts[b]!.compareTo(onTimeCounts[a]!));

      var top10Keys = sortedKeys.take(10).toList();

      if (top10Keys.isNotEmpty) {
        final topEmpData = await Supabase.instance.client
            .from('employees')
            .select('id, full_name, photo_url, jabatan_name')
            .inFilter('id', top10Keys);

        List<Map<String, dynamic>> tempTop = [];
        for (var key in top10Keys) {
          var emp = topEmpData.firstWhere((e) => e['id'].toString() == key,
              orElse: () => <String, dynamic>{});
          if (emp.isNotEmpty) {
            tempTop.add({
              'name': emp['full_name'] ?? 'Karyawan',
              'photo': emp['photo_url'],
              'count': '${onTimeCounts[key]} Tepat Waktu'
            });
          }
        }
        _topEmployees = tempTop;
      } else {
        _topEmployees = [];
      }
    } catch (e) {
      debugPrint('Error fetching top 10 stats: $e');
    } finally {
      if (mounted) setState(() => _isLoadingTop10 = false);
    }
  }

  static const List<String> _namaBulanTop = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember'
  ];

  Future<void> _fetchTopLateData() async {
    setState(() => _isLoadingTopLate = true);
    try {
      final firstDay =
          DateTime(_topLateCurrentDate.year, _topLateCurrentDate.month, 1);
      final lastDay = DateTime(_topLateCurrentDate.year,
          _topLateCurrentDate.month + 1, 0, 23, 59, 59);
      _topLatePeriod = '${_namaBulanTop[firstDay.month - 1]} ${firstDay.year}';

      final empRes = await Supabase.instance.client
          .from('employees')
          .select('id, jabatan_name');
      final Set<dynamic> excludedIds = {};
      for (var e in empRes) {
        final jab = (e['jabatan_name'] ?? '').toString().toLowerCase().trim();
        if (jab == 'driver' ||
            jab == 'ob' ||
            jab == 'cs' ||
            jab == 'security' ||
            jab == 'cleaning service') {
          excludedIds.add(e['id']);
        }
      }

      final attRes = await Supabase.instance.client
          .from('attendance')
          .select('employee_id, created_at, status')
          .gte('created_at', firstDay.toUtc().toIso8601String())
          .lte('created_at', lastDay.toUtc().toIso8601String());

      final Map<String, Map<String, int>> firstCheckIn = {};
      for (var r in attRes) {
        final eId = r['employee_id'];
        if (!_nonAdminIds.contains(eId) || excludedIds.contains(eId)) continue;

        if ((r['status'] ?? '').toString().toLowerCase().contains('out')) {
          continue;
        }
        final createdAt = r['created_at'];
        if (createdAt == null) continue;

        DateTime t;
        try {
          t = DateTime.parse(createdAt.toString()).toLocal();
        } catch (_) {
          continue;
        }

        final bool isWeekend =
            t.weekday == DateTime.saturday || t.weekday == DateTime.sunday;
        final String dateKey = DateFormat('yyyy-MM-dd').format(t);
        if (isWeekend || _holidaysMap.containsKey(dateKey)) continue;

        final int minutes = t.hour * 60 + t.minute;
        final days = firstCheckIn.putIfAbsent(eId.toString(), () => {});
        if (!days.containsKey(dateKey) || minutes < days[dateKey]!) {
          days[dateKey] = minutes;
        }
      }

      const int limitMinutes = 8 * 60 + 45;
      final Map<String, int> lateCounts = {};
      firstCheckIn.forEach((eId, days) {
        final n = days.values.where((m) => m > limitMinutes).length;
        if (n > 0) lateCounts[eId] = n;
      });

      final sortedKeys = lateCounts.keys.toList()
        ..sort((a, b) => lateCounts[b]!.compareTo(lateCounts[a]!));
      final top10Keys = sortedKeys.take(10).toList();

      if (top10Keys.isNotEmpty) {
        final topEmpData = await Supabase.instance.client
            .from('employees')
            .select('id, full_name, photo_url, jabatan_name')
            .inFilter('id', top10Keys);

        final List<Map<String, dynamic>> tempTop = [];
        for (var key in top10Keys) {
          final emp = topEmpData.firstWhere((e) => e['id'].toString() == key,
              orElse: () => <String, dynamic>{});
          if (emp.isNotEmpty) {
            tempTop.add({
              'name': emp['full_name'] ?? 'Karyawan',
              'photo': emp['photo_url'],
              'count': '${lateCounts[key]}x Terlambat'
            });
          }
        }
        _topLateEmployees = tempTop;
      } else {
        _topLateEmployees = [];
      }
    } catch (e) {
      debugPrint('Error fetching top late stats: $e');
    } finally {
      if (mounted) setState(() => _isLoadingTopLate = false);
    }
  }

  static const int _chartDaysRange = 12;

  Future<void> _fetchChartData(List<dynamic> validIds) async {
    final now = DateTime.now();
    final startOfRangeLocal = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: _chartDaysRange - 1));
    final startOfRangeUtcStr = startOfRangeLocal.toUtc().toIso8601String();

    final weeklyRes = await Supabase.instance.client
        .from('attendance')
        .select('employee_id, created_at, status')
        .gte('created_at', startOfRangeUtcStr);

    Map<String, Map<String, Set<dynamic>>> dailyData = {};
    for (int i = 0; i < _chartDaysRange; i++) {
      final d = startOfRangeLocal.add(Duration(days: i));
      dailyData[DateFormat('yyyy-MM-dd').format(d)] = {
        'tepat_waktu': <dynamic>{},
        'terlambat': <dynamic>{},
      };
    }

    for (var row in weeklyRes) {
      final empId = row['employee_id'];
      if (!validIds.contains(empId)) continue;

      if ((row['status'] ?? '').toString().toLowerCase().contains('out'))
        continue;

      final createdAt = row['created_at'];
      if (createdAt != null) {
        try {
          DateTime localDate = DateTime.parse(createdAt.toString()).toLocal();
          final dateStr = DateFormat('yyyy-MM-dd').format(localDate);

          if (dailyData.containsKey(dateStr)) {
            int totalMinutes = localDate.hour * 60 + localDate.minute;
            const int limitMinutes = 8 * 60 + 45;

            if (totalMinutes <= limitMinutes) {
              dailyData[dateStr]!['tepat_waktu']!.add(empId);
            } else {
              dailyData[dateStr]!['terlambat']!.add(empId);
            }
          }
        } catch (_) {}
      }
    }

    List<Map<String, dynamic>> tempDotData = [];

    dailyData.forEach((dateStr, stats) {
      final double countTepat = stats['tepat_waktu']!.length.toDouble();
      final double countTelat = stats['terlambat']!.length.toDouble();
      final double countTotalHadir = countTepat + countTelat;

      final dateObj = DateTime.parse(dateStr);
      bool isWeekend = dateObj.weekday == DateTime.saturday ||
          dateObj.weekday == DateTime.sunday;
      bool isHoliday = _holidaysMap.containsKey(dateStr);

      double countAbsen = 0;
      if (!isWeekend && !isHoliday) {
        countAbsen = (_totalKaryawan - countTotalHadir).toDouble();
        if (countAbsen < 0) countAbsen = 0;
      }

      const List<String> bulanIndoSingkat = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'Mei',
        'Jun',
        'Jul',
        'Agt',
        'Sep',
        'Okt',
        'Nov',
        'Des'
      ];
      String tgl =
          dateObj.day.toString().padLeft(2, '0'); // Contoh format: 01, 09, 15
      String bln = bulanIndoSingkat[dateObj.month - 1];

      tempDotData.add({
        'dateLabel': '$tgl $bln',
        'absen': countAbsen,
        'telat': countTelat,
        'tepat': countTepat,
        'hadir': countTotalHadir,
        'total': _totalKaryawan.toDouble(),
      });
    });

    _dotChartData = tempDotData;
  }

  bool _isPublicHoliday(DateTime day) {
    String dateKey = DateFormat('yyyy-MM-dd').format(day);
    return _holidaysMap.containsKey(dateKey);
  }

  String? _getHolidayDescription(DateTime day) {
    String dateKey = DateFormat('yyyy-MM-dd').format(day);
    return _holidaysMap[dateKey];
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dashboard Overview',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ringkasan data operasional HR Tetra.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _fetchDashboardData,
                      tooltip: 'Refresh Data',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: Colors.grey[200]!),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Grid Kartu Statistik Utama
                LayoutBuilder(
                  builder: (context, constraints) {
                    double width = (constraints.maxWidth - 36) / 4;
                    if (constraints.maxWidth < 800) {
                      width = (constraints.maxWidth - 12) / 2;
                    }
                    if (constraints.maxWidth < 500) {
                      width = constraints.maxWidth;
                    }

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildStatCard(
                            'Total Karyawan',
                            _totalKaryawan.toString(),
                            'L: $_totalLakiLaki | P: $_totalPerempuan',
                            Icons.people_outline,
                            Colors.blue,
                            width),
                        _buildStatCard(
                            'Karyawan Tetap',
                            _totalTetap.toString(),
                            'Status: Tetap',
                            Icons.verified_user_outlined,
                            Colors.indigo,
                            width),
                        _buildStatCard(
                            'Karyawan Kontrak',
                            _totalKontrak.toString(),
                            'Status: Kontrak',
                            Icons.assignment_ind_outlined,
                            Colors.teal,
                            width),
                        _buildStatCard(
                            'Karyawan Magang',
                            _totalMagang.toString(),
                            'Status: Magang',
                            Icons.school_outlined,
                            Colors.brown,
                            width),
                        _buildStatCard(
                            'Hadir Hari Ini',
                            _totalHadirHariIni.toString(),
                            'Tercatat masuk sistem',
                            Icons.how_to_reg_outlined,
                            Colors.green,
                            width),
                        _buildStatCard(
                          'Tidak Hadir Hari Ini',
                          _totalTidakHadirHariIni.toString(),
                          'Belum check-in (klik lihat nama)',
                          Icons.person_off_outlined,
                          Colors.red,
                          width,
                          onTap: _showTidakHadirDialog,
                        ),
                        _buildStatCard(
                            'Cuti / Izin Aktif',
                            _totalCutiHariIni.toString(),
                            'Disetujui hari ini',
                            Icons.event_busy_outlined,
                            Colors.orange,
                            width),
                        _buildStatCard(
                            'Lembur Pending',
                            _totalPendingLembur.toString(),
                            'Menunggu approval',
                            Icons.timer_outlined,
                            Colors.purple,
                            width),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Layout Utama
                LayoutBuilder(
                  builder: (context, constraints) {
                    bool isWide = constraints.maxWidth > 900;

                    Widget chartSection = Container(
                      width: isWide ? null : constraints.maxWidth,
                      height: 400,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.indigo[50],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.bar_chart_rounded,
                                    color: Colors.indigo[600], size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Grafik Tren Kehadiran',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        color: const Color(0xFF1E293B),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$_chartDaysRange Hari Terakhir',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // BAGIAN LEGEND:
                              Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                alignment: WrapAlignment.end,
                                children: [
                                  _buildChartLegend(
                                      const Color(0xFF3B82F6), 'Tidak Hadir'),
                                  _buildChartLegend(
                                      const Color(0xFFF59E0B), 'Terlambat'),
                                  _buildChartLegend(
                                      const Color(0xFF10B981), 'Tepat Waktu'),
                                  _buildChartLegend(
                                      const Color(0xFF8B5CF6), 'Total Hadir'),
                                  _buildChartLegend(
                                      Colors.grey[300]!, 'Total Karyawan'),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Divider(height: 1, color: Colors.grey[100]),
                          const SizedBox(height: 20),
                          Expanded(child: _buildDotAttendanceChart()),
                        ],
                      ),
                    );

                    Widget calendarSection = Container(
                      width: isWide ? null : constraints.maxWidth,
                      height: 400,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCalendar(),
                          if (_selectedDay != null &&
                              _getHolidayDescription(_selectedDay!) != null)
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.red[200]!),
                                ),
                                child: Text(
                                  'Libur: ${_getHolidayDescription(_selectedDay!)}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red[800],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );

                    if (isWide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          chartSection,
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildTopEmployeesCard()),
                              const SizedBox(width: 16),
                              Expanded(child: _buildTopLateCard()),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  flex: 1,
                                  child: _buildExpiringContractsCard()),
                              const SizedBox(width: 16),
                              Expanded(flex: 1, child: calendarSection),
                            ],
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          chartSection,
                          const SizedBox(height: 16),
                          _buildTopEmployeesCard(),
                          const SizedBox(height: 16),
                          _buildTopLateCard(),
                          const SizedBox(height: 16),
                          _buildExpiringContractsCard(),
                          const SizedBox(height: 16),
                          calendarSection,
                        ],
                      );
                    }
                  },
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  // Helper Komponen Chart Legend
  Widget _buildChartLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: Colors.grey[600],
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // KOMPONEN GRAFIK DOT-CHART CUSTOM BARU
  // =========================================================
  Widget _buildDotAttendanceChart() {
    if (_dotChartData.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 8, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _dotChartData.map((data) {
          return Tooltip(
            message: '${data['dateLabel']}\n'
                'Tidak Hadir: ${data['absen'].toInt()}\n'
                'Terlambat: ${data['telat'].toInt()}\n'
                'Tepat Waktu: ${data['tepat'].toInt()}\n'
                'Total Hadir: ${data['hadir'].toInt()}\n'
                'Total Karyawan: ${data['total'].toInt()}',
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey[900],
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 12,
              height: 1.5,
            ),
            preferBelow: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildSingleDotBar(data['absen'], data['total'],
                          const Color(0xFF3B82F6)),
                      const SizedBox(width: 4),
                      _buildSingleDotBar(data['telat'], data['total'],
                          const Color(0xFFF59E0B)),
                      const SizedBox(width: 4),
                      _buildSingleDotBar(data['tepat'], data['total'],
                          const Color(0xFF10B981)),
                      const SizedBox(width: 4),
                      _buildSingleDotBar(data['hadir'], data['total'],
                          const Color(0xFF8B5CF6)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  data['dateLabel'],
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // Builder untuk satu tiang/kolom kotak
  Widget _buildSingleDotBar(double value, double total, Color activeColor) {
    int maxVerticalDots = 18; // Menentukan tinggi maksimal kotak agar proporsional
    int actualDots = total > maxVerticalDots ? maxVerticalDots : total.toInt();
    if (actualDots <= 0) actualDots = 1; // Mencegah eror kalkulasi jika total=0

    double scale = actualDots / (total <= 0 ? 1 : total);
    int activeDotsCount = (value * scale).round();

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: List.generate(actualDots, (index) {
        // Render dari bawah ke atas
        int reverseIndex = actualDots - 1 - index;
        bool isActive = reverseIndex < activeDotsCount;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2.5),
          width: 8, // Lebar kotak
          height: 8, // Tinggi kotak
          decoration: BoxDecoration(
            color: isActive ? activeColor : Colors.grey[200],
            // Hapus shape: BoxShape.circle, lalu gunakan borderRadius agar sudut kotak sedikit tumpul
            borderRadius: BorderRadius.circular(2), 
          ),
        );
      }),
    );
  }

  Widget _buildCalendar() {
    return TableCalendar(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: _focusedDay,
      rowHeight: 40,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
      },
      calendarFormat: CalendarFormat.month,
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: Colors.orange[300],
          shape: BoxShape.circle,
        ),
        selectedDecoration: const BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
        ),
        defaultTextStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
        weekendTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          color: Colors.red,
          fontWeight: FontWeight.w600,
        ),
        outsideTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          color: Colors.grey[400],
        ),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
        weekendStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.red,
        ),
      ),
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, focusedDay) {
          if (_isPublicHoliday(day)) {
            return Center(
              child: Text(
                '${day.day}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            );
          }
          return null;
        },
      ),
    );
  }

  void _showTidakHadirDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.person_off_outlined, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tidak Hadir Hari Ini (${_tidakHadirList.length})',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('dd-MM-yyyy').format(DateTime.now()),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _tidakHadirList.isEmpty
                    ? Center(
                        child: Text(
                          'Semua karyawan sudah check-in.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _tidakHadirList.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final emp = _tidakHadirList[index];
                          final bool onLeave = emp['on_leave'] == true;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.red[50],
                              child: Text(
                                '${index + 1}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: Colors.red[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              emp['name'].toString(),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              emp['jabatan'].toString(),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                            trailing: onLeave
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[50],
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Cuti/Izin',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        color: Colors.orange[800],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                Text('Tutup', style: GoogleFonts.plusJakartaSans(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
    double width, {
    VoidCallback? onTap,
  }) {
    final card = Container(
      width: width > 0 ? width : 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: color, width: 5.0),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      value,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
        ),
      ),
    );

    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }

  Widget _buildTopEmployeesCard() {
    return _buildRankCard(
      title: 'Top 10 Paling Tepat Waktu',
      subtitle: 'Batas Masuk 08:30 (Toleransi s/d 08:45)',
      icon: Icons.verified_rounded,
      accent: Colors.indigo,
      employees: _topEmployees,
      period: _topEmployeesPeriod,
      currentMonth: _top10CurrentDate,
      isLoading: _isLoadingTop10,
      emptyText: 'Belum ada data kedisiplinan pada bulan ini.',
      onPrev: () {
        _top10CurrentDate =
            DateTime(_top10CurrentDate.year, _top10CurrentDate.month - 1, 1);
        _fetchTop10Data();
      },
      onNext: () {
        _top10CurrentDate =
            DateTime(_top10CurrentDate.year, _top10CurrentDate.month + 1, 1);
        _fetchTop10Data();
      },
    );
  }

  Widget _buildTopLateCard() {
    return _buildRankCard(
      title: 'Top 10 Paling Sering Terlambat',
      subtitle: 'Check-in setelah 08:45 (hari kerja)',
      icon: Icons.watch_later_rounded,
      accent: Colors.red,
      employees: _topLateEmployees,
      period: _topLatePeriod,
      currentMonth: _topLateCurrentDate,
      isLoading: _isLoadingTopLate,
      emptyText: 'Tidak ada keterlambatan pada bulan ini.',
      onPrev: () {
        _topLateCurrentDate = DateTime(
            _topLateCurrentDate.year, _topLateCurrentDate.month - 1, 1);
        _fetchTopLateData();
      },
      onNext: () {
        _topLateCurrentDate = DateTime(
            _topLateCurrentDate.year, _topLateCurrentDate.month + 1, 1);
        _fetchTopLateData();
      },
    );
  }

  Widget _buildRankCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required MaterialColor accent,
    required List<Map<String, dynamic>> employees,
    required String period,
    required DateTime currentMonth,
    required bool isLoading,
    required String emptyText,
    required VoidCallback onPrev,
    required VoidCallback onNext,
  }) {
    final DateTime now = DateTime.now();
    final bool isCurrentMonth =
        currentMonth.year == now.year && currentMonth.month == now.month;

    return Container(
      width: double.infinity,
      height: 400,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, color: accent, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.chevron_left, size: 22),
                    onPressed: onPrev,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    period,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: accent[700],
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.chevron_right,
                      size: 22,
                      color: isCurrentMonth ? Colors.grey[300] : Colors.black87,
                    ),
                    onPressed: () {
                      if (isCurrentMonth) return;
                      onNext();
                    },
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: Colors.grey[500],
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (employees.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 20.0),
                            child: Center(
                              child: Text(
                                emptyText,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          )
                        else
                          ...employees.asMap().entries.map((entry) {
                            final int index = entry.key;
                            final emp = entry.value;
                            final photoUrl = emp['photo'];

                            Color rankColor = Colors.grey[600]!;
                            if (index == 0) rankColor = Colors.amber[700]!;
                            if (index == 1) rankColor = Colors.blueGrey[400]!;
                            if (index == 2) rankColor = Colors.brown[400]!;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10.0),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '#${index + 1}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: rankColor,
                                      ),
                                    ),
                                  ),
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: accent[50],
                                    backgroundImage: (photoUrl != null &&
                                            photoUrl.toString().isNotEmpty)
                                        ? NetworkImage(photoUrl.toString())
                                        : null,
                                    child: (photoUrl == null ||
                                            photoUrl.toString().isEmpty)
                                        ? Icon(Icons.person,
                                            size: 16, color: accent)
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      emp['name'],
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF1E293B),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: accent[50],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      emp['count'],
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: accent[700],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiringContractsCard() {
    return Container(
      width: double.infinity,
      height: 400,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.amber[600], size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Kontrak yg Akan Berakhir (Karyawan Kontrak)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Batas toleransi: 1 Bulan (30 Hari)',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: Colors.grey[500],
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_expiringContracts.isEmpty)
                    Text(
                      'Tidak ada kontrak yang akan berakhir dalam 1 bulan ke depan.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    )
                  else
                    ..._expiringContracts.map((emp) {
                      int diff = emp['diff_days'];
                      String statusText = diff < 0
                          ? 'Lewat ${diff.abs()} hari'
                          : (diff == 0 ? 'Hari ini' : '$diff hari lagi');

                      Color statusColor;
                      Color bgColor;

                      if (diff < 0) {
                        statusColor = Colors.red[700]!;
                        bgColor = Colors.red[50]!;
                      } else if (diff <= 7) {
                        statusColor = Colors.orange[800]!;
                        bgColor = Colors.orange[50]!;
                      } else {
                        statusColor = Colors.amber[800]!;
                        bgColor = Colors.amber[50]!.withOpacity(0.5);
                      }

                      String formattedDate = '-';
                      try {
                        DateTime dt =
                            DateTime.parse(emp['end_date'].toString());
                        formattedDate = DateFormat('yyyy-MM-dd').format(dt);
                      } catch (_) {}

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: RichText(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '${emp['name']} ',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'No: ${emp['contract_number']}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$statusText ($formattedDate)',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
