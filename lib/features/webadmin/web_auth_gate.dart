import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'web_dashboard_page.dart';
import 'web_login_page.dart';
import 'web_ruang_meeting_page.dart';

/// Dipanggil setelah login berhasil. Menentukan tampilan berdasarkan hak akses:
/// - admin      -> WebDashboardPage (dashboard lengkap)
/// - non-admin  -> halaman Ruang Meeting (lihat jadwal + booking sendiri)
///
/// Penentuan admin memakai fungsi SQL `is_admin()` (lihat migration_meeting_room.sql)
/// sehingga aturannya sama dengan RLS di database (satu sumber kebenaran).
class WebAuthGate extends StatefulWidget {
  const WebAuthGate({super.key});

  @override
  State<WebAuthGate> createState() => _WebAuthGateState();
}

class _WebAuthGateState extends State<WebAuthGate> {
  late Future<bool> _isAdminFuture;

  @override
  void initState() {
    super.initState();
    _isAdminFuture = _checkAdmin();
  }

  Future<bool> _checkAdmin() async {
    final res = await Supabase.instance.client.rpc('is_admin');
    return res == true;
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const WebLoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdminFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Gagal memeriksa hak akses:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () =>
                            setState(() => _isAdminFuture = _checkAdmin()),
                        child: const Text('Coba lagi'),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: _logout,
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.data == true) {
          return const WebDashboardPage();
        }
        return _ViewerShell(onLogout: _logout);
      },
    );
  }
}

/// Tampilan untuk user non-admin: melihat jadwal dan membooking ruang meeting.
class _ViewerShell extends StatelessWidget {
  final VoidCallback onLogout;
  const _ViewerShell({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        title: const Text('Tetra • Ruang Meeting & Kendaraan'),
        actions: [
          if (email.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(email, style: const TextStyle(fontSize: 14)),
              ),
            ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: onLogout,
          ),
        ],
      ),
      body: const WebRuangMeetingPage(isAdmin: false),
    );
  }
}
