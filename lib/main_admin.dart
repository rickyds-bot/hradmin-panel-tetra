import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/login_page_admin.dart';
import 'features/admin/admin_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Admin Tetra',
      theme: ThemeData(textTheme: GoogleFonts.plusJakartaSansTextTheme()),
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthChecker(),
        '/login': (context) => LoginPage(),
        //'/register': (context) => RegisterPage(),
        //'/karyawan': (context) => KaryawanPage(),
        '/admin': (context) => AdminPage(),
      },
    );
  }
}

class AuthChecker extends StatefulWidget {
  const AuthChecker({super.key});
  @override
  _AuthCheckerState createState() => _AuthCheckerState();
}

class _AuthCheckerState extends State<AuthChecker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuth());
  }

  Future<void> _checkAuth() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (!mounted) return;

    if (session != null) {
      try {
        final response = await Supabase.instance.client
            .from('employees')
            .select('role')
            .eq('email', session.user.email!)
            .maybeSingle();

        if (!mounted) return;

        if (response != null) {
          // CEK ROLE DI SINI
          final String role =
              (response['role']?.toString().toLowerCase().trim() ?? '');
          if (role == 'admin') {
            Navigator.pushReplacementNamed(context, '/admin');
          } else {
            // Jika bukan admin, keluarkan paksa
            await Supabase.instance.client.auth.signOut();
            Navigator.pushReplacementNamed(context, '/login');
          }
        } else {
          await Supabase.instance.client.auth.signOut();
          Navigator.pushReplacementNamed(context, '/login');
        }
      } catch (e) {
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
      }
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}
