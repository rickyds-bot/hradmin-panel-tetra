import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
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
  int _totalCutiHariIni = 0;
  int _totalPendingLembur = 0;

  // Data Grafik
  List<BarChartGroupData> _attendanceChartData = [];
  List<String> _chartLabels = [];
  double _maxYChart = 10;

  // Data Kalender & Hari Libur
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final Map<String, String> _holidaysMap = {};

  // Variabel untuk Karyawan Paling Tepat Waktu & Kontrak
  List<Map<String, dynamic>> _topEmployees = [];
  String _topEmployeesPeriod = '';
  List<Map<String, dynamic>> _expiringContracts = [];

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Ambil data hari libur dari Supabase (tabel hari_libur)
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

      // 2. Ambil data karyawan (Filter non-admin + Ambil data kontrak)
      final karyawanRes = await Supabase.instance.client.from('employees').select(
          'id, full_name, gender, employee_status, role, contract_number, contract_end');

      int l = 0, p = 0, tetap = 0, kontrak = 0, magang = 0;
      List<dynamic> nonAdminIds = [];
      List<Map<String, dynamic>> tempExpiring = [];

      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);

      for (var emp in karyawanRes) {
        final role = (emp['role'] ?? '').toString().trim().toLowerCase();
        if (role == 'admin') continue;

        nonAdminIds.add(emp['id']);

        final gender = (emp['gender'] ?? '').toString().trim().toLowerCase();
        if (gender == 'l' || gender == 'laki-laki' || gender == 'male') {
          l++;
        } else if (gender == 'p' ||
            gender == 'perempuan' ||
            gender == 'female') {
          p++;
        }

        final empStatus =
            (emp['employee_status'] ?? '').toString().trim().toLowerCase();
        if (empStatus == 'tetap') {
          tetap++;
        } else if (empStatus == 'kontrak') {
          kontrak++;

          // Cek masa berlaku kontrak (1 bulan / 30 hari sebelum atau sudah lewat)
          if (emp['contract_end'] != null) {
            try {
              DateTime endDate = DateTime.parse(emp['contract_end'].toString());
              DateTime endDay =
                  DateTime(endDate.year, endDate.month, endDate.day);
              int diffDays = endDay.difference(today).inDays;

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

      // Urutkan dari yang paling mendesak (minus / terlewat paling atas)
      tempExpiring.sort((a, b) => a['diff_days'].compareTo(b['diff_days']));
      _expiringContracts = tempExpiring;

      _totalKaryawan = nonAdminIds.length;
      _totalLakiLaki = l;
      _totalPerempuan = p;
      _totalTetap = tetap;
      _totalKontrak = kontrak;
      _totalMagang = magang;

      final todayStr = today.toIso8601String().split('T')[0];

      // 3. Absen Hari Ini (Check-In)
      final absensiRes = await Supabase.instance.client
          .from('attendance')
          .select('employee_id')
          .gte('created_at', '$todayStr 00:00:00');

      Set uniqueHadir = absensiRes
          .map((e) => e['employee_id'])
          .where((id) => nonAdminIds.contains(id))
          .toSet();
      _totalHadirHariIni = uniqueHadir.length;

      // 4. Cuti Hari Ini
      final cutiRes = await Supabase.instance.client
          .from('leave_requests')
          .select('employee_id')
          .eq('status', 'approved')
          .lte('start_date', todayStr)
          .gte('end_date', todayStr);

      _totalCutiHariIni =
          cutiRes.where((e) => nonAdminIds.contains(e['employee_id'])).length;

      // 5. Lembur Pending
      final lemburRes = await Supabase.instance.client
          .from('overtime_requests')
          .select('employee_id')
          .eq('status', 'pending');

      _totalPendingLembur =
          lemburRes.where((e) => nonAdminIds.contains(e['employee_id'])).length;

      // 6. Data Grafik Kehadiran 7 Hari Terakhir
      await _fetchChartData(nonAdminIds);

      // 7. Karyawan Paling Tepat Waktu (Top 8)
      DateTime firstDayPrevMonth = DateTime(now.year, now.month - 1, 1);
      DateTime lastDayPrevMonth = DateTime(now.year, now.month, 0);

      String startDate = firstDayPrevMonth.toIso8601String().split('T')[0];
      String endDate = lastDayPrevMonth.toIso8601String().split('T')[0];

      const List<String> _namaBulan = [
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
      _topEmployeesPeriod =
          '${_namaBulan[firstDayPrevMonth.month - 1]} ${firstDayPrevMonth.year}';

      final allAttRes = await Supabase.instance.client
          .from('attendance')
          .select('employee_id, created_at')
          .gte('created_at', '$startDate 00:00:00')
          .lte('created_at', '$endDate 23:59:59');

      Map<String, int> onTimeCounts = {};

      for (var r in allAttRes) {
        final eId = r['employee_id'];
        if (nonAdminIds.contains(eId)) {
          final String eIdStr = eId.toString();
          final createdAtStr = r['created_at'];

          if (createdAtStr != null) {
            try {
              DateTime checkInTime = DateTime.parse(createdAtStr.toString());
              int totalMinutes = checkInTime.hour * 60 + checkInTime.minute;
              const int limitMinutes = 8 * 60 + 45; // 08:45

              if (totalMinutes <= limitMinutes) {
                onTimeCounts[eIdStr] = (onTimeCounts[eIdStr] ?? 0) + 1;
              }
            } catch (_) {}
          }
        }
      }

      var sortedKeys = onTimeCounts.keys.toList()
        ..sort((a, b) => onTimeCounts[b]!.compareTo(onTimeCounts[a]!));

      var top8Keys = sortedKeys.take(8).toList();

      if (top8Keys.isNotEmpty) {
        final topEmpData = await Supabase.instance.client
            .from('employees')
            .select('id, full_name, photo_url, jabatan_name')
            .inFilter('id', top8Keys);

        List<Map<String, dynamic>> tempTop = [];
        for (var key in top8Keys) {
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
      debugPrint('Error fetching dashboard stats: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchChartData(List<dynamic> validIds) async {
    final last7Days = DateTime.now().subtract(const Duration(days: 6));
    final last7DaysStr = DateFormat('yyyy-MM-dd').format(last7Days);

    final weeklyRes = await Supabase.instance.client
        .from('attendance')
        .select('employee_id, created_at')
        .gte('created_at', '$last7DaysStr 00:00:00');

    Map<String, Set<dynamic>> dailyHadir = {};
    for (int i = 0; i < 7; i++) {
      final d = last7Days.add(Duration(days: i));
      dailyHadir[DateFormat('yyyy-MM-dd').format(d)] = {};
    }

    for (var row in weeklyRes) {
      final empId = row['employee_id'];
      if (!validIds.contains(empId)) continue;

      final createdAt = row['created_at'];
      if (createdAt != null) {
        final dateStr = createdAt.toString().split('T')[0];
        if (dailyHadir.containsKey(dateStr)) {
          dailyHadir[dateStr]!.add(empId);
        }
      }
    }

    List<BarChartGroupData> tempChartData = [];
    List<String> tempLabels = [];
    double maxVal = 0;
    int index = 0;

    dailyHadir.forEach((dateStr, empSet) {
      final count = empSet.length.toDouble();
      if (count > maxVal) maxVal = count;

      final dateObj = DateTime.parse(dateStr);
      tempLabels.add(DateFormat('dd MMM').format(dateObj));

      tempChartData.add(
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: count,
              color: Colors.blue[600]!,
              width: 40,
              borderRadius: BorderRadius.circular(6),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: _totalKaryawan.toDouble() > 0
                    ? _totalKaryawan.toDouble()
                    : 10,
                color: Colors.blue[50],
              ),
            ),
          ],
        ),
      );
      index++;
    });

    _attendanceChartData = tempChartData;
    _chartLabels = tempLabels;
    _maxYChart = maxVal < 10 ? 10 : (_totalKaryawan.toDouble() + 5);
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

                // Layout Utama: Baris 1 (Grafik & Top 8 Tepat Waktu), Baris 2 (Kontrak Akan Berakhir & Kalender)
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
                          Text(
                            'Grafik Kehadiran (7 Hari Terakhir)',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Expanded(child: _buildAttendanceChart()),
                        ],
                      ),
                    );

                    Widget calendarSection = Container(
                      width: isWide ? null : constraints.maxWidth,
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
                        children: [
                          // Baris 1: Grafik Kehadiran (Kiri) & Top 8 Paling Tepat Waktu (Kanan)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 2, child: chartSection),
                              const SizedBox(width: 16),
                              Expanded(
                                  flex: 1, child: _buildTopEmployeesCard()),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Baris 2: Kontrak Akan Berakhir (Kiri) & Kalender (Kanan)
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

  // Komponen Grafik (fl_chart)
  Widget _buildAttendanceChart() {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: _maxYChart,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => Colors.blueGrey[800]!,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${_chartLabels[group.x.toInt()]}\n',
                GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                children: <TextSpan>[
                  TextSpan(
                    text: '${rod.toY.toInt()} Hadir',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.amber,
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                final int index = value.toInt();
                if (index >= 0 && index < _chartLabels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _chartLabels[index],
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }
                return const SizedBox();
              },
              reservedSize: 28,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: _maxYChart > 20 ? 10 : 2,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.left,
                );
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey[200],
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: _attendanceChartData,
      ),
    );
  }

  // Komponen Kalender
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

  Widget _buildStatCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
    double width,
  ) {
    return Container(
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
  }

  // Widget daftar Top 8 Karyawan Paling Tepat Waktu
  Widget _buildTopEmployeesCard() {
    return Container(
      width: double.infinity,
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
              const Icon(Icons.verified_rounded,
                  color: Colors.indigo, size: 20),
              const SizedBox(width: 8),
              Text(
                'Top 8 Paling Tepat Waktu',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Periode: $_topEmployeesPeriod • Batas Masuk 08:30 (Toleransi s/d 08:45)',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: Colors.grey[500],
            ),
          ),
          const Divider(height: 20),
          if (_topEmployees.isEmpty)
            Text(
              'Belum ada data kedisiplinan.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Colors.grey,
              ),
            )
          else
            ..._topEmployees.asMap().entries.map((entry) {
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
                      backgroundColor: Colors.indigo[50],
                      backgroundImage:
                          (photoUrl != null && photoUrl.toString().isNotEmpty)
                              ? NetworkImage(photoUrl.toString())
                              : null,
                      child: (photoUrl == null || photoUrl.toString().isEmpty)
                          ? const Icon(Icons.person,
                              size: 16, color: Colors.indigo)
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
                        color: Colors.indigo[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        emp['count'],
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo[700],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // Widget daftar Karyawan Kontrak Akan Berakhir
  Widget _buildExpiringContractsCard() {
    return Container(
      width: double.infinity,
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
              Text(
                'Kontrak Akan Berakhir',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
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
                DateTime dt = DateTime.parse(emp['end_date'].toString());
                formattedDate = DateFormat('yyyy-MM-dd').format(dt);
              } catch (_) {}

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    );
  }
}
