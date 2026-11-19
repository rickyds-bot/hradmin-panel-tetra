import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterPage extends StatefulWidget {
  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _nikCtrl = TextEditingController();
  final _tanggalMasukCtrl = TextEditingController();

  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _positions = [];

  dynamic _selectedDepartmentId;
  dynamic _selectedPositionId;
  String? _selectedStatus;

  bool _isLoadingData = true;
  bool _isSubmitting = false;

  final List<String> _statusKerjaOptions = ['Tetap', 'Kontrak', 'Magang'];

  @override
  void initState() {
    super.initState();
    _loadDropdownData();
  }

  Future<void> _loadDropdownData() async {
    try {
      final deptData =
          await Supabase.instance.client.from('departments').select('id, name');
      final posData =
          await Supabase.instance.client.from('positions').select('id, name');

      if (mounted) {
        setState(() {
          _departments = List<Map<String, dynamic>>.from(deptData);
          _positions = List<Map<String, dynamic>>.from(posData);
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  Future<void> _pilihTanggal(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null) {
      setState(() {
        _tanggalMasukCtrl.text =
            "${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}";
      });
    }
  }

  void _tampilkanDialogPesan(String judul, String pesan, Color warnaHeader) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          judul,
          style: TextStyle(color: warnaHeader, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(child: Text(pesan)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Tutup", style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  // Email dinormalisasi (trim + huruf kecil) supaya "Budi@x.com" dan
  // "budi@x.com" dianggap email yang sama.
  String get _email => _emailCtrl.text.trim().toLowerCase();

  bool _formatEmailValid(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  // Cek ke database lewat fungsi RPC `email_terdaftar` (lihat SQL terpisah).
  Future<bool> _emailSudahTerdaftar(String email) async {
    final res = await Supabase.instance.client
        .rpc('email_terdaftar', params: {'p_email': email});
    return res == true;
  }

  void _dialogEmailTerdaftar() {
    _tampilkanDialogPesan(
      "Email Sudah Terdaftar",
      "Alamat email ini sudah terdaftar dan tidak dapat digunakan lagi. "
          "Silakan gunakan email lain atau langsung Login.",
      Colors.red,
    );
  }

  Future<void> _register() async {
    final email = _email;
    final password = _passwordCtrl.text.trim();

    if (_fullNameCtrl.text.trim().isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        _selectedStatus == null ||
        _tanggalMasukCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lengkapi data yang wajib!")),
      );
      return;
    }

    if (!_formatEmailValid(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Format email tidak valid!")),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password minimal 6 karakter!")),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // LAPIS 1: cek ke database SEBELUM membuat akun, supaya tidak ada
      // akun Auth "yatim" tanpa data karyawan.
      if (await _emailSudahTerdaftar(email)) {
        if (mounted) _dialogEmailTerdaftar();
        return;
      }

      final authResponse = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );

      final user = authResponse.user;
      if (user == null) {
        throw 'Registrasi gagal. Silakan coba lagi.';
      }

      // LAPIS 2: jika konfirmasi email Supabase AKTIF dan email sudah pernah
      // terdaftar, Supabase TIDAK melempar error. Ia mengembalikan user
      // "palsu" dengan identities kosong. Tanpa pengecekan ini, aplikasi
      // akan menampilkan "Cek Email Anda" padahal akun tidak dibuat.
      if (user.identities != null && user.identities!.isEmpty) {
        if (mounted) _dialogEmailTerdaftar();
        return;
      }

      final Map<String, dynamic> insertData = {
        'email': email,
        'full_name': _fullNameCtrl.text.trim(),
        'employee_status': _selectedStatus?.toLowerCase(),
        'join_date': _tanggalMasukCtrl.text,
        'role': 'karyawan',
        'department_id': _selectedDepartmentId ?? 0,
        'position_id': _selectedPositionId ?? 0,
        'location_id': 1,
      };

      if (_nikCtrl.text.isNotEmpty) insertData['nik'] = _nikCtrl.text.trim();
      if (_selectedDepartmentId != null)
        insertData['department_id'] = _selectedDepartmentId;
      if (_selectedPositionId != null)
        insertData['position_id'] = _selectedPositionId;

      // LAPIS 3: unique index di tabel employees (lihat SQL). Jika lolos
      // dari dua lapis di atas (mis. dua orang submit bersamaan), insert
      // ini akan ditolak database dan ditangkap di catch di bawah.
      await Supabase.instance.client.from('employees').insert(insertData);

      if (!mounted) return;

      if (authResponse.session == null) {
        // Supabase mewajibkan konfirmasi email
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Row(
              children: [
                Icon(Icons.mark_email_unread, color: Colors.blue),
                SizedBox(width: 10),
                Text("Cek Email Anda", style: TextStyle(fontSize: 18)),
              ],
            ),
            content: const Text(
              "Registrasi berhasil! Kami telah mengirimkan tautan konfirmasi ke email Anda.\n\n"
              "Silakan periksa kotak masuk (atau folder spam) dan klik tautan tersebut sebelum melakukan login.",
              style: TextStyle(height: 1.5),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade900,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context); // Tutup dialog
                  Navigator.pop(context); // Kembali ke halaman Login
                },
                child: const Text("Kembali ke Login"),
              ),
            ],
          ),
        );
      } else {
        // Konfirmasi email Supabase NONAKTIF (user langsung mendapat session)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Registrasi Berhasil!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Kembali ke halaman Login
      }
    } catch (e) {
      String pesanError = e.toString();

      if (e is AuthException) {
        final msg = e.message.toLowerCase();
        if (msg.contains('already registered') ||
            msg.contains('already exists') ||
            msg.contains('sudah terdaftar')) {
          if (mounted) _dialogEmailTerdaftar();
          return;
        }
        pesanError = e.message;
      } else if (e is PostgrestException && e.code == '23505') {
        // Pelanggaran unique constraint di database
        if (e.message.toLowerCase().contains('email')) {
          if (mounted) _dialogEmailTerdaftar();
          return;
        }
        pesanError = "Data sudah terdaftar (NIK atau email sudah digunakan).";
      }

      if (mounted) {
        _tampilkanDialogPesan("Registrasi Gagal", pesanError, Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Registrasi Karyawan")),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  TextField(
                    controller: _fullNameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Nama Lengkap (Wajib)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nikCtrl,
                    decoration: const InputDecoration(
                      labelText: "NIK (Opsional)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<dynamic>(
                    decoration: const InputDecoration(
                      labelText: "Divisi",
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedDepartmentId,
                    items: _departments
                        .map(
                          (d) => DropdownMenuItem<dynamic>(
                            value: d['id'],
                            child: Text(d['name']),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedDepartmentId = val),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<dynamic>(
                    decoration: const InputDecoration(
                      labelText: "Role",
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedPositionId,
                    items: _positions
                        .map(
                          (p) => DropdownMenuItem<dynamic>(
                            value: p['id'],
                            child: Text(p['name']),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedPositionId = val),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: "Status Kerja (Wajib)",
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedStatus,
                    items: _statusKerjaOptions
                        .map(
                          (s) => DropdownMenuItem<String>(
                            value: s,
                            child: Text(s),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setState(() => _selectedStatus = val),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tanggalMasukCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: "Tanggal Join (Wajib)",
                      prefixIcon: Icon(Icons.calendar_today),
                      border: OutlineInputBorder(),
                    ),
                    onTap: () => _pilihTanggal(context),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: "Email (Wajib)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: "Password (Wajib)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _isSubmitting
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _register,
                          child: const Text(
                            "Daftar",
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                ],
              ),
            ),
    );
  }
}
