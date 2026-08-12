import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WebDashboardContent extends StatefulWidget {
  const WebDashboardContent({super.key});

  @override
  State<WebDashboardContent> createState() => _WebDashboardContentState();
}

class _WebDashboardContentState extends State<WebDashboardContent> {
  bool _isLoading = true;
  int _totalKaryawan = 0;
  int _totalLakiLaki = 0;
  int _totalPerempuan = 0;
  int _totalTetap = 0;
  int _totalKontrak = 0;
  int _totalMagang = 0;
  int _totalHadirHariIni = 0;
  int _totalCutiHariIni = 0;
  int _totalPendingLembur = 0;

  @override
  void initState() {
    super.initState();
    _fetchDashboardStats();
  }

  Future<void> _fetchDashboardStats() async {
    setState(() => _isLoading = true);
    try {
      // 1. Ambil data karyawan (tambahkan 'role' di select)
      final karyawanRes = await Supabase.instance.client
          .from('employees')
          .select('id, gender, employee_status, role');

      int l = 0;
      int p = 0;
      int tetap = 0;
      int kontrak = 0;
      int magang = 0;

      // List untuk menampung ID karyawan selain Admin
      List<dynamic> nonAdminIds = [];

      for (var emp in karyawanRes) {
        // Abaikan perhitungan jika role adalah Admin
        final role = (emp['role'] ?? '').toString().trim().toLowerCase();
        if (role == 'admin') continue;

        // Simpan ID non-admin untuk filter tabel lain
        nonAdminIds.add(emp['id']);

        // Hitung Gender
        final gender = (emp['gender'] ?? '').toString().trim().toLowerCase();
        if (gender == 'l' || gender == 'laki-laki' || gender == 'male') {
          l++;
        } else if (gender == 'p' ||
            gender == 'perempuan' ||
            gender == 'female') {
          p++;
        }

        // Hitung Status Kerja (Tetap, Kontrak, Magang)
        final empStatus =
            (emp['employee_status'] ?? '').toString().trim().toLowerCase();
        if (empStatus == 'tetap') {
          tetap++;
        } else if (empStatus == 'kontrak') {
          kontrak++;
        } else if (empStatus == 'magang') {
          magang++;
        }
      }

      _totalKaryawan = nonAdminIds.length;
      _totalLakiLaki = l;
      _totalPerempuan = p;
      _totalTetap = tetap;
      _totalKontrak = kontrak;
      _totalMagang = magang;

      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      // 2. Absen Hari Ini (Check-In)
      final absensiRes = await Supabase.instance.client
          .from('attendance')
          .select('employee_id')
          .gte('created_at', '$todayStr 00:00:00');

      // Filter: Hanya hitung ID yang ada di dalam nonAdminIds
      Set uniqueHadir = absensiRes
          .map((e) => e['employee_id'])
          .where((id) => nonAdminIds.contains(id))
          .toSet();
      _totalHadirHariIni = uniqueHadir.length;

      // 3. Cuti Hari Ini
      final cutiRes = await Supabase.instance.client
          .from('leave_requests')
          .select('employee_id')
          .eq('status', 'approved')
          .lte('start_date', todayStr)
          .gte('end_date', todayStr);

      // Filter Cuti
      _totalCutiHariIni =
          cutiRes.where((e) => nonAdminIds.contains(e['employee_id'])).length;

      // 4. Lembur Pending
      final lemburRes = await Supabase.instance.client
          .from('overtime_requests')
          .select('employee_id')
          .eq('status', 'pending');

      // Filter Lembur
      _totalPendingLembur =
          lemburRes.where((e) => nonAdminIds.contains(e['employee_id'])).length;
    } catch (e) {
      debugPrint('Error fetching dashboard stats: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                          width,
                        ),
                        _buildStatCard(
                          'Karyawan Tetap',
                          _totalTetap.toString(),
                          'Status: Tetap',
                          Icons.verified_user_outlined,
                          Colors.indigo,
                          width,
                        ),
                        _buildStatCard(
                          'Karyawan Kontrak',
                          _totalKontrak.toString(),
                          'Status: Kontrak',
                          Icons.assignment_ind_outlined,
                          Colors.teal,
                          width,
                        ),
                        _buildStatCard(
                          'Karyawan Magang',
                          _totalMagang.toString(),
                          'Status: Magang',
                          Icons.school_outlined,
                          Colors.brown,
                          width,
                        ),
                        _buildStatCard(
                          'Hadir Hari Ini',
                          _totalHadirHariIni.toString(),
                          'Tercatat masuk sistem',
                          Icons.how_to_reg_outlined,
                          Colors.green,
                          width,
                        ),
                        _buildStatCard(
                          'Cuti / Izin Aktif',
                          _totalCutiHariIni.toString(),
                          'Disetujui hari ini',
                          Icons.event_busy_outlined,
                          Colors.orange,
                          width,
                        ),
                        _buildStatCard(
                          'Lembur Pending',
                          _totalPendingLembur.toString(),
                          'Menunggu approval',
                          Icons.timer_outlined,
                          Colors.purple,
                          width,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),

                // Bagian Informasi Tambahan
                Container(
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: _fetchDashboardStats,
                            tooltip: 'Refresh Statistik',
                          ),
                        ],
                      ),
                    ],
                  ),
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
    double width,
  ) {
    return Container(
      width: width > 0 ? width : 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
