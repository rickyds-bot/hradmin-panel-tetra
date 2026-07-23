import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
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
              Tab(text: "Aktivitas"),
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
// TAB 1: KARYAWAN
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
      _karyawanFuture = Supabase.instance.client.from('employees').select();
    });
  }

  Widget _buildDetailRow(String label, dynamic value) {
    String textValue =
        (value == null ||
            value.toString().trim().isEmpty ||
            value.toString() == 'null')
        ? '-'
        : value.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          const Text(": ", style: TextStyle(color: Colors.grey, fontSize: 13)),
          Expanded(
            child: Text(
              textValue,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 15, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.blue,
          fontSize: 14,
        ),
      ),
    );
  }

  void _viewDetail(Map<String, dynamic> data) {
    final rawPhoto = data['photo_url'];
    final photoUrl =
        (rawPhoto != null &&
            rawPhoto.toString().trim().isNotEmpty &&
            rawPhoto.toString().startsWith('http'))
        ? rawPhoto.toString()
        : null;

    List<dynamic> anakList = [];
    if (data['children_data'] != null) {
      try {
        anakList = data['children_data'] is String
            ? jsonDecode(data['children_data'])
            : data['children_data'];
      } catch (_) {}
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: Colors.blue.shade100,
                backgroundImage: photoUrl != null
                    ? NetworkImage(photoUrl)
                    : null,
                child: photoUrl == null
                    ? const Icon(Icons.person, color: Colors.blue, size: 30)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  data['full_name'] ?? 'Tanpa Nama',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  _sectionTitle("Data Pribadi"),
                  _buildDetailRow("Nama", data['full_name']),
                  _buildDetailRow("Tempat Lahir", data['birth_place']),
                  _buildDetailRow("Tgl Lahir", data['birth_date']),
                  _buildDetailRow("Agama", data['religion']),
                  _buildDetailRow("No. KTP", data['ktp_number']),
                  _buildDetailRow("No. NPWP", data['npwp_number']),
                  _buildDetailRow("Alamat KTP", data['address_ktp']),
                  _buildDetailRow(
                    "Alamat Domisili",
                    data['address_now'] ?? data['address'],
                  ),
                  _buildDetailRow(
                    "No. HP",
                    data['phone'] ?? data['phone_number'],
                  ),
                  _buildDetailRow(
                    "Pendidikan",
                    data['education'] ?? data['education_level'],
                  ),

                  _sectionTitle("Data Keluarga"),
                  _buildDetailRow("Status Nikah", data['marital_status']),
                  _buildDetailRow("Nama Pasangan", data['spouse_name']),
                  _buildDetailRow("Tgl Lahir Psg", data['spouse_birth_date']),
                  if (anakList.isNotEmpty)
                    ...anakList
                        .map(
                          (anak) => _buildDetailRow(
                            "Anak",
                            "${anak['name'] ?? '-'} (${anak['birth_date'] ?? '-'})",
                          ),
                        )
                        .toList()
                  else
                    _buildDetailRow("Anak", "-"),

                  _sectionTitle("Kontak Darurat"),
                  _buildDetailRow(
                    "Nama Kontak",
                    data['emergency_contact_name'] ?? data['emergency_name'],
                  ),
                  _buildDetailRow(
                    "Nomor HP",
                    data['emergency_contact_phone'] ?? data['emergency_phone'],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Tutup", style: TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
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
              hintText: "Cari nama karyawan...",
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
                final list = snapshot.data!
                    .where(
                      (e) => (e['full_name'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(_search.toLowerCase()),
                    )
                    .toList();
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final dataKaryawan = list[i];
                    final rawPhoto = dataKaryawan['photo_url'];
                    final photoUrl =
                        (rawPhoto != null &&
                            rawPhoto.toString().trim().isNotEmpty &&
                            rawPhoto.toString().startsWith('http'))
                        ? rawPhoto.toString()
                        : null;
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
                          backgroundImage: photoUrl != null
                              ? NetworkImage(photoUrl)
                              : null,
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
                          dataKaryawan['nik'] ?? 'NIK Kosong',
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

// ==========================================
// TAB 2: AKTIVITAS
// ==========================================
class AktivitasTab extends StatefulWidget {
  const AktivitasTab({Key? key}) : super(key: key);
  @override
  _AktivitasTabState createState() => _AktivitasTabState();
}

class _AktivitasTabState extends State<AktivitasTab> {
  String _search = "";
  late Future<List<Map<String, dynamic>>> _aktivitasFuture;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() {
      _aktivitasFuture = Supabase.instance.client
          .from('attendance')
          .select('*, employees(full_name)')
          .order('created_at', ascending: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: const InputDecoration(
              hintText: "Cari nama atau status...",
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

                final list = snapshot.data!.where((e) {
                  final empData = e['employees'];
                  final empName = empData?['full_name'] ?? '';
                  final status = e['status'] ?? '';
                  final searchLower = _search.toLowerCase();
                  return empName.toString().toLowerCase().contains(
                        searchLower,
                      ) ||
                      status.toString().toLowerCase().contains(searchLower);
                }).toList();

                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final item = list[i];
                    final empData = item['employees'];
                    final namaKaryawan = empData?['full_name'] ?? 'Tanpa Nama';
                    final status = item['status'].toString().toUpperCase();

                    // PARSING WAKTU DENGAN CARA BAWAAN FLUTTER YANG LEBIH CERDAS
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
// TAB 3: PENGAJUAN (TANPA APPROVED BY)
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

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('id_ID', null);
    _refreshData();
  }

  Future<void> _refreshData() async {
    final empResponse = await Supabase.instance.client
        .from('employees')
        .select();
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

  // --- FUNGSI FORMAT YANG DISAMAKAN DENGAN KARYAWAN_PAGE ---
  String _formatTanggalCantik(String? tgl) {
    if (tgl == null || tgl == '-' || tgl == 'null') return '-';
    try {
      String datePart = tgl.contains('T')
          ? tgl.split('T')[0]
          : tgl.split(' ')[0];
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
  // --------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
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

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, i) {
              final row = snapshot.data![i];
              final namaKaryawan = _getEmployeeName(
                row['employee_id'] ?? row['user_id'] ?? row['id'],
              );
              final status = (row['status'] ?? 'PENDING')
                  .toString()
                  .toUpperCase();

              Color statusColor = Colors.orange;
              if (status == 'APPROVED' || status == 'DISETUJUI')
                statusColor = Colors.green;
              if (status == 'REJECTED' || status == 'DITOLAK')
                statusColor = Colors.red;

              String tanggalInfo = "-";
              String keterangan = "-";

              if (widget.tableName == 'leave_requests') {
                tanggalInfo =
                    "${_formatTanggalCantik(row['start_date'])} s/d ${_formatTanggalCantik(row['end_date'])}";
                keterangan = "Alasan: ${row['reason'] ?? '-'}";
              } else {
                // LOGIKA LEMBUR YANG SUDAH DISAMAKAN
                String tgl = _formatTanggalCantik(
                  row['overtime_date'] ?? row['start_time'],
                );
                String jamMulai = _formatJam(row['start_time']?.toString());
                String jamSelesai = _formatJam(row['end_time']?.toString());
                String durasi = _hitungDurasi(
                  row['start_time']?.toString(),
                  row['end_time']?.toString(),
                );

                tanggalInfo = "$tgl \n$jamMulai - $jamSelesai WIB $durasi";
                keterangan =
                    "Pekerjaan: ${row['reason'] ?? row['description'] ?? '-'}";
              }

              return Card(
                elevation: 0.5,
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(
                    namaKaryawan,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        tanggalInfo,
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
                    ],
                  ),
                  trailing: Container(
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
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
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
