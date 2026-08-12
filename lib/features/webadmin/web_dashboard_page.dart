import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'web_login_page.dart';
import 'web_karyawan_page.dart';
import 'web_absensi.dart';
import 'web_cuti.dart';
import 'web_lembur.dart';
import 'web_lokasi.dart';
import 'web_log.dart';
import 'web_dashboard_content.dart';
import 'web_laporan_karyawan_page.dart';
import 'web_laporan_absensi.dart';
import 'web_pemberitahuan_page.dart';
import 'web_laporan_cuti.dart';
import 'web_laporan_lembur.dart';

class WebDashboardPage extends StatefulWidget {
  const WebDashboardPage({super.key});

  @override
  State<WebDashboardPage> createState() => _WebDashboardPageState();
}

class _WebDashboardPageState extends State<WebDashboardPage> {
  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;
  bool _isLaporanExpanded = false; // Status expand menu Laporan

  // Urutan judul disesuaikan persis dengan urutan indeks _pages di bawah
  final List<String> _pageTitles = [
    'Dashboard', // 0
    'Data Karyawan', // 1
    'Data Absensi', // 2
    'Cuti & Izin', // 3
    'Pengajuan Lembur', // 4
    'Pengaturan Lokasi', // 5
    'Pemberitahuan', // 6
    'Log Aktifitas Karyawan', // 7
    'Laporan Karyawan', // 8
    'Laporan Absensi', // 9
    'Laporan Cuti', // 10
    'Laporan Lembur', // 11
  ];

  late final List<Widget> _pages = [
    const WebDashboardContent(), // 0
    const WebKaryawanPage(), // 1
    const WebAbsensiPage(), // 2
    const WebCutiPage(), // 3
    const WebLemburPage(), // 4
    const WebLokasiPage(), // 5
    const WebPemberitahuanPage(), // 6
    const WebLogPage(), // 7
    const WebLaporanKaryawanPage(), // 8
    const WebLaporanAbsensiPage(), // 9
    const LaporanCutiPage(), // 10
    const LaporanLemburPage(), // 11
  ];

  void _showGantiPasswordDialog(BuildContext context) {
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Ganti Password',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPassCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password Lama',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPassCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password Baru',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Password berhasil diperbarui!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Tema Sidebar menggunakan warna Biru penuh
    final sidebarBgColor = Colors.blue[800]!;
    final sidebarTextColor = Colors.white;
    final sidebarIconColor = Colors.white70;

    return Scaffold(
      body: Row(
        children: [
          // --- SIDEBAR NAVIGASI ---
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isSidebarExpanded ? 260 : 76,
            color: sidebarBgColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Sidebar (Logo & Tombol Collapse)
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.white.withOpacity(0.15)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_isSidebarExpanded)
                        Expanded(
                          child: Text(
                            'HR Admin Panel',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: sidebarTextColor,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: Icon(
                          _isSidebarExpanded ? Icons.menu_open : Icons.menu,
                          size: 20,
                          color: sidebarTextColor,
                        ),
                        onPressed: () {
                          setState(() {
                            _isSidebarExpanded = !_isSidebarExpanded;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Daftar Menu Sidebar
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      _buildNavItem(0, Icons.dashboard_outlined, 'Dashboard'),
                      _buildNavItem(1, Icons.people_outline, 'Karyawan'),
                      _buildNavItem(
                        2,
                        Icons.access_time_outlined,
                        'Absensi',
                      ),
                      _buildNavItem(
                        3,
                        Icons.event_note_outlined,
                        'Cuti & Izin',
                      ),
                      _buildNavItem(4, Icons.more_time_outlined, 'Lembur'),
                      _buildNavItem(
                        5,
                        Icons.location_on_outlined,
                        'Pengaturan Lokasi',
                      ),
                      _buildNavItem(
                        6,
                        Icons.campaign_outlined,
                        'Pemberitahuan',
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        child: Divider(color: Colors.white.withOpacity(0.2)),
                      ),

                      // --- MENU DROPDOWN LAPORAN (Indeks 8 sampai 11) ---
                      _buildLaporanDropdownGroup(),

                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        child: Divider(color: Colors.white.withOpacity(0.2)),
                      ),
                      _buildNavItem(
                        7,
                        Icons.receipt_long_outlined,
                        'Log Aktifitas',
                      ),
                    ],
                  ),
                ),

                // --- FOOTER SIDEBAR: PROFIL ADMINISTRATOR ---
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.white.withOpacity(0.15)),
                    ),
                  ),
                  child: PopupMenuButton<String>(
                    offset: const Offset(0, -120),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'password',
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, size: 16),
                            SizedBox(width: 8),
                            Text('Ganti Password'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(Icons.logout, size: 16, color: Colors.red),
                            SizedBox(width: 8),
                            Text(
                              'Logout',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) async {
                      if (value == 'password') {
                        _showGantiPasswordDialog(context);
                      } else if (value == 'logout') {
                        await Supabase.instance.client.auth.signOut();
                        if (mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const WebLoginPage(),
                            ),
                          );
                        }
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: _isSidebarExpanded
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        children: [
                          const CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.white24,
                            child: Icon(
                              Icons.admin_panel_settings,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                          if (_isSidebarExpanded) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Administrator',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: sidebarTextColor,
                                    ),
                                  ),
                                  Text(
                                    'Setting',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.unfold_more,
                              size: 16,
                              color: sidebarIconColor,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Colors.grey.withOpacity(0.2),
          ),

          // --- KONTEN UTAMA ---
          Expanded(
            child: _pages[_selectedIndex],
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = _selectedIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            setState(() {
              _selectedIndex = index;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
                if (_isSidebarExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? Colors.white : Colors.white70,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLaporanDropdownGroup() {
    // Range index laporan dari 8 sampai 11
    bool isLaporanSelected = _selectedIndex >= 8 && _selectedIndex <= 11;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              setState(() {
                if (!_isSidebarExpanded) {
                  _isSidebarExpanded = true;
                }
                _isLaporanExpanded = !_isLaporanExpanded;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isLaporanSelected
                    ? Colors.white.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.assessment_outlined,
                    size: 18,
                    color: isLaporanSelected ? Colors.white : Colors.white70,
                  ),
                  if (_isSidebarExpanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Laporan',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: isLaporanSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color:
                              isLaporanSelected ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                    Icon(
                      _isLaporanExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 16,
                      color: Colors.white70,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_isSidebarExpanded && _isLaporanExpanded) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Column(
              children: [
                _buildSubNavItem(8, 'Laporan Karyawan'),
                _buildSubNavItem(9, 'Laporan Absensi'),
                _buildSubNavItem(10, 'Laporan Cuti'),
                _buildSubNavItem(11, 'Laporan Lembur'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSubNavItem(int index, String label) {
    bool isSelected = _selectedIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            setState(() {
              _selectedIndex = index;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? Colors.white : Colors.white60,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
