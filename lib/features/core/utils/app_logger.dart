import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppLogger {
  /// Mencatat aktivitas ke tabel activity_logs secara otomatis
  /// berdasarkan user yang sedang login saat ini.
  static Future<void> log({
    required String activity,
    required String module,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      // 1. Dapatkan data user yang sedang login dari sesi Supabase
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        debugPrint('Log gagal: Tidak ada user yang login.');
        return;
      }

      // 2. Cari ID karyawan (int8) di tabel employees berdasarkan email user yang login
      // (Asumsi di tabel employees Anda ada kolom 'email' atau 'user_id')
      final employeeData = await supabase
          .from('employees')
          .select('id')
          .eq('email', currentUser.email ?? '')
          .maybeSingle();

      if (employeeData != null) {
        // 3. Masukkan data log dengan ID karyawan yang valid
        await supabase.from('activity_logs').insert({
          'employee_id': employeeData['id'],
          'activity': activity,
          'module': module,
        });
      } else {
        debugPrint(
            'Log gagal: Data karyawan tidak ditemukan untuk email ${currentUser.email}');
      }
    } catch (e) {
      debugPrint('Gagal mencatat log: $e');
    }
  }
}
