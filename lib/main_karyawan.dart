import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/login_page.dart';
import 'features/auth/register_page.dart';
import 'features/employee/karyawan_page.dart';
import 'package:google_fonts/google_fonts.dart';
//import 'package:timezone/data/latest_all.dart' as tz;
import 'package:firebase_core/firebase_core.dart';
import 'features/employee/notification_services.dart';
import 'firebase_options.dart';

//import 'package:mobile_absensi/features/auth/login_page.dart';
//import 'package:mobile_absensi/features/auth/register_page.dart';
//import 'package:mobile_absensi/features/employee/karyawan_page.dart';
//import 'package:mobile_absensi/features/employee/notification_services.dart';
import 'package:mobile_absensi/features/employee/face_net_service.dart';

void main() async {
  // Pastikan binding ini dipanggil paling pertama
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Gunakan DefaultFirebaseOptions yang baru saja kita buat
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService().initialize();

  //tz.initializeTimeZones();

  await Supabase.initialize(
    url: 'https://srnufxhwmrvazixithku.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNybnVmeGh3bXJ2YXppeGl0aGt1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE2NjcyMDMsImV4cCI6MjA5NzI0MzIwM30.Dj5yinnmQbF0DUN7LapjsiUeD7yPxirkUMCPLQporpU',
  );

  await FaceNetService().loadModel();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Absensi Tetra',
      theme: ThemeData(textTheme: GoogleFonts.plusJakartaSansTextTheme()),
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthChecker(),
        '/login': (context) => LoginPage(),
        '/register': (context) => RegisterPage(),
        '/karyawan': (context) => KaryawanPage(),
        // '/admin': (context) => AdminPage(),
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

    if (!mounted) return; // Keamanan tambahan

    if (session != null) {
      final userId = session.user.id;

      try {
        final response = await Supabase.instance.client
            .from('employees')
            .select('role')
            .eq('email', session.user.email!)
            .maybeSingle();

        if (!mounted) return; // Keamanan tambahan

        if (response != null) {
          Navigator.pushReplacementNamed(context, '/karyawan');
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
      backgroundColor: Colors.blue.shade900,
      body: const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}
