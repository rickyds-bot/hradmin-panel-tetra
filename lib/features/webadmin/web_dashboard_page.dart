import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main_web.dart';
import 'web_login_page.dart';
import 'web_karyawan_page.dart';
import 'web_absensi.dart';
import 'web_cuti.dart';
import 'web_lembur.dart';
import 'web_lokasi.dart';
import 'web_log.dart';
import 'web_dashboard_content.dart';

class WebDashboardPage extends StatefulWidget {
  const WebDashboardPage({super.key});

  @override
  State<WebDashboardPage> createState() => _WebDashboardPageState();
}

class _WebDashboardPageState extends State<WebDashboardPage> {
  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;
  bool _isLaporanExpanded = false; // Status expand menu Laporan

  final List<String> _pageTitles = [
    'Dashboard',
    'Data Karyawan',
    'Data Absensi',
    'Pengajuan Cuti & Izin',
    'Pengajuan Lembur',
    'Pengaturan Lokasi',
    'Log Aktivitas Karyawan',
    'Laporan Karyawan',
    'Laporan Absensi',
    'Laporan Cuti',
    'Laporan Lembur',
  ];

  late final List<Widget> _pages = [
    const WebDashboardContent(),
    const WebKaryawanPage(),
    const WebAbsensiPage(),
    const WebCutiPage(),
    const WebLemburPage(),
    const WebLokasiPage(),
    const WebLogPage(),
    // Halaman Laporan (Sementara menggunakan halaman terkait atau placeholder khusus laporan)
    const WebKaryawanPage(), // Laporan Karyawan
    const WebAbsensiPage(), // Laporan Absensi
    const WebCutiPage(), // Laporan Cuti
    const WebLemburPage(), // Laporan Lembur
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
    final isDarkMode = themeNotifier.value == ThemeMode.dark;

    return Scaffold(
      body: Row(
        children: [
          // --- SIDEBAR NAVIGASI ---
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isSidebarExpanded ? 260 : 76,
            color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.grey[50],
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
                      bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
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
                            ),
                          ),
                        ),
                      IconButton(
                        icon: Icon(
                          _isSidebarExpanded ? Icons.menu_open : Icons.menu,
                          size: 20,
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
                      _buildNavItem(1, Icons.people_outline, 'Data Karyawan'),
                      _buildNavItem(
                        2,
                        Icons.access_time_outlined,
                        'Data Absensi',
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

                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        child: Divider(),
                      ),

                      // --- MENU DROPDOWN LAPORAN ---
                      _buildLaporanDropdownGroup(),

                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        child: Divider(),
                      ),
                      _buildNavItem(
                        6,
                        Icons.receipt_long_outlined,
                        'Log Aktivitas',
                      ),
                    ],
                  ),
                ),

                // --- FOOTER SIDEBAR: PROFIL ADMINISTRATOR (TETAP MUNCUL MESKI DIKECILKAN) ---
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.withOpacity(0.2)),
                    ),
                  ),
                  child: PopupMenuButton<String>(
                    offset: const Offset(0, -150),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'theme',
                        child: Row(
                          children: [
                            Icon(
                              isDarkMode ? Icons.light_mode : Icons.dark_mode,
                              size: 14,
                            ),
                            const SizedBox(width: 8),
                            Text(isDarkMode ? 'Mode Light' : 'Mode Dark'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'password',
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, size: 16),
                            const SizedBox(width: 8),
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
                            const SizedBox(width: 8),
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
                      if (value == 'theme') {
                        setState(() {
                          themeNotifier.value = isDarkMode
                              ? ThemeMode.light
                              : ThemeMode.dark;
                        });
                      } else if (value == 'password') {
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
                            backgroundColor: Colors.blueAccent,
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
                                    ),
                                  ),
                                  Text(
                                    'Setting',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.unfold_more,
                              size: 16,
                              color: Colors.grey,
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
            child: Column(
              children: [
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _pageTitles[_selectedIndex],
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _pages[_selectedIndex]),
              ],
            ),
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
                  ? Colors.blue.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.blueAccent : Colors.grey,
                ),
                if (_isSidebarExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isSelected ? Colors.blueAccent : null,
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
    bool isLaporanSelected = _selectedIndex >= 7 && _selectedIndex <= 10;

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
                    ? Colors.blue.withOpacity(0.05)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.assessment_outlined,
                    size: 18,
                    color: isLaporanSelected ? Colors.blueAccent : Colors.grey,
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
                          color: isLaporanSelected ? Colors.blueAccent : null,
                        ),
                      ),
                    ),
                    Icon(
                      _isLaporanExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 16,
                      color: Colors.grey,
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
                _buildSubNavItem(7, 'Laporan Karyawan'),
                _buildSubNavItem(8, 'Laporan Absensi'),
                _buildSubNavItem(9, 'Laporan Cuti'),
                _buildSubNavItem(10, 'Laporan Lembur'),
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
                  ? Colors.blue.withOpacity(0.1)
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
                    color: isSelected ? Colors.blueAccent : Colors.grey[400],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: isSelected ? Colors.blueAccent : Colors.grey[700],
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
