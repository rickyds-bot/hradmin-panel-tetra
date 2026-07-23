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
      // 1. Ambil data karyawan (untuk total & jenis kelamin)
      final karyawanRes = await Supabase.instance.client
          .from('employees')
          .select('id, gender'); // Pastikan kolom gender ada di tabel employees

      _totalKaryawan = karyawanRes.length;

      int l = 0;
      int p = 0;
      for (var emp in karyawanRes) {
        final gender = (emp['gender'] ?? '').toString().trim().toLowerCase();
        // Menyesuaikan dengan isian gender di database (misal: 'l', 'laki-laki', 'male' / 'p', 'perempuan', 'female')
        if (gender == 'l' || gender == 'laki-laki' || gender == 'male') {
          l++;
        } else if (gender == 'p' ||
            gender == 'perempuan' ||
            gender == 'female') {
          p++;
        }
      }
      _totalLakiLaki = l;
      _totalPerempuan = p;

      // 2. Absen Hari Ini (Check-In)
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final absensiRes = await Supabase.instance.client
          .from('attendance')
          .select()
          .gte('created_at', '$todayStr 00:00:00');

      Set uniqueHadir = absensiRes.map((e) => e['employee_id']).toSet();
      _totalHadirHariIni = uniqueHadir.length;

      // 3. Cuti Hari Ini
      final cutiRes = await Supabase.instance.client
          .from('leave_requests')
          .select()
          .eq('status', 'approved')
          .lte('start_date', todayStr)
          .gte('end_date', todayStr);
      _totalCutiHariIni = cutiRes.length;

      // 4. Lembur Pending
      final lemburRes = await Supabase.instance.client
          .from('overtime_requests')
          .select('id')
          .eq('status', 'pending');
      _totalPendingLembur = lemburRes.length;
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
                          /* Text(
                            'Selamat Datang di HR Admin Panel',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ), */
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: _fetchDashboardStats,
                            tooltip: 'Refresh Statistik',
                          ),
                        ],
                      ),
                      /* const SizedBox(height: 8),
                      Text(
                        'Gunakan menu navigasi di sebelah kiri untuk mengelola data karyawan, memantau absensi real-time, memproses cuti, lembur, serta melihat laporan berkala.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.5,
                        ),
                      ), */
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
