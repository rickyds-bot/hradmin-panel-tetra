import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Sesuaikan path import ini jika berbeda
import 'features/webadmin/web_login_page.dart';

// Notifier global untuk mengontrol tema Dark / Light dari seluruh halaman
ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  // Inisialisasi Supabase khusus web
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const WebDashboardApp());
}

class WebDashboardApp extends StatelessWidget {
  const WebDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'Admin Web Dashboard',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,

          // --- Konfigurasi Tema Terang (Light Theme) ---
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            primarySwatch: Colors.blue,
            cardColor: Colors.white,
            textTheme: GoogleFonts.plusJakartaSansTextTheme(
              ThemeData.light().textTheme,
            ).copyWith(
              bodyMedium: GoogleFonts.roboto(
                fontSize: 14,
                color: const Color(0xFF334155),
              ),
              titleLarge: GoogleFonts.roboto(
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ),

          // --- Konfigurasi Tema Gelap (Dark Theme) ---
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
            primarySwatch: Colors.blue,
            cardColor: const Color(0xFF1E293B), // Slate 800
            textTheme: GoogleFonts.plusJakartaSansTextTheme(
              ThemeData.dark().textTheme,
            ).copyWith(
              bodyMedium: GoogleFonts.roboto(
                fontSize: 14,
                color: const Color(0xFF94A3B8), // Slate 400
              ),
              titleLarge: GoogleFonts.roboto(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
          ),

          home: const WebLoginPage(),
        );
      },
    );
  }
}
