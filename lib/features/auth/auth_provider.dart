import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  // Fungsi Login
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        return null; // Sukses
      }
      return "Login gagal";
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return "Terjadi kesalahan: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fungsi Logout
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    notifyListeners();
  }

  // Mendapatkan User yang sedang aktif
  User? get currentUser => _supabase.auth.currentUser;
}
