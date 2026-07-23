import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class WebKaryawanPage extends StatefulWidget {
  const WebKaryawanPage({super.key});

  @override
  State<WebKaryawanPage> createState() => _WebKaryawanPageState();
}

class _WebKaryawanPageState extends State<WebKaryawanPage> {
  List<dynamic> _karyawanList = [];
  List<dynamic> _filteredList = [];
  bool _isLoading = true;

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _horizontalScrollCtrl = ScrollController();

  int _rowsPerPage = 50;
  final List<int> _pageOptions = [50, 100, 200];

  @override
  void initState() {
    super.initState();
    _fetchKaryawan();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchKaryawan() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('employees')
          .select()
          .order('created_at', ascending: false);

      setState(() {
        _karyawanList = data;
        _filteredList = data;
      });
      _filterKaryawan(_searchCtrl.text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal mengambil data: $e',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterKaryawan(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredList = _karyawanList;
      } else {
        _filteredList = _karyawanList.where((item) {
          final name = (item['full_name'] ?? '').toLowerCase();
          return name.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Future<void> _deleteKaryawan(Map<String, dynamic> karyawan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Konfirmasi Hapus',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Yakin ingin menghapus data ${karyawan['full_name']}?',
          style: GoogleFonts.plusJakartaSans(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Batal',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Hapus',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client
            .from('employees')
            .delete()
            .eq('id', karyawan['id']);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Data berhasil dihapus',
                style: GoogleFonts.plusJakartaSans(fontSize: 12),
              ),
            ),
          );
          _fetchKaryawan();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Gagal menghapus: $e',
                style: GoogleFonts.plusJakartaSans(fontSize: 12),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showBiodataDialog(Map<String, dynamic> karyawan) {
    // Mendukung pengecekan 'children_data' maupun 'childern_data'
    String childDataText = '-';
    final cd = karyawan['children_data'] ?? karyawan['childern_data'];
    if (cd != null) {
      if (cd is Map) {
        childDataText =
            cd['info']?.toString() ??
            cd.values.where((v) => v != null).join(', ');
      } else {
        childDataText = cd.toString();
      }
    }

    String emergencyText = '-';
    final eName = karyawan['emergency_name'] ?? '';
    final ePhone = karyawan['emergency_phone'] ?? '';
    if (eName.toString().isNotEmpty || ePhone.toString().isNotEmpty) {
      emergencyText = '$eName ($ePhone)';
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 550),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.blueGrey[50],
                    backgroundImage: (karyawan['photo_url'] != null)
                        ? NetworkImage(karyawan['photo_url'])
                        : null,
                    child: (karyawan['photo_url'] == null)
                        ? const Icon(
                            Icons.person,
                            size: 36,
                            color: Colors.blueGrey,
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    karyawan['full_name'] ?? 'Nama Tidak Tersedia',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${karyawan['jabatan_name'] ?? karyawan['jabatan'] ?? '-'} | ${karyawan['role'] ?? '-'}',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.grey[700],
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _buildBiodataRow(
                              Icons.badge_outlined,
                              'NIK',
                              karyawan['nik'],
                            ),
                            _buildBiodataRow(
                              Icons.credit_card,
                              'No. KTP',
                              karyawan['ktp_number'],
                            ),
                            _buildBiodataRow(
                              Icons.cake,
                              'Tempat, Tgl Lahir',
                              '${karyawan['birth_place'] ?? '-'}, ${karyawan['birth_date'] ?? '-'}',
                            ),
                            _buildBiodataRow(
                              Icons.wc,
                              'Jenis Kelamin',
                              karyawan['gender'],
                            ),
                            _buildBiodataRow(
                              Icons.mosque,
                              'Agama',
                              karyawan['religion'],
                            ),
                            _buildBiodataRow(
                              Icons.school,
                              'Pendidikan',
                              karyawan['education'],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            _buildBiodataRow(
                              Icons.phone,
                              'No. Telepon',
                              karyawan['phone'],
                            ),
                            _buildBiodataRow(
                              Icons.location_on,
                              'Alamat KTP',
                              karyawan['address_ktp'],
                            ),
                            _buildBiodataRow(
                              Icons.home,
                              'Alamat Domisili',
                              karyawan['address_now'],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Divider(height: 1),
                            ),
                            _buildBiodataRow(
                              Icons.family_restroom,
                              'Status Menikah',
                              karyawan['marital_status'],
                            ),
                            _buildBiodataRow(
                              Icons.favorite,
                              'Nama Pasangan',
                              karyawan['spouse_name'],
                            ),
                            _buildBiodataRow(
                              Icons.child_care,
                              'Data Anak',
                              childDataText,
                            ),
                            _buildBiodataRow(
                              Icons.contact_phone,
                              'Kontak Darurat',
                              emergencyText,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        'Tutup',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBiodataRow(IconData icon, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.blueAccent),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value ?? '-',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Data Karyawan',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) =>
                        AddKaryawanDialog(onSuccess: _fetchKaryawan),
                  );
                },
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  'Tambah Karyawan',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: 320,
                height: 42,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _filterKaryawan,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Cari nama karyawan...',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 18,
                      color: Colors.grey,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 0,
                      horizontal: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Text(
                    'Tampilkan:',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButton<int>(
                      value: _rowsPerPage,
                      underline: const SizedBox(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                      items: _pageOptions.map((int value) {
                        return DropdownMenuItem<int>(
                          value: value,
                          child: Text(
                            '$value',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12),
                          ),
                        );
                      }).toList(),
                      onChanged: (int? newValue) {
                        if (newValue != null) {
                          setState(() => _rowsPerPage = newValue);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey[200]!),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredList.isEmpty
                  ? Center(
                      child: Text(
                        'Data karyawan tidak ditemukan.',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return Scrollbar(
                          controller: _horizontalScrollCtrl,
                          thumbVisibility: true,
                          trackVisibility: true,
                          child: SingleChildScrollView(
                            controller: _horizontalScrollCtrl,
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth > 1000
                                    ? constraints.maxWidth
                                    : 1000,
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: DataTable(
                                  showCheckboxColumn: false,
                                  columnSpacing:
                                      25, // <-- TAMBAHKAN INI AGAR JARAK ANTAR KOLOM MERAPAT
                                  horizontalMargin:
                                      16, // <-- TAMBAHKAN INI AGAR PADDING KIRI/KANAN PAS
                                  headingRowColor: WidgetStateProperty.all(
                                    Colors.grey[50],
                                  ),
                                  dataRowMaxHeight: 48,
                                  headingTextStyle: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  dataTextStyle: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: Colors.black87,
                                  ),
                                  columns: const [
                                    DataColumn(label: Text('No')),
                                    DataColumn(label: Text('Foto')),
                                    DataColumn(label: Text('NIK')),
                                    DataColumn(label: Text('Nama Lengkap')),
                                    DataColumn(label: Text('No. KTP')),
                                    DataColumn(label: Text('No. HP')),
                                    DataColumn(label: Text('Action')),
                                  ],
                                  rows: List<DataRow>.generate(
                                    _filteredList.length > _rowsPerPage
                                        ? _rowsPerPage
                                        : _filteredList.length,
                                    (index) {
                                      final karyawan = _filteredList[index];
                                      return DataRow(
                                        onSelectChanged: (selected) {
                                          if (selected != null && selected) {
                                            _showBiodataDialog(karyawan);
                                          }
                                        },
                                        cells: [
                                          DataCell(Text('${index + 1}')),
                                          DataCell(
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor:
                                                  Colors.blueGrey[50],
                                              backgroundImage:
                                                  (karyawan['photo_url'] !=
                                                      null)
                                                  ? NetworkImage(
                                                      karyawan['photo_url'],
                                                    )
                                                  : null,
                                              child:
                                                  (karyawan['photo_url'] ==
                                                      null)
                                                  ? const Icon(
                                                      Icons.person,
                                                      color: Colors.blueGrey,
                                                      size: 16,
                                                    )
                                                  : null,
                                            ),
                                          ),
                                          DataCell(
                                            Text(karyawan['nik'] ?? '-'),
                                          ),
                                          DataCell(
                                            Text(
                                              karyawan['full_name'] ?? '-',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(karyawan['ktp_number'] ?? '-'),
                                          ),
                                          DataCell(
                                            Text(karyawan['phone'] ?? '-'),
                                          ),
                                          DataCell(
                                            PopupMenuButton<String>(
                                              icon: const Icon(
                                                Icons.more_vert,
                                                color: Colors.black54,
                                                size: 18,
                                              ),
                                              tooltip: 'Pilihan Tindakan',
                                              onSelected: (value) {
                                                if (value == 'detail') {
                                                  _showBiodataDialog(karyawan);
                                                }
                                                if (value == 'edit') {
                                                  showDialog(
                                                    context: context,
                                                    barrierDismissible: false,
                                                    builder: (context) =>
                                                        EditKaryawanDialog(
                                                          karyawan: karyawan,
                                                          onSuccess:
                                                              _fetchKaryawan,
                                                        ),
                                                  );
                                                }
                                                if (value == 'delete') {
                                                  _deleteKaryawan(karyawan);
                                                }
                                              },
                                              itemBuilder: (context) => [
                                                PopupMenuItem(
                                                  value: 'detail',
                                                  child: ListTile(
                                                    leading: const Icon(
                                                      Icons
                                                          .contact_page_outlined,
                                                      color: Colors.green,
                                                      size: 16,
                                                    ),
                                                    title: Text(
                                                      'Lihat Biodata',
                                                      style:
                                                          GoogleFonts.plusJakartaSans(
                                                            fontSize: 12,
                                                          ),
                                                    ),
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    dense: true,
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'edit',
                                                  child: ListTile(
                                                    leading: const Icon(
                                                      Icons.edit_outlined,
                                                      color: Colors.blue,
                                                      size: 16,
                                                    ),
                                                    title: Text(
                                                      'Edit Data',
                                                      style:
                                                          GoogleFonts.plusJakartaSans(
                                                            fontSize: 12,
                                                          ),
                                                    ),
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    dense: true,
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'delete',
                                                  child: ListTile(
                                                    leading: const Icon(
                                                      Icons.delete_outline,
                                                      color: Colors.red,
                                                      size: 16,
                                                    ),
                                                    title: Text(
                                                      'Hapus Data',
                                                      style:
                                                          GoogleFonts.plusJakartaSans(
                                                            fontSize: 12,
                                                          ),
                                                    ),
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    dense: true,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// WIDGET TAMBAH KARYAWAN
// ============================================================================
class AddKaryawanDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const AddKaryawanDialog({super.key, required this.onSuccess});

  @override
  State<AddKaryawanDialog> createState() => _AddKaryawanDialogState();
}

class _AddKaryawanDialogState extends State<AddKaryawanDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  final _nikCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _ktpCtrl = TextEditingController();
  final _npwpCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _birthPlaceCtrl = TextEditingController();
  final _birthDateCtrl = TextEditingController();
  final _addrNowCtrl = TextEditingController();
  final _addrKtpCtrl = TextEditingController();
  final _jabatanCtrl = TextEditingController();
  final _spouseNameCtrl = TextEditingController();
  final _childrenCountCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  String? _selectedGender;
  String? _selectedRole;
  String? _selectedEducation;
  String? _selectedReligion;
  String? _selectedStatus;

  final List<String> _genderList = ['Laki-laki', 'Perempuan'];
  final List<String> _roleList = ['Admin', 'Staff', 'Supervisor', 'Manager'];
  final List<String> _educationList = ['SMA/SMK', 'D3', 'S1', 'S2'];
  final List<String> _religionList = [
    'Islam',
    'Kristen',
    'Katolik',
    'Hindu',
    'Buddha',
    'Konghucu',
  ];
  final List<String> _statusList = ['Belum Menikah', 'Menikah', 'Cerai'];

  // Fungsi helper untuk menentukan position_id berdasarkan role
  int _getPositionId(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin':
        return 1;
      case 'staff':
        return 3;
      case 'supervisor':
        return 2;
      case 'manager':
        return 4;
      default:
        return 3; // Default ke Staff jika kosong
    }
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client.from('employees').insert({
        'nik': _nikCtrl.text,
        'full_name': _nameCtrl.text,
        'gender': _selectedGender,
        'ktp_number': _ktpCtrl.text,
        'npwp_number': _npwpCtrl.text,
        'phone': _phoneCtrl.text,
        'birth_place': _birthPlaceCtrl.text,
        'birth_date': _birthDateCtrl.text,
        'address_ktp': _addrKtpCtrl.text,
        'address_now': _addrNowCtrl.text,
        'education': _selectedEducation,
        'religion': _selectedReligion,
        'marital_status': _selectedStatus,
        'jabatan_name': _jabatanCtrl.text,
        'role': _selectedRole,
        'position_id': _getPositionId(_selectedRole), // Mapping posisi otomatis
        'spouse_name': _spouseNameCtrl.text,
        'children_data': {
          'info': _childrenCountCtrl.text,
        }, // Menggunakan children_data
        'emergency_name': _emergencyNameCtrl.text,
        'emergency_phone': _emergencyPhoneCtrl.text,
      });
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Karyawan berhasil ditambahkan!',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal menyimpan: $e',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1995, 1, 1),
      firstDate: DateTime(1945),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        String day = picked.day.toString().padLeft(2, '0');
        String month = picked.month.toString().padLeft(2, '0');
        String year = picked.year.toString();
        _birthDateCtrl.text = "$day-$month-$year";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.person_add,
                    color: Colors.blue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Tambah Karyawan Baru',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(),
            ),

            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      _buildTextField(_nikCtrl, 'NIK', isRequired: true),
                      _buildTextField(
                        _nameCtrl,
                        'Nama Lengkap',
                        isRequired: true,
                      ),
                      _buildDropdown(
                        'Jenis Kelamin (Gender)',
                        _genderList,
                        _selectedGender,
                        (val) => setState(() => _selectedGender = val),
                      ),
                      _buildTextField(_birthPlaceCtrl, 'Tempat Lahir'),
                      _buildTextField(
                        _birthDateCtrl,
                        'Tanggal Lahir',
                        readOnly: true,
                        onTap: () => _selectDate(context),
                        suffixIcon: const Icon(
                          Icons.calendar_today,
                          color: Colors.black54,
                          size: 16,
                        ),
                      ),
                      _buildDropdown(
                        'Agama',
                        _religionList,
                        _selectedReligion,
                        (val) => setState(() => _selectedReligion = val),
                      ),

                      _buildTextField(_ktpCtrl, 'Nomor KTP', isRequired: true),
                      _buildTextField(_npwpCtrl, 'Nomor NPWP'),
                      _buildTextField(_phoneCtrl, 'Nomor HP', isRequired: true),
                      _buildTextField(
                        _addrKtpCtrl,
                        'Alamat Sesuai KTP',
                        isFullWidth: true,
                      ),
                      _buildTextField(
                        _addrNowCtrl,
                        'Alamat Domisili',
                        isFullWidth: true,
                      ),

                      _buildDropdown(
                        'Pendidikan Terakhir',
                        _educationList,
                        _selectedEducation,
                        (val) => setState(() => _selectedEducation = val),
                      ),
                      _buildTextField(
                        _jabatanCtrl,
                        'Jabatan',
                        isRequired: true,
                      ),
                      _buildDropdown(
                        'Role (Akses App)',
                        _roleList,
                        _selectedRole,
                        (val) => setState(() => _selectedRole = val),
                      ),

                      _buildDropdown(
                        'Status Pernikahan',
                        _statusList,
                        _selectedStatus,
                        (val) => setState(() => _selectedStatus = val),
                      ),
                      _buildTextField(_spouseNameCtrl, 'Nama Istri/Suami'),
                      _buildTextField(
                        _childrenCountCtrl,
                        'Data Anak (Jumlah/Nama)',
                      ),
                      _buildTextField(
                        _emergencyNameCtrl,
                        'Nama Kontak Darurat',
                      ),
                      _buildTextField(
                        _emergencyPhoneCtrl,
                        'No. HP Kontak Darurat',
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    'Batal',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveData,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Simpan Data',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label, {
    bool isRequired = false,
    bool isFullWidth = false,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
  }) {
    return SizedBox(
      width: isFullWidth ? double.infinity : 350,
      child: TextFormField(
        controller: ctrl,
        readOnly: readOnly,
        onTap: onTap,
        style: GoogleFonts.plusJakartaSans(fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.plusJakartaSans(
            color: Colors.black54,
            fontSize: 12,
          ),
          filled: true,
          fillColor: Colors.grey[50],
          suffixIcon: suffixIcon,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
        ),
        validator: isRequired
            ? (val) => val == null || val.isEmpty ? 'Wajib diisi' : null
            : null,
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String? val,
    ValueChanged<String?> onChanged,
  ) {
    return SizedBox(
      width: 350,
      child: DropdownButtonFormField<String>(
        value: val,
        items: items
            .map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(
                  e,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12),
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.black87),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.plusJakartaSans(
            color: Colors.black54,
            fontSize: 12,
          ),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// WIDGET EDIT KARYAWAN
// ============================================================================
class EditKaryawanDialog extends StatefulWidget {
  final Map<String, dynamic> karyawan;
  final VoidCallback onSuccess;
  const EditKaryawanDialog({
    super.key,
    required this.karyawan,
    required this.onSuccess,
  });

  @override
  State<EditKaryawanDialog> createState() => _EditKaryawanDialogState();
}

class _EditKaryawanDialogState extends State<EditKaryawanDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  late TextEditingController _nikCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _ktpCtrl;
  late TextEditingController _npwpCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _birthPlaceCtrl;
  late TextEditingController _birthDateCtrl;
  late TextEditingController _addrNowCtrl;
  late TextEditingController _addrKtpCtrl;
  late TextEditingController _jabatanCtrl;
  late TextEditingController _spouseNameCtrl;
  late TextEditingController _childrenCountCtrl;
  late TextEditingController _emergencyNameCtrl;
  late TextEditingController _emergencyPhoneCtrl;

  String? _selectedGender;
  String? _selectedRole;
  String? _selectedEducation;
  String? _selectedReligion;
  String? _selectedStatus;

  final List<String> _genderList = ['Laki-laki', 'Perempuan'];
  final List<String> _roleList = ['Admin', 'Staff', 'Supervisor', 'Manager'];
  final List<String> _educationList = ['SMA/SMK', 'D3', 'S1', 'S2'];
  final List<String> _religionList = [
    'Islam',
    'Kristen',
    'Katolik',
    'Hindu',
    'Buddha',
    'Konghucu',
  ];
  final List<String> _statusList = ['Belum Menikah', 'Menikah', 'Cerai'];

  String? _getSafeDropdownValue(List<String> list, dynamic dbValue) {
    if (dbValue == null || dbValue.toString().trim().isEmpty) return null;
    final stringValue = dbValue.toString().toLowerCase();
    for (var item in list) {
      if (item.toLowerCase() == stringValue) {
        return item;
      }
    }
    return null;
  }

  int _getPositionId(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin':
        return 1;
      case 'staff':
        return 2;
      case 'supervisor':
        return 3;
      case 'manager':
        return 4;
      default:
        return 2;
    }
  }

  @override
  void initState() {
    super.initState();
    _nikCtrl = TextEditingController(
      text: widget.karyawan['nik']?.toString() ?? '',
    );
    _nameCtrl = TextEditingController(
      text: widget.karyawan['full_name']?.toString() ?? '',
    );
    _ktpCtrl = TextEditingController(
      text: widget.karyawan['ktp_number']?.toString() ?? '',
    );
    _npwpCtrl = TextEditingController(
      text: widget.karyawan['npwp_number']?.toString() ?? '',
    );
    _phoneCtrl = TextEditingController(
      text: widget.karyawan['phone']?.toString() ?? '',
    );
    _birthPlaceCtrl = TextEditingController(
      text: widget.karyawan['birth_place']?.toString() ?? '',
    );
    _birthDateCtrl = TextEditingController(
      text: widget.karyawan['birth_date']?.toString() ?? '',
    );
    _addrNowCtrl = TextEditingController(
      text: widget.karyawan['address_now']?.toString() ?? '',
    );
    _addrKtpCtrl = TextEditingController(
      text: widget.karyawan['address_ktp']?.toString() ?? '',
    );
    _jabatanCtrl = TextEditingController(
      text:
          (widget.karyawan['jabatan_name'] ?? widget.karyawan['jabatan'])
              ?.toString() ??
          '',
    );
    _spouseNameCtrl = TextEditingController(
      text: widget.karyawan['spouse_name']?.toString() ?? '',
    );

    // PARSING DATA ANAK (Mendukung 'children_data' maupun 'childern_data')
    String initChildData = '';
    final cd =
        widget.karyawan['children_data'] ?? widget.karyawan['childern_data'];
    if (cd != null) {
      if (cd is Map) {
        initChildData =
            cd['info']?.toString() ??
            cd.values.where((v) => v != null).join(', ');
      } else if (cd is List) {
        initChildData = cd.join(', ');
      } else {
        initChildData = cd.toString();
      }
    }
    _childrenCountCtrl = TextEditingController(text: initChildData);

    _emergencyNameCtrl = TextEditingController(
      text: widget.karyawan['emergency_name']?.toString() ?? '',
    );
    _emergencyPhoneCtrl = TextEditingController(
      text: widget.karyawan['emergency_phone']?.toString() ?? '',
    );

    _selectedGender = _getSafeDropdownValue(
      _genderList,
      widget.karyawan['gender'],
    );
    _selectedRole = _getSafeDropdownValue(_roleList, widget.karyawan['role']);
    _selectedEducation = _getSafeDropdownValue(
      _educationList,
      widget.karyawan['education'],
    );
    _selectedReligion = _getSafeDropdownValue(
      _religionList,
      widget.karyawan['religion'],
    );
    _selectedStatus = _getSafeDropdownValue(
      _statusList,
      widget.karyawan['marital_status'],
    );
  }

  @override
  void dispose() {
    _nikCtrl.dispose();
    _nameCtrl.dispose();
    _ktpCtrl.dispose();
    _npwpCtrl.dispose();
    _phoneCtrl.dispose();
    _birthPlaceCtrl.dispose();
    _birthDateCtrl.dispose();
    _addrNowCtrl.dispose();
    _addrKtpCtrl.dispose();
    _jabatanCtrl.dispose();
    _spouseNameCtrl.dispose();
    _childrenCountCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateData() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client
          .from('employees')
          .update({
            'nik': _nikCtrl.text,
            'full_name': _nameCtrl.text,
            'gender': _selectedGender,
            'ktp_number': _ktpCtrl.text,
            'npwp_number': _npwpCtrl.text,
            'address_ktp': _addrKtpCtrl.text,
            'phone': _phoneCtrl.text,
            'birth_place': _birthPlaceCtrl.text,
            'birth_date': _birthDateCtrl.text,
            'address_now': _addrNowCtrl.text,
            'education': _selectedEducation,
            'religion': _selectedReligion,
            'marital_status': _selectedStatus,
            'jabatan_name': _jabatanCtrl.text,
            'role': _selectedRole,
            'position_id': _getPositionId(
              _selectedRole,
            ), // Update position_id otomatis
            'spouse_name': _spouseNameCtrl.text,
            'children_data': {
              'info': _childrenCountCtrl.text,
            }, // Menggunakan children_data
            'emergency_name': _emergencyNameCtrl.text,
            'emergency_phone': _emergencyPhoneCtrl.text,
          })
          .eq('id', widget.karyawan['id']);

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Data berhasil diubah!',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal update: $e',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1995, 1, 1),
      firstDate: DateTime(1945),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        String day = picked.day.toString().padLeft(2, '0');
        String month = picked.month.toString().padLeft(2, '0');
        String year = picked.year.toString();
        _birthDateCtrl.text = "$day-$month-$year";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.edit_note,
                    color: Colors.orange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Edit Data Karyawan',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(),
            ),

            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      _buildTextField(_nikCtrl, 'NIK', isRequired: true),
                      _buildTextField(
                        _nameCtrl,
                        'Nama Lengkap',
                        isRequired: true,
                      ),
                      _buildDropdown(
                        'Jenis Kelamin (Gender)',
                        _genderList,
                        _selectedGender,
                        (val) => setState(() => _selectedGender = val),
                      ),
                      _buildTextField(_birthPlaceCtrl, 'Tempat Lahir'),
                      _buildTextField(
                        _birthDateCtrl,
                        'Tanggal Lahir',
                        readOnly: true,
                        onTap: () => _selectDate(context),
                        suffixIcon: const Icon(
                          Icons.calendar_today,
                          color: Colors.black54,
                          size: 16,
                        ),
                      ),
                      _buildDropdown(
                        'Agama',
                        _religionList,
                        _selectedReligion,
                        (val) => setState(() => _selectedReligion = val),
                      ),

                      _buildTextField(_ktpCtrl, 'Nomor KTP', isRequired: true),
                      _buildTextField(_npwpCtrl, 'Nomor NPWP'),
                      _buildTextField(_phoneCtrl, 'Nomor HP', isRequired: true),
                      _buildTextField(
                        _addrKtpCtrl,
                        'Alamat Sesuai KTP',
                        isFullWidth: true,
                      ),
                      _buildTextField(
                        _addrNowCtrl,
                        'Alamat Domisili',
                        isFullWidth: true,
                      ),

                      _buildDropdown(
                        'Pendidikan Terakhir',
                        _educationList,
                        _selectedEducation,
                        (val) => setState(() => _selectedEducation = val),
                      ),
                      _buildTextField(
                        _jabatanCtrl,
                        'Jabatan',
                        isRequired: true,
                      ),
                      _buildDropdown(
                        'Role (Akses App)',
                        _roleList,
                        _selectedRole,
                        (val) => setState(() => _selectedRole = val),
                      ),

                      _buildDropdown(
                        'Status Pernikahan',
                        _statusList,
                        _selectedStatus,
                        (val) => setState(() => _selectedStatus = val),
                      ),
                      _buildTextField(_spouseNameCtrl, 'Nama Istri/Suami'),
                      _buildTextField(
                        _childrenCountCtrl,
                        'Data Anak (Jumlah/Nama)',
                      ),
                      _buildTextField(
                        _emergencyNameCtrl,
                        'Nama Kontak Darurat',
                      ),
                      _buildTextField(
                        _emergencyPhoneCtrl,
                        'No. HP Kontak Darurat',
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    'Batal',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isSaving ? null : _updateData,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Simpan Perubahan',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label, {
    bool isRequired = false,
    bool isFullWidth = false,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
  }) {
    return SizedBox(
      width: isFullWidth ? double.infinity : 350,
      child: TextFormField(
        controller: ctrl,
        readOnly: readOnly,
        onTap: onTap,
        style: GoogleFonts.plusJakartaSans(fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.plusJakartaSans(
            color: Colors.black54,
            fontSize: 12,
          ),
          filled: true,
          fillColor: Colors.grey[50],
          suffixIcon: suffixIcon,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
        ),
        validator: isRequired
            ? (val) => val == null || val.isEmpty ? 'Wajib diisi' : null
            : null,
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String? val,
    ValueChanged<String?> onChanged,
  ) {
    return SizedBox(
      width: 350,
      child: DropdownButtonFormField<String>(
        value: val,
        items: items
            .map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(
                  e,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12),
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.black87),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.plusJakartaSans(
            color: Colors.black54,
            fontSize: 12,
          ),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
        ),
      ),
    );
  }
}
