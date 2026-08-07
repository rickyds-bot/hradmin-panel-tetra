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

  Future<void> _register() async {
    // Tambahkan validasi password juga di sini agar lebih aman
    if (_emailCtrl.text.isEmpty ||
        _passwordCtrl.text.isEmpty ||
        _selectedStatus == null ||
        _tanggalMasukCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lengkapi data yang wajib!")),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final authResponse = await Supabase.instance.client.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );

      final user = authResponse.user;

      if (user != null) {
        final Map<String, dynamic> insertData = {
          'email': _emailCtrl.text.trim(),
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

        // Simpan data profil ke tabel employees
        await Supabase.instance.client.from('employees').insert(insertData);

        if (!mounted) return;

        // --- LOGIKA BARU: CEK KONFIRMASI EMAIL ---
        if (authResponse.session == null) {
          // Jika session null, artinya Supabase mewajibkan konfirmasi email
          showDialog(
            context: context,
            barrierDismissible: false, // User tidak bisa menutup sembarangan
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
          // Jika fitur konfirmasi email Supabase dalam keadaan NONAKTIF (user langsung mendapat session)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Registrasi Berhasil!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context); // Kembali ke halaman Login
        }
        // ------------------------------------------
      }
    } catch (e) {
      String pesanError = e.toString();

      // Cek apakah error berasal dari Supabase Auth
      if (e is AuthException) {
        // Jika pesan error mengandung kata kunci email sudah terdaftar
        if (e.message.toLowerCase().contains('already registered') ||
            e.message.toLowerCase().contains('already exists') ||
            e.message.toLowerCase().contains('sudah terdaftar')) {
          pesanError =
              "Alamat email ini sudah terdaftar. Silakan gunakan email lain atau langsung Login.";
        } else {
          // Tampilkan pesan error bawaan Supabase jika error lainnya (misal password kurang dari 6 karakter)
          pesanError = e.message;
        }
      }

      // Tampilkan dialog gagal menggunakan fungsi yang sudah Anda buat
      _tampilkanDialogPesan("Registrasi Gagal", pesanError, Colors.red);
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
