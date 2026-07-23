import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email dan Password wajib diisi")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authResponse = await Supabase.instance.client.auth
          .signInWithPassword(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text.trim(),
          );

      final user = authResponse.user;

      if (user != null) {
        final userData = await Supabase.instance.client
            .from('employees')
            .select('role')
            .eq('email', user.email!)
            .maybeSingle();

        if (!mounted) return;

        final String role =
            (userData?['role']?.toString().toLowerCase().trim() ?? 'karyawan');

        // UBAH BAGIAN INI
        if (role == 'admin') {
          Navigator.pushReplacementNamed(context, '/admin');
        } else {
          // Jika karyawan mencoba login di aplikasi admin, tolak!
          await Supabase.instance.client.auth.signOut(); // Logout otomatis
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Akses Ditolak: Aplikasi ini khusus Admin!"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Login gagal: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // LOGO DENGAN ROUNDED CORNERS & BINGKAI
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue.shade900, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/images/logo_tetra.png',
                    height: 120,
                    width: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              const SizedBox(height: 20),
              const Text(
                "Admin Tetra",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),

              TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: "Email",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
              ),
              const SizedBox(height: 15),

              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 25),

              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _login,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Colors.blue.shade900,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        "Login",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
              const SizedBox(height: 15),
              //  TextButton(
              //    onPressed: () => Navigator.pushNamed(context, '/register'),
              //   child: const Text("Belum punya akun? Daftar Baru"),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}
