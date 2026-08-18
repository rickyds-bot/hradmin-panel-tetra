import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

class AdminPage extends StatefulWidget {
  const AdminPage({Key? key}) : super(key: key);

  @override
  _AdminPageState createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          title: const Text(
            "Admin Tetra",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
                Navigator.pushReplacementNamed(context, '/');
              },
            ),
          ],
          bottom: const TabBar(
            isScrollable: false,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            labelPadding: EdgeInsets.symmetric(horizontal: 4),
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: "Karyawan"),
              Tab(text: "Aktifitas"),
              Tab(text: "Pengajuan"),
              Tab(text: "Lokasi"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            KaryawanTab(),
            AktivitasTab(),
            PengajuanTab(),
            LokasiTab(),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// TAB 1: KARYAWAN (DENGAN POPUP DETAIL SESUAI WEB)
// ==========================================
class KaryawanTab extends StatefulWidget {
  const KaryawanTab({Key? key}) : super(key: key);
  @override
  _KaryawanTabState createState() => _KaryawanTabState();
}

class _KaryawanTabState extends State<KaryawanTab> {
  String _search = "";
  late Future<List<Map<String, dynamic>>> _karyawanFuture;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() {
      _karyawanFuture = Supabase.instance.client
          .from('employees')
          .select()
          .order('full_name', ascending: true);
    });
  }

  void _viewDetail(Map<String, dynamic> karyawan) {
    showDialog(
      context: context,
      builder: (context) => _DetailKaryawanDialog(karyawan: karyawan),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: const InputDecoration(
              hintText: "Cari nama atau NIK karyawan...",
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _karyawanFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("Tidak ada data karyawan."));
                }
                final list = snapshot.data!.where((e) {
                  final name = (e['full_name'] ?? '').toString().toLowerCase();
                  final nik = (e['nik'] ?? '').toString().toLowerCase();
                  final query = _search.toLowerCase();
                  return name.contains(query) || nik.contains(query);
                }).toList();

                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final dataKaryawan = list[i];
                    final rawPhoto = dataKaryawan['photo_url'];
                    final photoUrl = (rawPhoto != null &&
                            rawPhoto.toString().trim().isNotEmpty &&
                            rawPhoto.toString().startsWith('http'))
                        ? rawPhoto.toString()
                        : null;

                    String rawEmpStatus = dataKaryawan['employee_status']
                            ?.toString()
                            .toLowerCase() ??
                        'tetap';
                    String displayStatus = 'Tetap';
                    if (rawEmpStatus == 'kontrak') {
                      displayStatus = 'Kontrak';
                    } else if (rawEmpStatus == 'magang') {
                      displayStatus = 'Magang';
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.blue.shade100,
                          backgroundImage:
                              photoUrl != null ? NetworkImage(photoUrl) : null,
                          child: photoUrl == null
                              ? const Icon(
                                  Icons.person,
                                  color: Colors.blue,
                                  size: 20,
                                )
                              : null,
                        ),
                        title: Text(
                          dataKaryawan['full_name'] ?? 'Tanpa Nama',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          "${dataKaryawan['nik'] ?? 'NIK Kosong'} • $displayStatus",
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () => _viewDetail(dataKaryawan),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// POPUP DETAIL / FULL BIODATA KARYAWAN
// ============================================================================
class _DetailKaryawanDialog extends StatefulWidget {
  final Map<String, dynamic> karyawan;
  const _DetailKaryawanDialog({required this.karyawan});

  @override
  State<_DetailKaryawanDialog> createState() => _DetailKaryawanDialogState();
}

class _DetailKaryawanDialogState extends State<_DetailKaryawanDialog> {
  bool _isLoadingContracts = true;
  List<dynamic> _contractHistory = [];

  @override
  void initState() {
    super.initState();
    _fetchContractHistory();
  }

  Future<void> _fetchContractHistory() async {
    try {
      final res = await Supabase.instance.client
          .from('employee_contracts')
          .select()
          .eq('employee_id', widget.karyawan['id'])
          .order('contract_start', ascending: false);

      setState(() {
        _contractHistory = res;
        _isLoadingContracts = false;
      });
    } catch (_) {
      setState(() => _isLoadingContracts = false);
    }
  }

  Future<void> _downloadFile(String? fileUrl) async {
    if (fileUrl != null && fileUrl.isNotEmpty) {
      final uri = Uri.parse(fileUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty || dateStr == 'null') return '-';
    try {
      final dt = DateTime.parse(
          dateStr.contains('T') ? dateStr.split('T')[0] : dateStr);
      return DateFormat('dd-MM-yyyy').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- PERBAIKAN FORMAT DATA ANAK ---
    String childrenStr = '-';
    final rawChildrenData = widget.karyawan['children_data'];

    if (rawChildrenData != null &&
        rawChildrenData.toString().trim().isNotEmpty) {
      try {
        List<dynamic> childrenList = [];

        // Cek apakah data berupa String JSON atau sudah berupa List (JSONB dari Supabase)
        if (rawChildrenData is String) {
          childrenList = jsonDecode(rawChildrenData);
        } else if (rawChildrenData is List) {
          childrenList = rawChildrenData;
        }

        if (childrenList.isNotEmpty) {
          List<String> formattedList = [];
          for (int i = 0; i < childrenList.length; i++) {
            final child = childrenList[i];
            final name = child['name'] ?? 'Tanpa Nama';
            // Bisa menggunakan fungsi _formatDate yang sudah ada agar format tanggal seragam
            final birthDate = child['birth_date'] != null
                ? _formatDate(child['birth_date'])
                : '-';

            formattedList.add('${i + 1}. $name ($birthDate)');
          }
          childrenStr = formattedList.join('\n');
        }
      } catch (e) {
        // Jika gagal parse JSON (data tidak valid), kembalikan ke teks aslinya
        childrenStr = rawChildrenData.toString();
      }
    }

    final photoUrl = widget.karyawan['photo_url'] ?? widget.karyawan['photo'];

    String rawEmpStatus =
        widget.karyawan['employee_status']?.toString().toLowerCase() ?? 'tetap';
    String displayStatus = 'Tetap';
    if (rawEmpStatus == 'kontrak') {
      displayStatus = 'Kontrak';
    } else if (rawEmpStatus == 'magang') {
      displayStatus = 'Magang';
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 650),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Detail Biodata Karyawan & Riwayat',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 35,
                            backgroundColor: Colors.blue[100],
                            backgroundImage: (photoUrl != null &&
                                    photoUrl.toString().isNotEmpty)
                                ? NetworkImage(photoUrl.toString())
                                : null,
                            child: (photoUrl == null ||
                                    photoUrl.toString().isEmpty)
                                ? const Icon(Icons.person,
                                    size: 35, color: Colors.blue)
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.karyawan['full_name'] ?? '-',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            widget.karyawan['jabatan_name'] ?? '-',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSectionTitle('Informasi Akun & Pekerjaan'),
                    _buildInfoRow('NIK', widget.karyawan['nik']),
                    _buildInfoRow('Email', widget.karyawan['email']),
                    _buildInfoRow('No. Telepon', widget.karyawan['phone']),
                    _buildInfoRow('Jabatan', widget.karyawan['jabatan_name']),
                    _buildInfoRow('Status Karyawan', displayStatus),
                    _buildInfoRow(
                        'Status Akun',
                        (widget.karyawan['is_active'] ?? true)
                            ? 'Aktif'
                            : 'Non-Aktif'),
                    if (displayStatus.toLowerCase() == 'kontrak' ||
                        displayStatus.toLowerCase() == 'magang') ...[
                      _buildInfoRow(
                          'No. Kontrak', widget.karyawan['contract_number']),
                      _buildInfoRow('Mulai Periode',
                          _formatDate(widget.karyawan['contract_start'])),
                      _buildInfoRow('Selesai Periode',
                          _formatDate(widget.karyawan['contract_end'])),
                    ],
                    if (displayStatus.toLowerCase() == 'kontrak' &&
                        widget.karyawan['contract_file'] != null &&
                        widget.karyawan['contract_file'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 140,
                              child: Text('Surat Kontrak',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w500)),
                            ),
                            const Text(': '),
                            ElevatedButton.icon(
                              onPressed: () => _downloadFile(
                                  widget.karyawan['contract_file']),
                              icon: const Icon(Icons.download, size: 14),
                              label: const Text('Download Dokumen PDF',
                                  style: TextStyle(fontSize: 11)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(0, 30)),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    _buildSectionTitle('Informasi Pribadi & Identitas'),
                    _buildInfoRow('Jenis Kelamin', widget.karyawan['gender']),
                    _buildInfoRow('Agama', widget.karyawan['religion']),
                    _buildInfoRow('Tempat, Tgl Lahir',
                        '${widget.karyawan['birth_place'] ?? '-'}, ${_formatDate(widget.karyawan['birth_date'])}'),
                    _buildInfoRow('Nomor KTP', widget.karyawan['ktp_number']),
                    _buildInfoRow('Nomor NPWP', widget.karyawan['npwp_number']),
                    _buildInfoRow('Pendidikan', widget.karyawan['education']),
                    const SizedBox(height: 12),
                    _buildSectionTitle('Alamat & Keluarga (Termasuk Anak)'),
                    _buildInfoRow('Alamat KTP', widget.karyawan['address_ktp']),
                    _buildInfoRow(
                        'Alamat Domisili', widget.karyawan['address_now']),
                    _buildInfoRow(
                        'Status Pernikahan', widget.karyawan['marital_status']),
                    _buildInfoRow(
                        'Nama Pasangan', widget.karyawan['spouse_name']),
                    _buildInfoRow('Tgl Lahir Pasangan',
                        _formatDate(widget.karyawan['spouse_birth_date'])),
                    _buildInfoRow('Data Anak', childrenStr),
                    const SizedBox(height: 12),
                    _buildSectionTitle('Kontak Darurat'),
                    _buildInfoRow('Nama Kontak Darurat',
                        widget.karyawan['emergency_name']),
                    _buildInfoRow('Telp Kontak Darurat',
                        widget.karyawan['emergency_phone']),
                    const SizedBox(height: 12),
                    _buildSectionTitle('Riwayat Kontrak / Perubahan Status'),
                    _isLoadingContracts
                        ? const Center(child: CircularProgressIndicator())
                        : _contractHistory.isEmpty
                            ? Text(
                                displayStatus == 'Tetap'
                                    ? 'Karyawan langsung berstatus Tetap (Tidak ada riwayat kontrak sebelumnya).'
                                    : 'Belum ada riwayat kontrak.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _contractHistory.length,
                                itemBuilder: (context, index) {
                                  final c = _contractHistory[index];
                                  return Card(
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: ListTile(
                                      dense: true,
                                      title: Text(
                                          'Periode: ${_formatDate(c['contract_start'])} s/d ${_formatDate(c['contract_end'])}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold)),
                                      trailing: c['contract_file'] != null &&
                                              c['contract_file']
                                                  .toString()
                                                  .isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.download,
                                                  color: Colors.teal, size: 18),
                                              onPressed: () => _downloadFile(
                                                  c['contract_file']),
                                            )
                                          : const Text('Tanpa Dokumen / Magang',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey)),
                                    ),
                                  );
                                },
                              ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, top: 6.0),
      child: Text(
        title,
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue[800]),
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500)),
          ),
          const Text(': '),
          Expanded(
            child: Text(
                value?.toString().isNotEmpty == true ? value.toString() : '-',
                style: const TextStyle(fontSize: 12, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TAB 2: AKTIVITAS (DENGAN FILTER TANGGAL, NAMA & LIMIT 30)
// ==========================================
class AktivitasTab extends StatefulWidget {
  const AktivitasTab({Key? key}) : super(key: key);
  @override
  _AktivitasTabState createState() => _AktivitasTabState();
}

class _AktivitasTabState extends State<AktivitasTab> {
  String _search = "";
  DateTime? _startDate;
  DateTime? _endDate;

  late Future<List<Map<String, dynamic>>> _aktivitasFuture;
  List<Map<String, dynamic>> _employeeList = [];

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    try {
      final empResponse = await Supabase.instance.client
          .from('employees')
          .select('id, full_name');

      // 1. Inisialisasi query dasar tanpa order()
      var query = Supabase.instance.client.from('attendance').select();

      // 2. Masukkan filter tanggal TERLEBIH DAHULU (jika ada)
      if (_startDate != null && _endDate != null) {
        final startStr = DateFormat('yyyy-MM-dd').format(_startDate!);
        final endStr = DateFormat('yyyy-MM-dd').format(_endDate!);
        query = query
            .gte('created_at', '${startStr}T00:00:00')
            .lte('created_at', '${endStr}T23:59:59');
      }

      // 3. Setelah filter selesai, BARU terapkan order() dan limit()
      final attResponse =
          await query.order('created_at', ascending: false).limit(30);

      if (mounted) {
        setState(() {
          _employeeList = List<Map<String, dynamic>>.from(empResponse);
          _aktivitasFuture =
              Future.value(List<Map<String, dynamic>>.from(attResponse));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aktivitasFuture = Future.error(e);
        });
      }
    }
  }

  String _getEmployeeName(dynamic id) {
    if (id == null) return "Tanpa Nama";
    final match = _employeeList.firstWhere(
      (emp) => emp['id'].toString() == id.toString(),
      orElse: () => <String, dynamic>{},
    );
    return match['full_name'] ?? "Tanpa Nama";
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: "Cari nama/status...",
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(
                  _startDate == null
                      ? "Filter Tgl"
                      : "${DateFormat('dd/MM').format(_startDate!)} - ${DateFormat('dd/MM').format(_endDate!)}",
                  style: const TextStyle(fontSize: 11),
                ),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    )),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                    initialDateRange: _startDate != null
                        ? DateTimeRange(start: _startDate!, end: _endDate!)
                        : null,
                  );
                  if (picked != null) {
                    setState(() {
                      _startDate = picked.start;
                      _endDate = picked.end;
                    });
                    _refreshData();
                  }
                },
              ),
              if (_startDate != null)
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.red, size: 20),
                  onPressed: () {
                    setState(() {
                      _startDate = null;
                      _endDate = null;
                    });
                    _refreshData();
                  },
                )
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _aktivitasFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      "Error Supabase: ${snapshot.error}",
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("Tidak ada data aktivitas."));
                }

                // Filter nama/status pada sisi UI berdasarkan 30 baris yang di-fetch
                final list = snapshot.data!.where((e) {
                  final empName = _getEmployeeName(e['employee_id']);
                  final status = e['status'] ?? '';
                  final searchLower = _search.toLowerCase();
                  return empName.toLowerCase().contains(searchLower) ||
                      status.toString().toLowerCase().contains(searchLower);
                }).toList();

                if (list.isEmpty) {
                  return const Center(
                      child: Text("Data aktivitas tidak ditemukan."));
                }

                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final item = list[i];
                    final namaKaryawan = _getEmployeeName(item['employee_id']);
                    final status = item['status'].toString().toUpperCase();

                    final DateTime? createdAt = DateTime.tryParse(
                      item['created_at'].toString(),
                    )?.toLocal();

                    final jam = createdAt != null
                        ? DateFormat('HH:mm').format(createdAt)
                        : "-";
                    final tanggal = createdAt != null
                        ? DateFormat('dd/MM/yyyy').format(createdAt)
                        : "-";
                    final isCheckIn = status.contains('IN');

                    return Card(
                      elevation: 0.5,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 0,
                        ),
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: isCheckIn
                              ? Colors.green.shade100
                              : Colors.red.shade100,
                          child: Icon(
                            isCheckIn ? Icons.login : Icons.logout,
                            color: isCheckIn ? Colors.green : Colors.red,
                            size: 16,
                          ),
                        ),
                        title: Text(
                          namaKaryawan,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          "$status  •  $tanggal",
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Text(
                          jam,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// TAB 3: PENGAJUAN (DENGAN FITUR PENCARIAN NAMA & APPROVAL)
// ==========================================
class PengajuanTab extends StatelessWidget {
  const PengajuanTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: Colors.blue,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: "Cuti/Izin"),
              Tab(text: "Lembur"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _RequestListWidget(tableName: 'leave_requests'),
                _RequestListWidget(tableName: 'overtime_requests'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestListWidget extends StatefulWidget {
  final String tableName;
  const _RequestListWidget({Key? key, required this.tableName})
      : super(key: key);
  @override
  __RequestListWidgetState createState() => __RequestListWidgetState();
}

class __RequestListWidgetState extends State<_RequestListWidget> {
  late Future<List<Map<String, dynamic>>> _requestFuture;
  List<Map<String, dynamic>> _employeeList = [];
  int? _adminEmployeeId;
  String _searchName = ""; // Variabel pencarian pengajuan

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('id_ID', null);
    _loadAdminAndData();
  }

  Future<void> _loadAdminAndData() async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null) {
        final adminData = await Supabase.instance.client
            .from('employees')
            .select('id')
            .eq('email', currentUser.email!)
            .maybeSingle();
        if (adminData != null) {
          _adminEmployeeId = adminData['id'];
        }
      }
    } catch (e) {
      debugPrint("Gagal mengambil ID admin: $e");
    }
    _refreshData();
  }

  Future<void> _refreshData() async {
    final empResponse =
        await Supabase.instance.client.from('employees').select();
    final reqResponse = await Supabase.instance.client
        .from(widget.tableName)
        .select()
        .order('created_at', ascending: false);

    if (mounted) {
      setState(() {
        _employeeList = List<Map<String, dynamic>>.from(empResponse);
        _requestFuture = Future.value(
          List<Map<String, dynamic>>.from(reqResponse),
        );
      });
    }
  }

  String _getEmployeeName(dynamic identifier) {
    if (identifier == null || identifier.toString().trim().isEmpty) {
      return "Karyawan";
    }
    final match = _employeeList.firstWhere(
      (emp) =>
          emp['id']?.toString() == identifier.toString() ||
          emp['user_id']?.toString() == identifier.toString() ||
          emp['nik']?.toString() == identifier.toString(),
      orElse: () => <String, dynamic>{},
    );
    return match['full_name'] ?? match['name'] ?? "Karyawan";
  }

  Future<void> _updateStatusCuti(int id, String newStatus, String? userId,
      String startDate, String endDate) async {
    try {
      await Supabase.instance.client.from('leave_requests').update({
        'status': newStatus,
        'approved_by': _adminEmployeeId,
      }).eq('id', id);

      if (newStatus == 'approved' && userId != null) {
        DateTime start = DateTime.parse(startDate);
        DateTime end = DateTime.parse(endDate);
        int durasi = end.difference(start).inDays + 1;

        final balanceData = await Supabase.instance.client
            .from('leave_balance')
            .select('*')
            .eq('user_id', userId)
            .maybeSingle();

        if (balanceData == null) {
          await Supabase.instance.client.from('leave_balance').insert({
            'user_id': userId,
            'used_leave': durasi,
            'remaining_leave': 12 - durasi,
          });
        } else {
          int currentUsed = balanceData['used_leave'] ?? 0;
          int currentRemaining = balanceData['remaining_leave'] ?? 0;
          await Supabase.instance.client.from('leave_balance').update({
            'used_leave': currentUsed + durasi,
            'remaining_leave': currentRemaining - durasi,
          }).eq('user_id', userId);
        }
      }

      _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Berhasil memproses pengajuan cuti!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateStatusLembur(
      int id, String newStatus, dynamic employeeId, double durasi) async {
    try {
      await Supabase.instance.client.from('overtime_requests').update({
        'status': newStatus,
        'approved_by': _adminEmployeeId,
      }).eq('id', id);

      if (newStatus == 'approved' && employeeId != null) {
        final empData = await Supabase.instance.client
            .from('employees')
            .select('total_overtime_hours')
            .eq('id', employeeId)
            .single();
        double currentTotal =
            double.parse((empData['total_overtime_hours'] ?? 0).toString());
        await Supabase.instance.client
            .from('employees')
            .update({'total_overtime_hours': currentTotal + durasi}).eq(
                'id', employeeId);
      }

      _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pengajuan lembur berhasil diproses!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatTanggalCantik(String? tgl) {
    if (tgl == null || tgl == '-' || tgl == 'null') return '-';
    try {
      String datePart =
          tgl.contains('T') ? tgl.split('T')[0] : tgl.split(' ')[0];
      DateTime dt = DateTime.parse(datePart);
      return DateFormat('dd-MM-yyyy', 'id_ID').format(dt);
    } catch (e) {
      return tgl;
    }
  }

  String _formatJam(String? waktu) {
    if (waktu == null || waktu == '-' || waktu == 'null' || waktu.isEmpty)
      return '-';
    try {
      if (waktu.contains('T')) return waktu.split('T')[1].substring(0, 5);
      if (waktu.contains(' ')) return waktu.split(' ').last.substring(0, 5);
      if (waktu.length >= 5) return waktu.substring(0, 5);
      return waktu;
    } catch (e) {
      return '-';
    }
  }

  String _hitungDurasi(String? start, String? end) {
    if (start == null || end == null || start == 'null' || end == 'null')
      return '';
    try {
      DateTime dtStart = (start.contains('T') || start.contains('-'))
          ? DateTime.parse(start)
          : DateTime.parse('1970-01-01 $start');
      DateTime dtEnd = (end.contains('T') || end.contains('-'))
          ? DateTime.parse(end)
          : DateTime.parse('1970-01-01 $end');

      Duration diff = dtEnd.difference(dtStart);
      if (diff.isNegative) {
        dtEnd = dtEnd.add(const Duration(days: 1));
        diff = dtEnd.difference(dtStart);
      }

      int hours = diff.inHours;
      int minutes = diff.inMinutes.remainder(60);

      if (hours > 0 && minutes > 0) return "($hours Jam $minutes Menit)";
      if (hours > 0) return "($hours Jam)";
      if (minutes > 0) return "($minutes Menit)";
      return "";
    } catch (e) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Fitur Filter Nama pada Tab Pengajuan
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: "Cari nama karyawan...",
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (v) => setState(() => _searchName = v),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _requestFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("Tidak ada data pengajuan."));
                }

                // Melakukan Filter Nama Di Sini
                final list = snapshot.data!.where((row) {
                  final namaKaryawan = _getEmployeeName(
                    row['employee_id'] ?? row['user_id'] ?? row['id'],
                  ).toLowerCase();
                  return namaKaryawan.contains(_searchName.toLowerCase());
                }).toList();

                if (list.isEmpty) {
                  return const Center(
                      child: Text("Pengajuan tidak ditemukan."));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final row = list[i];
                    final namaKaryawan = _getEmployeeName(
                      row['employee_id'] ?? row['user_id'] ?? row['id'],
                    );
                    final rawStatus =
                        (row['status'] ?? 'pending').toString().toLowerCase();

                    Color statusColor = Colors.orange;
                    String statusText = "PENDING";
                    if (rawStatus == 'approved' || rawStatus == 'disetujui') {
                      statusColor = Colors.green;
                      statusText = "APPROVED";
                    } else if (rawStatus == 'rejected' ||
                        rawStatus == 'ditolak') {
                      statusColor = Colors.red;
                      statusText = "REJECTED";
                    }

                    // MENAMPILKAN NAMA APPROVER
                    String approver = '';
                    if (row['approved_by'] != null) {
                      approver = _getEmployeeName(row['approved_by']);
                    }

                    String infoUtama = "-";
                    String keterangan = "-";

                    if (widget.tableName == 'leave_requests') {
                      infoUtama =
                          "${row['leave_type'] ?? 'Cuti'} • ${_formatTanggalCantik(row['start_date'])} s/d ${_formatTanggalCantik(row['end_date'])}";
                      keterangan = "Alasan: ${row['reason'] ?? '-'}";
                    } else {
                      String tgl = _formatTanggalCantik(
                        row['overtime_date'] ?? row['start_time'],
                      );
                      String jamMulai =
                          _formatJam(row['start_time']?.toString());
                      String jamSelesai =
                          _formatJam(row['end_time']?.toString());
                      String durasi = _hitungDurasi(
                        row['start_time']?.toString(),
                        row['end_time']?.toString(),
                      );

                      infoUtama =
                          "Lembur • $tgl \n$jamMulai - $jamSelesai WIB $durasi";
                      keterangan =
                          "Pekerjaan: ${row['reason'] ?? row['description'] ?? '-'}";
                    }

                    return Card(
                      elevation: 0.5,
                      margin: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  namaKaryawan,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: statusColor),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              infoUtama,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              keterangan,
                              style: const TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            if (rawStatus != 'pending' &&
                                approver.isNotEmpty &&
                                approver != 'Karyawan') ...[
                              const SizedBox(height: 2),
                              Text(
                                "Approved by: $approver",
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blue.shade800,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                            if (rawStatus == 'pending') ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        if (widget.tableName ==
                                            'leave_requests') {
                                          _updateStatusCuti(
                                            row['id'],
                                            'rejected',
                                            row['user_id']?.toString(),
                                            row['start_date'],
                                            row['end_date'],
                                          );
                                        } else {
                                          _updateStatusLembur(
                                            row['id'],
                                            'rejected',
                                            row['employee_id'],
                                            double.tryParse(
                                                  row['duration_hours']
                                                          ?.toString() ??
                                                      '0',
                                                ) ??
                                                0.0,
                                          );
                                        }
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                        side:
                                            const BorderSide(color: Colors.red),
                                        minimumSize: const Size(0, 32),
                                        padding: EdgeInsets.zero,
                                      ),
                                      child: const Text(
                                        "Tolak",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () {
                                        if (widget.tableName ==
                                            'leave_requests') {
                                          _updateStatusCuti(
                                            row['id'],
                                            'approved',
                                            row['user_id']?.toString(),
                                            row['start_date'],
                                            row['end_date'],
                                          );
                                        } else {
                                          _updateStatusLembur(
                                            row['id'],
                                            'approved',
                                            row['employee_id'],
                                            double.tryParse(
                                                  row['duration_hours']
                                                          ?.toString() ??
                                                      '0',
                                                ) ??
                                                0.0,
                                          );
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(0, 32),
                                        padding: EdgeInsets.zero,
                                      ),
                                      child: const Text(
                                        "Setujui",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// TAB 4: LOKASI
// ==========================================
class LokasiTab extends StatefulWidget {
  const LokasiTab({Key? key}) : super(key: key);
  @override
  _LokasiTabState createState() => _LokasiTabState();
}

class _LokasiTabState extends State<LokasiTab> {
  late Future<List<Map<String, dynamic>>> _lokasiFuture;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() {
      _lokasiFuture = Supabase.instance.client.from('locations').select();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _lokasiFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text("Tidak ada data lokasi."));
            }

            final list = snapshot.data!;
            return ListView.builder(
              itemCount: list.length,
              itemBuilder: (c, i) {
                final item = list[i];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on, color: Colors.blue),
                    title: Text(
                      item['name'] ?? 'Tanpa Nama',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['address'] ?? 'Tidak ada alamat',
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          "Radius: ${item['radius_meter'] ?? 0}m",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
