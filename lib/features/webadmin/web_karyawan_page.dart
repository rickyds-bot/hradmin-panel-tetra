import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:mobile_absensi/features/core/utils/app_logger.dart';

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

  int _rowsPerPage = 10;
  final List<int> _pageOptions = [10, 20, 50, 100];

  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _fetchKaryawanData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchKaryawanData() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('employees')
          .select('*, departments(name)') // Join dengan tabel departments
          .order('full_name', ascending: true);

      setState(() {
        _karyawanList = response;
        _filteredList = response;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengambil data: $e',
                style: GoogleFonts.plusJakartaSans(fontSize: 12)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterData(String query) {
    if (query.isEmpty) {
      setState(() => _filteredList = _karyawanList);
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredList = _karyawanList.where((item) {
        final name = (item['full_name'] ?? '').toString().toLowerCase();
        final nik = (item['nik'] ?? '').toString().toLowerCase();
        return name.contains(lowerQuery) || nik.contains(lowerQuery);
      }).toList();
    });
  }

  void _sort<T>(Comparable<T> Function(Map<String, dynamic> d) getField,
      int columnIndex, bool ascending) {
    _filteredList.sort((a, b) {
      final aValue = getField(a);
      final bValue = getField(b);
      return ascending
          ? Comparable.compare(aValue, bValue)
          : Comparable.compare(bValue, aValue);
    });
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  String _formatDateIndo(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final dt = DateTime.parse(dateStr);
      final day = dt.day.toString().padLeft(2, '0');
      final year = dt.year.toString();
      const months = [
        '',
        'Januari',
        'Februari',
        'Maret',
        'April',
        'Mei',
        'Juni',
        'Juli',
        'Agustus',
        'September',
        'Oktober',
        'November',
        'Desember'
      ];
      final month = months[dt.month];
      return '$day $month $year';
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _toggleFreeLocation(
      Map<String, dynamic> karyawan, bool? value) async {
    if (value == null) return;

    final originalValue = karyawan['is_free_location'];

    setState(() {
      karyawan['is_free_location'] = value;
    });

    try {
      await Supabase.instance.client
          .from('employees')
          .update({'is_free_location': value}).eq('id', karyawan['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Status absen bebas ${karyawan['full_name']} diperbarui',
                style: GoogleFonts.plusJakartaSans(fontSize: 12)),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      setState(() {
        karyawan['is_free_location'] = originalValue;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memperbarui status: $e',
                style: GoogleFonts.plusJakartaSans(fontSize: 12)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showChangePasswordDialog(Map<String, dynamic> karyawan) async {
    final passCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(
              "Ubah Password: ${karyawan['full_name']}",
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: TextField(
              controller: passCtrl,
              obscureText: true,
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
              decoration: InputDecoration(
                labelText: "Password Baru (Min. 6 karakter)",
                labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Batal",
                    style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        if (passCtrl.text.length < 6) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Password minimal 6 karakter',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12)),
                            ),
                          );
                          return;
                        }

                        setStateDialog(() => isSaving = true);
                        try {
                          await Supabase.instance.client.rpc(
                            'admin_update_user_password_by_email',
                            params: {
                              'target_email':
                                  karyawan['email'], // <-- Gunakan email
                              'new_password': passCtrl.text,
                            },
                          );
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Password berhasil diubah!',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12)),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Gagal mengubah password: $e',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12)),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setStateDialog(() => isSaving = false);
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text("Simpan Password",
                        style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              )
            ],
          );
        },
      ),
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddKaryawanDialog(onSuccess: _fetchKaryawanData),
    );
  }

  void _showDetailDialog(Map<String, dynamic> karyawan) {
    showDialog(
      context: context,
      builder: (context) => DetailKaryawanDialog(karyawan: karyawan),
    );
  }

  void _showEditDialog(Map<String, dynamic> karyawan) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => EditKaryawanDialog(
        karyawan: karyawan,
        onSuccess: _fetchKaryawanData,
      ),
    );
  }

  Future<void> _showLeaveBalanceDialog(Map<String, dynamic> karyawan) async {
    final empId = karyawan['id'];
    var userUuid = karyawan['user_id'];
    final empName = karyawan['full_name'] ?? 'Karyawan';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic>? balanceData;
    try {
      if (userUuid == null || userUuid.toString().isEmpty) {
        final leaveReqRes = await Supabase.instance.client
            .from('leave_requests')
            .select('user_id')
            .eq('employee_id', empId)
            .limit(1);

        if (leaveReqRes.isNotEmpty) {
          userUuid = leaveReqRes.first['user_id'];
        }
      }

      if (userUuid != null && userUuid.toString().isNotEmpty) {
        balanceData = await Supabase.instance.client
            .from('leave_balance')
            .select()
            .eq('user_id', userUuid)
            .maybeSingle();
      }
    } catch (e) {
      debugPrint('Error fetching balance: $e');
      balanceData = null;
    }

    if (mounted) Navigator.pop(context);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => KaryawanLeaveBalanceDialog(
        userUuid: userUuid,
        empName: empName,
        initialBalance: balanceData,
        onSuccess: _fetchKaryawanData,
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
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  'Tambah Karyawan',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Cari NIK atau Nama...',
                    hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  onChanged: _filterData,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Text(
                      'Tampilkan:',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _rowsPerPage,
                      underline: const SizedBox(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                      items: _pageOptions.map((int value) {
                        return DropdownMenuItem<int>(
                          value: value,
                          child: Text('$value',
                              style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (int? newValue) {
                        if (newValue != null) {
                          setState(() => _rowsPerPage = newValue);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey[200]!),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredList.isEmpty
                      ? Center(
                          child: Text(
                            'Tidak ada data karyawan.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : Scrollbar(
                          controller: _horizontalScrollCtrl,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _horizontalScrollCtrl,
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth:
                                    MediaQuery.of(context).size.width - 80,
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: DataTable(
                                  sortColumnIndex: _sortColumnIndex,
                                  sortAscending: _sortAscending,
                                  headingRowColor:
                                      WidgetStateProperty.all(Colors.grey[50]),
                                  headingTextStyle: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                  dataTextStyle: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: Colors.black87,
                                  ),
                                  columns: [
                                    DataColumn(
                                      label: const Text('NIK'),
                                      onSort: (colIndex, ascending) => _sort(
                                          (d) => d['nik'] ?? '',
                                          colIndex,
                                          ascending),
                                    ),
                                    DataColumn(
                                      label: const Text('Nama Karyawan'),
                                      onSort: (colIndex, ascending) => _sort(
                                          (d) => d['full_name'] ?? '',
                                          colIndex,
                                          ascending),
                                    ),
                                    DataColumn(
                                      label: const Text('Email'),
                                      onSort: (colIndex, ascending) => _sort(
                                          (d) => d['email'] ?? '',
                                          colIndex,
                                          ascending),
                                    ),
                                    const DataColumn(
                                      label: Text('Absen Bebas'),
                                      tooltip:
                                          'Karyawan bebas absen dari lokasi mana saja',
                                    ),
                                    DataColumn(
                                      label: const Text('Jabatan'),
                                      onSort: (colIndex, ascending) => _sort(
                                          (d) => d['jabatan_name'] ?? '',
                                          colIndex,
                                          ascending),
                                    ),
                                    DataColumn(
                                      label: const Text('Tanggal Masuk'),
                                      onSort: (colIndex, ascending) => _sort(
                                          (d) => d['join_date'] ?? '',
                                          colIndex,
                                          ascending),
                                    ),
                                    DataColumn(
                                      label: const Text('Status Karyawan'),
                                      onSort: (colIndex, ascending) => _sort(
                                          (d) => d['employee_status'] ?? '',
                                          colIndex,
                                          ascending),
                                    ),
                                    const DataColumn(label: Text('Saldo Cuti')),
                                    const DataColumn(
                                        label: Text('Status Akun')),
                                    const DataColumn(label: Text('Action')),
                                  ],
                                  rows: List<DataRow>.generate(
                                    _filteredList.length > _rowsPerPage
                                        ? _rowsPerPage
                                        : _filteredList.length,
                                    (index) {
                                      final item = _filteredList[index];
                                      final isActive =
                                          item['is_active'] ?? true;

                                      final isFreeLocation =
                                          item['is_free_location'] ?? false;

                                      String rawEmpStatus =
                                          item['employee_status']
                                                  ?.toString()
                                                  .toLowerCase() ??
                                              'tetap';
                                      String displayStatus = 'Tetap';
                                      if (rawEmpStatus == 'kontrak') {
                                        displayStatus = 'Kontrak';
                                      } else if (rawEmpStatus == 'magang') {
                                        displayStatus = 'Magang';
                                      }

                                      return DataRow(
                                        cells: [
                                          DataCell(Text(item['nik'] ?? '-')),
                                          DataCell(
                                            InkWell(
                                              onTap: () =>
                                                  _showDetailDialog(item),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 8.0),
                                                child: Text(
                                                  item['full_name'] ?? '-',
                                                  style: GoogleFonts
                                                      .plusJakartaSans(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue[700],
                                                    decoration: TextDecoration
                                                        .underline,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(Text(item['email'] ?? '-')),
                                          DataCell(
                                            Checkbox(
                                              value: isFreeLocation,
                                              activeColor: Colors.blue[700],
                                              onChanged: (bool? newValue) {
                                                _toggleFreeLocation(
                                                    item, newValue);
                                              },
                                            ),
                                          ),
                                          DataCell(Text(
                                              item['jabatan_name'] ?? '-')),
                                          DataCell(Text(_formatDateIndo(
                                              item['join_date']))),
                                          DataCell(
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.blue[50],
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                displayStatus,
                                                style:
                                                    GoogleFonts.plusJakartaSans(
                                                  fontSize: 12,
                                                  color: Colors.blue[800],
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            ElevatedButton.icon(
                                              onPressed: () =>
                                                  _showLeaveBalanceDialog(item),
                                              icon: const Icon(
                                                  Icons.account_balance_wallet,
                                                  size: 14),
                                              label: Text('Edit Saldo',
                                                  style: GoogleFonts
                                                      .plusJakartaSans(
                                                          fontSize: 11)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.orange,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                minimumSize: const Size(0, 30),
                                                elevation: 0,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: isActive
                                                    ? Colors.green[50]
                                                    : Colors.red[50],
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                isActive
                                                    ? 'Aktif'
                                                    : 'Non-Aktif',
                                                style:
                                                    GoogleFonts.plusJakartaSans(
                                                  fontSize: 12,
                                                  color: isActive
                                                      ? Colors.green[800]
                                                      : Colors.red[800],
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert,
                                                  size: 20, color: Colors.grey),
                                              onSelected: (value) {
                                                if (value == 'edit') {
                                                  _showEditDialog(item);
                                                } else if (value ==
                                                    'password') {
                                                  _showChangePasswordDialog(
                                                      item);
                                                }
                                              },
                                              itemBuilder: (context) => [
                                                PopupMenuItem(
                                                  value: 'edit',
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.edit,
                                                          size: 16,
                                                          color: Colors.blue),
                                                      const SizedBox(width: 8),
                                                      Text('Edit Biodata',
                                                          style: GoogleFonts
                                                              .plusJakartaSans(
                                                                  fontSize:
                                                                      12)),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'password',
                                                  child: Row(
                                                    children: [
                                                      const Icon(
                                                          Icons.lock_reset,
                                                          size: 16,
                                                          color: Colors.orange),
                                                      const SizedBox(width: 8),
                                                      Text('Ubah Password',
                                                          style: GoogleFonts
                                                              .plusJakartaSans(
                                                                  fontSize:
                                                                      12)),
                                                    ],
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
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class DetailKaryawanDialog extends StatefulWidget {
  final Map<String, dynamic> karyawan;
  const DetailKaryawanDialog({super.key, required this.karyawan});

  @override
  State<DetailKaryawanDialog> createState() => _DetailKaryawanDialogState();
}

class _DetailKaryawanDialogState extends State<DetailKaryawanDialog> {
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
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd-MM-yyyy').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    String childrenStr = '-';
    final rawChildren = widget.karyawan['children_data'];

    if (rawChildren != null &&
        rawChildren.toString() != 'null' &&
        rawChildren.toString().isNotEmpty) {
      try {
        List<dynamic> childrenList = [];

        if (rawChildren is String) {
          if (rawChildren.trim().startsWith('[')) {
            childrenList = jsonDecode(rawChildren);
          } else {
            childrenStr = rawChildren;
          }
        } else if (rawChildren is List) {
          childrenList = rawChildren;
        }

        if (childrenList.isNotEmpty) {
          List<String> formattedAnak = [];
          for (int i = 0; i < childrenList.length; i++) {
            var anak = childrenList[i];
            if (anak is Map) {
              String nama = anak['name'] ?? '-';
              String tglLahir = anak['birth_date'] ?? '-';
              formattedAnak.add("${i + 1}. $nama ($tglLahir)");
            }
          }
          if (formattedAnak.isNotEmpty) {
            childrenStr = formattedAnak.join('\n');
          }
        }
      } catch (e) {
        childrenStr = rawChildren.toString();
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
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Detail Biodata Karyawan & Riwayat',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.blue[100],
                            backgroundImage: (photoUrl != null &&
                                    photoUrl.toString().isNotEmpty)
                                ? NetworkImage(photoUrl.toString())
                                : null,
                            child: (photoUrl == null ||
                                    photoUrl.toString().isEmpty)
                                ? const Icon(Icons.person,
                                    size: 40, color: Colors.blue)
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.karyawan['full_name'] ?? '-',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            widget.karyawan['jabatan_name'] ?? '-',
                            style: GoogleFonts.plusJakartaSans(
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
                    _buildInfoRow('Departemen',
                        widget.karyawan['departments']?['name'] ?? '-'),
                    _buildInfoRow('Role', widget.karyawan['role']),
                    _buildInfoRow(
                        'Position ID', widget.karyawan['position_id']),
                    _buildInfoRow('Status Karyawan Saat Ini', displayStatus),
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
                              width: 160,
                              child: Text('Surat Kontrak',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w500)),
                            ),
                            const Text(': '),
                            ElevatedButton.icon(
                              onPressed: () => _downloadFile(
                                  widget.karyawan['contract_file']),
                              icon: const Icon(Icons.download, size: 14),
                              label: Text('Download Dokumen PDF',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    _buildSectionTitle('Informasi Pribadi & Identitas'),
                    _buildInfoRow('Jenis Kelamin', widget.karyawan['gender']),
                    _buildInfoRow('Agama', widget.karyawan['religion']),
                    _buildInfoRow('Tempat, Tanggal Lahir',
                        '${widget.karyawan['birth_place'] ?? '-'}, ${_formatDate(widget.karyawan['birth_date'])}'),
                    _buildInfoRow('Nomor KTP', widget.karyawan['ktp_number']),
                    _buildInfoRow('Nomor NPWP', widget.karyawan['npwp_number']),
                    _buildInfoRow('Pendidikan', widget.karyawan['education']),
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 16),
                    _buildSectionTitle('Kontak Darurat'),
                    _buildInfoRow('Nama Kontak Darurat',
                        widget.karyawan['emergency_name']),
                    _buildInfoRow('Telp Kontak Darurat',
                        widget.karyawan['emergency_phone']),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionTitle('Riwayat Kontrak / Perubahan Status'),
            _isLoadingContracts
                ? const Center(child: CircularProgressIndicator())
                : _contractHistory.isEmpty
                    ? Text(
                        displayStatus == 'Tetap'
                            ? 'Karyawan langsung berstatus Tetap (Tidak ada riwayat kontrak sebelumnya).'
                            : 'Belum ada riwayat kontrak.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: Colors.grey[600]),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _contractHistory.length,
                        itemBuilder: (context, index) {
                          final c = _contractHistory[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(
                                  'Periode: ${_formatDate(c['contract_start'])} s/d ${_formatDate(c['contract_end'])}',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (c['contract_number'] != null &&
                                      c['contract_number']
                                          .toString()
                                          .isNotEmpty)
                                    Text('No: ${c['contract_number']}   ',
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            color: Colors.blue[700]))
                                  else
                                    Text('Tanpa No.   ',
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10, color: Colors.grey)),
                                  if (c['contract_file'] != null &&
                                      c['contract_file'].toString().isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.download,
                                          color: Colors.teal, size: 20),
                                      tooltip: 'Download PDF',
                                      onPressed: () =>
                                          _downloadFile(c['contract_file']),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Tutup',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
      child: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[800]),
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500)),
          ),
          const Text(': '),
          Expanded(
            child: Text(
                value?.toString().isNotEmpty == true ? value.toString() : '-',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}

class AddKaryawanDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const AddKaryawanDialog({super.key, required this.onSuccess});

  @override
  State<AddKaryawanDialog> createState() => _AddKaryawanDialogState();
}

class _AddKaryawanDialogState extends State<AddKaryawanDialog> {
  bool _isSaving = false;

  final _nikCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _birthPlaceCtrl = TextEditingController();
  final _birthDateCtrl = TextEditingController();
  final _ktpCtrl = TextEditingController();
  final _npwpCtrl = TextEditingController();
  final _addressKtpCtrl = TextEditingController();
  final _addressNowCtrl = TextEditingController();

  String _selectedMaritalStatus = 'Single';
  final List<String> _maritalStatusOptions = ['Single', 'Menikah', 'Bercerai'];

  final _spouseNameCtrl = TextEditingController();
  final _spouseBirthDateCtrl = TextEditingController();
  final _childrenDataCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();
  final _jabatanCtrl = TextEditingController();
  final _contractNumberCtrl = TextEditingController();

  String _selectedRole = 'Staff';
  final List<String> _roleOptions = ['Staff', 'Supervisor', 'Manager', 'Admin'];

  String _selectedGender = 'Laki-laki';
  final List<String> _genderOptions = ['Laki-laki', 'Perempuan'];

  String _selectedReligion = 'Islam';
  final List<String> _religionOptions = [
    'Islam',
    'Kristen',
    'Katolik',
    'Hindu',
    'Buddha',
    'Konghucu',
    'Lainnya'
  ];

  String _selectedEducation = 'S1';
  final List<String> _educationOptions = [
    'SD',
    'SMP',
    'SMA/SMK',
    'D3',
    'D4',
    'S1',
    'S2',
    'S3'
  ];

  String _selectedAccountStatus = 'Aktif';
  String _selectedEmpStatus = 'Tetap';
  final _contractStartCtrl = TextEditingController();
  final _contractEndCtrl = TextEditingController();

  Uint8List? _selectedFileBytes;
  String? _selectedFileName;

  List<Map<String, dynamic>> _departments = [];
  int? _selectedDepartmentId;

  @override
  void initState() {
    super.initState();
    _fetchDepartments();
  }

  Future<void> _fetchDepartments() async {
    try {
      final res = await Supabase.instance.client
          .from('departments')
          .select('id, name')
          .order('name', ascending: true);

      if (mounted) {
        setState(() {
          _departments = List<Map<String, dynamic>>.from(res);
          if (_departments.isNotEmpty) {
            _selectedDepartmentId = _departments.first['id'];
          }
        });
      }
    } catch (e) {
      debugPrint("Gagal mengambil data departemen: $e");
    }
  }

  int _mapRoleToPositionId(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'manager':
        return 1;
      case 'supervisor':
        return 2;
      case 'staff':
      default:
        return 3;
    }
  }

  Future<void> _selectDate(
      BuildContext context, TextEditingController ctrl) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1940),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _selectedFileBytes = result.files.single.bytes;
        _selectedFileName = result.files.single.name;
      });
    }
  }

  Future<void> _saveData() async {
    if (_nameCtrl.text.isEmpty ||
        _emailCtrl.text.isEmpty ||
        _passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Nama, Email, dan Password wajib diisi',
                style: GoogleFonts.plusJakartaSans(fontSize: 12))),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final authRes = await Supabase.instance.client.auth.admin
          .createUser(AdminUserAttributes(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        emailConfirm: true,
      ));

      final newUserId = authRes.user?.id;
      if (newUserId != null) {
        String? contractUrl;

        if (_selectedEmpStatus == 'Kontrak' && _selectedFileBytes != null) {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final safeFileName = _selectedFileName!.replaceAll(' ', '_');
          final filePath =
              'karyawan_${_nikCtrl.text}_${timestamp}_$safeFileName';

          await Supabase.instance.client.storage
              .from('contracts')
              .uploadBinary(filePath, _selectedFileBytes!);

          contractUrl = Supabase.instance.client.storage
              .from('contracts')
              .getPublicUrl(filePath);
        }

        dynamic childrenVal;
        try {
          childrenVal = _childrenDataCtrl.text.isNotEmpty
              ? jsonDecode(_childrenDataCtrl.text)
              : null;
        } catch (_) {
          childrenVal =
              _childrenDataCtrl.text.isNotEmpty ? _childrenDataCtrl.text : null;
        }

        final int positionId = _mapRoleToPositionId(_selectedRole);
        final String? contractNum = (_selectedEmpStatus == 'Kontrak' ||
                    _selectedEmpStatus == 'Magang') &&
                _contractNumberCtrl.text.isNotEmpty
            ? _contractNumberCtrl.text
            : null;

        final newEmployeeData = await Supabase.instance.client
            .from('employees')
            .insert({
              'user_id': newUserId,
              'nik': _nikCtrl.text,
              'full_name': _nameCtrl.text,
              'email': _emailCtrl.text,
              'phone': _phoneCtrl.text,
              'gender': _selectedGender,
              'religion': _selectedReligion,
              'birth_place': _birthPlaceCtrl.text,
              'birth_date':
                  _birthDateCtrl.text.isNotEmpty ? _birthDateCtrl.text : null,
              'ktp_number': _ktpCtrl.text,
              'npwp_number': _npwpCtrl.text,
              'address_ktp': _addressKtpCtrl.text,
              'address_now': _addressNowCtrl.text,
              'education': _selectedEducation,
              'marital_status': _selectedMaritalStatus,
              'spouse_name': _spouseNameCtrl.text,
              'spouse_birth_date': _spouseBirthDateCtrl.text.isNotEmpty
                  ? _spouseBirthDateCtrl.text
                  : null,
              'children_data': childrenVal,
              'emergency_name': _emergencyNameCtrl.text,
              'emergency_phone': _emergencyPhoneCtrl.text,
              'jabatan_name': _jabatanCtrl.text,
              'department_id': _selectedDepartmentId,
              'role': _selectedRole,
              'position_id': positionId,
              'is_active': _selectedAccountStatus == 'Aktif',
              'employee_status': _selectedEmpStatus,
              'contract_number': contractNum,
              'contract_start': (_selectedEmpStatus == 'Kontrak' ||
                          _selectedEmpStatus == 'Magang') &&
                      _contractStartCtrl.text.isNotEmpty
                  ? _contractStartCtrl.text
                  : null,
              'contract_end': (_selectedEmpStatus == 'Kontrak' ||
                          _selectedEmpStatus == 'Magang') &&
                      _contractEndCtrl.text.isNotEmpty
                  ? _contractEndCtrl.text
                  : null,
              'contract_file': contractUrl,
              'join_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
            })
            .select()
            .single();

        if ((_selectedEmpStatus == 'Kontrak' ||
                _selectedEmpStatus == 'Magang') &&
            newEmployeeData != null) {
          await Supabase.instance.client.from('employee_contracts').insert({
            'employee_id': newEmployeeData['id'],
            'contract_start': _contractStartCtrl.text.isNotEmpty
                ? _contractStartCtrl.text
                : null,
            'contract_end':
                _contractEndCtrl.text.isNotEmpty ? _contractEndCtrl.text : null,
            'contract_number': contractNum,
            'contract_file': contractUrl,
          });
        }
      }

      if (mounted) {
        await AppLogger.log(
          activity:
              'Menambahkan karyawan baru: ${_nameCtrl.text} (NIK: ${_nikCtrl.text})',
          module: 'Data Karyawan',
        );

        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Karyawan berhasil ditambahkan',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Gagal: $e',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tambah Karyawan Baru',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _buildTextField(_nikCtrl, 'NIK', width: 300),
                    _buildTextField(_nameCtrl, 'Nama Lengkap', width: 300),
                    _buildTextField(_emailCtrl, 'Email', width: 300),
                    _buildTextField(_passwordCtrl, 'Password Default',
                        width: 300, isPassword: true),
                    _buildTextField(_phoneCtrl, 'No. Telepon', width: 300),
                    _buildDropdownField(
                        'Jenis Kelamin',
                        _selectedGender,
                        _genderOptions,
                        (val) => setState(() => _selectedGender = val!)),
                    _buildDropdownField(
                        'Agama',
                        _selectedReligion,
                        _religionOptions,
                        (val) => setState(() => _selectedReligion = val!)),
                    _buildTextField(_birthPlaceCtrl, 'Tempat Lahir',
                        width: 300),
                    _buildTextField(_birthDateCtrl, 'Tanggal Lahir',
                        width: 300,
                        readOnly: true,
                        onTap: () => _selectDate(context, _birthDateCtrl)),
                    _buildTextField(_ktpCtrl, 'Nomor KTP', width: 300),
                    _buildTextField(_npwpCtrl, 'Nomor NPWP', width: 300),
                    _buildDropdownField(
                        'Pendidikan Terakhir',
                        _selectedEducation,
                        _educationOptions,
                        (val) => setState(() => _selectedEducation = val!)),
                    _buildDropdownField(
                        'Status Pernikahan',
                        _selectedMaritalStatus,
                        _maritalStatusOptions,
                        (val) => setState(() => _selectedMaritalStatus = val!),
                        width: 300),
                    _buildTextField(_spouseNameCtrl, 'Nama Pasangan',
                        width: 300),
                    _buildTextField(_spouseBirthDateCtrl, 'Tgl Lahir Pasangan',
                        width: 300,
                        readOnly: true,
                        onTap: () =>
                            _selectDate(context, _spouseBirthDateCtrl)),
                    _buildTextField(_childrenDataCtrl, 'Data Anak (Teks/JSON)',
                        width: 616),
                    _buildTextField(_emergencyNameCtrl, 'Nama Kontak Darurat',
                        width: 300),
                    _buildTextField(_emergencyPhoneCtrl, 'Telp Kontak Darurat',
                        width: 300),
                    _buildTextField(_addressKtpCtrl, 'Alamat KTP', width: 616),
                    _buildTextField(_addressNowCtrl, 'Alamat Domisili Sekarang',
                        width: 616),
                    _buildTextField(_jabatanCtrl, 'Jabatan', width: 300),
                    if (_departments.isNotEmpty)
                      SizedBox(
                        width: 300,
                        child: DropdownButtonFormField<int>(
                          value: _selectedDepartmentId,
                          items: _departments.map((dept) {
                            return DropdownMenuItem<int>(
                              value: dept['id'],
                              child: Text(dept['name'],
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (val) =>
                              setState(() => _selectedDepartmentId = val),
                          decoration: InputDecoration(
                            labelText: 'Departemen/Divisi',
                            labelStyle:
                                GoogleFonts.plusJakartaSans(fontSize: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                    _buildDropdownField('Role', _selectedRole, _roleOptions,
                        (val) => setState(() => _selectedRole = val!)),
                    _buildDropdownField(
                        'Status Akun',
                        _selectedAccountStatus,
                        ['Aktif', 'Non-Aktif'],
                        (val) => setState(() => _selectedAccountStatus = val!)),
                    _buildDropdownField(
                        'Status Karyawan',
                        _selectedEmpStatus,
                        ['Tetap', 'Kontrak', 'Magang'],
                        (val) => setState(() {
                              _selectedEmpStatus = val!;
                              if (val == 'Tetap') {
                                _contractNumberCtrl.clear();
                                _contractStartCtrl.clear();
                                _contractEndCtrl.clear();
                                _selectedFileBytes = null;
                                _selectedFileName = null;
                              }
                            })),
                    if (_selectedEmpStatus == 'Kontrak' ||
                        _selectedEmpStatus == 'Magang') ...[
                      _buildTextField(_contractNumberCtrl, 'No. Kontrak',
                          width: 616),
                      _buildTextField(_contractStartCtrl, 'Tgl Mulai',
                          width: 300,
                          readOnly: true,
                          onTap: () =>
                              _selectDate(context, _contractStartCtrl)),
                      _buildTextField(_contractEndCtrl, 'Tgl Selesai',
                          width: 300,
                          readOnly: true,
                          onTap: () => _selectDate(context, _contractEndCtrl)),
                    ],
                    if (_selectedEmpStatus == 'Kontrak')
                      SizedBox(
                        width: 616,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Surat Kontrak (PDF)',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12, color: Colors.grey[700])),
                            const SizedBox(height: 4),
                            OutlinedButton.icon(
                              onPressed: _pickFile,
                              icon: const Icon(Icons.upload_file, size: 16),
                              label: Text(
                                _selectedFileName ??
                                    'Pilih File PDF (Opsional)',
                                style:
                                    GoogleFonts.plusJakartaSans(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 14),
                                alignment: Alignment.centerLeft,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Batal',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text('Simpan Data',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    double width = 300,
    bool isPassword = false,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        readOnly: readOnly,
        onTap: onTap,
        style: GoogleFonts.plusJakartaSans(fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildDropdownField(
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged, {
    double width = 300,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        value: items.contains(value) ? value : items.first,
        items: items
            .map((e) => DropdownMenuItem(
                value: e,
                child:
                    Text(e, style: GoogleFonts.plusJakartaSans(fontSize: 12))))
            .toList(),
        onChanged: onChanged,
        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.black87),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}

class EditKaryawanDialog extends StatefulWidget {
  final Map<String, dynamic> karyawan;
  final VoidCallback onSuccess;
  const EditKaryawanDialog(
      {super.key, required this.karyawan, required this.onSuccess});

  @override
  State<EditKaryawanDialog> createState() => _EditKaryawanDialogState();
}

class _EditKaryawanDialogState extends State<EditKaryawanDialog> {
  bool _isSaving = false;
  bool _isLoadingContracts = true;
  List<dynamic> _contractHistory = [];

  late TextEditingController _nikCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _birthPlaceCtrl;
  late TextEditingController _birthDateCtrl;
  late TextEditingController _ktpCtrl;
  late TextEditingController _npwpCtrl;
  late TextEditingController _addressKtpCtrl;
  late TextEditingController _addressNowCtrl;

  late String _selectedMaritalStatus;
  final List<String> _maritalStatusOptions = ['Single', 'Menikah', 'Bercerai'];

  late TextEditingController _spouseNameCtrl;
  late TextEditingController _spouseBirthDateCtrl;
  late TextEditingController _childrenDataCtrl;
  late TextEditingController _emergencyNameCtrl;
  late TextEditingController _emergencyPhoneCtrl;
  late TextEditingController _jabatanCtrl;
  late TextEditingController _joinDateCtrl;
  late TextEditingController _contractNumberCtrl;

  late String _selectedRole;
  final List<String> _roleOptions = ['Staff', 'Supervisor', 'Manager', 'Admin'];

  late String _selectedGender;
  final List<String> _genderOptions = ['Laki-laki', 'Perempuan'];

  late String _selectedReligion;
  final List<String> _religionOptions = [
    'Islam',
    'Kristen',
    'Katolik',
    'Hindu',
    'Buddha',
    'Konghucu',
    'Lainnya'
  ];

  late String _selectedEducation;
  final List<String> _educationOptions = [
    'SD',
    'SMP',
    'SMA/SMK',
    'D3',
    'D4',
    'S1',
    'S2',
    'S3'
  ];

  late String _selectedEmpStatus;
  late String _selectedAccountStatus;

  late TextEditingController _contractStartCtrl;
  late TextEditingController _contractEndCtrl;

  List<Map<String, dynamic>> _departments = [];
  int? _selectedDepartmentId;

  @override
  void initState() {
    super.initState();
    _nikCtrl = TextEditingController(text: widget.karyawan['nik'] ?? '');
    _nameCtrl = TextEditingController(text: widget.karyawan['full_name'] ?? '');
    _emailCtrl = TextEditingController(text: widget.karyawan['email'] ?? '');
    _phoneCtrl = TextEditingController(text: widget.karyawan['phone'] ?? '');

    String dbGender = widget.karyawan['gender'] ?? 'Laki-laki';
    _selectedGender =
        _genderOptions.contains(dbGender) ? dbGender : 'Laki-laki';

    String dbReligion = widget.karyawan['religion'] ?? 'Islam';
    _selectedReligion =
        _religionOptions.contains(dbReligion) ? dbReligion : 'Islam';

    String dbEducation = widget.karyawan['education'] ?? 'S1';
    _selectedEducation =
        _educationOptions.contains(dbEducation) ? dbEducation : 'S1';

    String dbMarital = widget.karyawan['marital_status'] ?? 'Single';
    _selectedMaritalStatus =
        _maritalStatusOptions.contains(dbMarital) ? dbMarital : 'Single';

    String dbRole = widget.karyawan['role']?.toString() ?? 'Staff';
    String formattedRole = _roleOptions.firstWhere(
      (r) => r.toLowerCase() == dbRole.toLowerCase(),
      orElse: () => 'Staff',
    );
    _selectedRole = formattedRole;

    _birthPlaceCtrl =
        TextEditingController(text: widget.karyawan['birth_place'] ?? '');
    _birthDateCtrl =
        TextEditingController(text: widget.karyawan['birth_date'] ?? '');
    _ktpCtrl = TextEditingController(text: widget.karyawan['ktp_number'] ?? '');
    _npwpCtrl =
        TextEditingController(text: widget.karyawan['npwp_number'] ?? '');
    _addressKtpCtrl =
        TextEditingController(text: widget.karyawan['address_ktp'] ?? '');
    _addressNowCtrl =
        TextEditingController(text: widget.karyawan['address_now'] ?? '');
    _spouseNameCtrl =
        TextEditingController(text: widget.karyawan['spouse_name'] ?? '');
    _spouseBirthDateCtrl =
        TextEditingController(text: widget.karyawan['spouse_birth_date'] ?? '');

    var rawChildren = widget.karyawan['children_data'];
    String childrenText = '';
    if (rawChildren != null) {
      if (rawChildren is String) {
        childrenText = rawChildren;
      } else {
        childrenText = jsonEncode(rawChildren);
      }
    }
    _childrenDataCtrl = TextEditingController(text: childrenText);

    _emergencyNameCtrl =
        TextEditingController(text: widget.karyawan['emergency_name'] ?? '');
    _emergencyPhoneCtrl =
        TextEditingController(text: widget.karyawan['emergency_phone'] ?? '');
    _jabatanCtrl =
        TextEditingController(text: widget.karyawan['jabatan_name'] ?? '');
    _joinDateCtrl =
        TextEditingController(text: widget.karyawan['join_date'] ?? '');
    _contractNumberCtrl = TextEditingController(
        text: widget.karyawan['contract_number']?.toString() ?? '');

    _selectedAccountStatus =
        (widget.karyawan['is_active'] == false) ? 'Non-Aktif' : 'Aktif';

    String rawEmpStatus =
        widget.karyawan['employee_status']?.toString().toLowerCase() ?? 'tetap';
    if (rawEmpStatus == 'kontrak') {
      _selectedEmpStatus = 'Kontrak';
    } else if (rawEmpStatus == 'magang') {
      _selectedEmpStatus = 'Magang';
    } else {
      _selectedEmpStatus = 'Tetap';
    }

    _contractStartCtrl =
        TextEditingController(text: widget.karyawan['contract_start'] ?? '');
    _contractEndCtrl =
        TextEditingController(text: widget.karyawan['contract_end'] ?? '');

    if (widget.karyawan['department_id'] != null) {
      _selectedDepartmentId =
          int.tryParse(widget.karyawan['department_id'].toString());
    }

    _fetchDepartments();
    _fetchContractHistory();
  }

  Future<void> _fetchDepartments() async {
    try {
      final res = await Supabase.instance.client
          .from('departments')
          .select('id, name')
          .order('name', ascending: true);

      if (mounted) {
        setState(() {
          _departments = List<Map<String, dynamic>>.from(res);
          if (_selectedDepartmentId != null &&
              !_departments.any((d) => d['id'] == _selectedDepartmentId)) {
            _selectedDepartmentId =
                _departments.isNotEmpty ? _departments.first['id'] : null;
          } else if (_selectedDepartmentId == null && _departments.isNotEmpty) {
            _selectedDepartmentId = _departments.first['id'];
          }
        });
      }
    } catch (e) {
      debugPrint("Gagal mengambil data departemen: $e");
    }
  }

  int _mapRoleToPositionId(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'manager':
        return 1;
      case 'supervisor':
        return 2;
      case 'staff':
      default:
        return 3;
    }
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

  Future<void> _showAddContractDialog() async {
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();
    final historyContractNumCtrl = TextEditingController();
    Uint8List? fileBytes;
    String? fileName;

    Future<void> selectDate(
        BuildContext ctx, TextEditingController ctrl) async {
      final picked = await showDatePicker(
        context: ctx,
        initialDate: DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) {
        ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
      }
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDlg) {
          return AlertDialog(
            title: Text('Tambah Perpanjangan Kontrak',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: startCtrl,
                    readOnly: true,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                    onTap: () => selectDate(context, startCtrl),
                    decoration: InputDecoration(
                        labelText: 'Tanggal Mulai Kontrak',
                        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                        border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: endCtrl,
                    readOnly: true,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                    onTap: () => selectDate(context, endCtrl),
                    decoration: InputDecoration(
                        labelText: 'Tanggal Selesai Kontrak',
                        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                        border: const OutlineInputBorder()),
                  ),
                  if (_selectedEmpStatus == 'Kontrak' ||
                      _selectedEmpStatus == 'Magang') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: historyContractNumCtrl,
                      style: GoogleFonts.plusJakartaSans(fontSize: 12),
                      decoration: InputDecoration(
                          labelText: 'No. Kontrak',
                          labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                          border: const OutlineInputBorder()),
                    ),
                  ],
                  if (_selectedEmpStatus == 'Kontrak') ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        FilePickerResult? result = await FilePicker.platform
                            .pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['pdf']);
                        if (result != null &&
                            result.files.single.bytes != null) {
                          setStateDlg(() {
                            fileBytes = result.files.single.bytes;
                            fileName = result.files.single.name;
                          });
                        }
                      },
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: Text(
                          fileName ?? 'Upload Surat Kontrak (PDF/Opsional)',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                    ),
                  ]
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Batal',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  if (startCtrl.text.isEmpty || endCtrl.text.isEmpty) return;

                  try {
                    String? contractNum = historyContractNumCtrl.text.isNotEmpty
                        ? historyContractNumCtrl.text
                        : null;

                    String? fileUrl;
                    if (_selectedEmpStatus == 'Kontrak' &&
                        fileBytes != null &&
                        fileName != null) {
                      final timestamp = DateTime.now().millisecondsSinceEpoch;
                      final filePath =
                          'contract_${widget.karyawan['nik']}_${timestamp}_$fileName';
                      await Supabase.instance.client.storage
                          .from('contracts')
                          .uploadBinary(filePath, fileBytes!);
                      fileUrl = Supabase.instance.client.storage
                          .from('contracts')
                          .getPublicUrl(filePath);
                    }

                    await Supabase.instance.client
                        .from('employee_contracts')
                        .insert({
                      'employee_id': widget.karyawan['id'],
                      'contract_start': startCtrl.text,
                      'contract_end': endCtrl.text,
                      'contract_number': contractNum,
                      'contract_file': fileUrl,
                    });

                    await Supabase.instance.client.from('employees').update({
                      'contract_start': startCtrl.text,
                      'contract_end': endCtrl.text,
                      if (contractNum != null) 'contract_number': contractNum,
                      if (fileUrl != null) 'contract_file': fileUrl,
                    }).eq('id', widget.karyawan['id']);

                    await AppLogger.log(
                      activity:
                          'Memperbarui biodata karyawan: ${_nameCtrl.text}',
                      module: 'Data Karyawan',
                    );

                    Navigator.pop(context);

                    if (contractNum != null) {
                      setState(() {
                        _contractNumberCtrl.text = contractNum;
                      });
                    }
                    _fetchContractHistory();

                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Kontrak berhasil diperpanjang!'),
                        backgroundColor: Colors.green));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Gagal: $e'),
                        backgroundColor: Colors.red));
                  }
                },
                child: Text('Simpan',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateData() async {
    setState(() => _isSaving = true);
    try {
      dynamic childrenVal;
      try {
        childrenVal = _childrenDataCtrl.text.isNotEmpty
            ? jsonDecode(_childrenDataCtrl.text)
            : null;
      } catch (_) {
        childrenVal =
            _childrenDataCtrl.text.isNotEmpty ? _childrenDataCtrl.text : null;
      }

      bool newIsActive = _selectedAccountStatus == 'Aktif';
      String? userId = widget.karyawan['user_id'];

      if (userId != null && userId.isNotEmpty) {
        await Supabase.instance.client.rpc(
          'admin_set_user_active_status',
          params: {
            'target_user_id': userId,
            'is_active': newIsActive,
          },
        );
      }

      final int positionId = _mapRoleToPositionId(_selectedRole);
      final String? contractNum =
          (_selectedEmpStatus == 'Kontrak' || _selectedEmpStatus == 'Magang') &&
                  _contractNumberCtrl.text.isNotEmpty
              ? _contractNumberCtrl.text
              : null;

      await Supabase.instance.client.from('employees').update({
        'nik': _nikCtrl.text,
        'full_name': _nameCtrl.text,
        'email': _emailCtrl.text,
        'phone': _phoneCtrl.text,
        'gender': _selectedGender,
        'religion': _selectedReligion,
        'birth_place': _birthPlaceCtrl.text,
        'birth_date':
            _birthDateCtrl.text.isNotEmpty ? _birthDateCtrl.text : null,
        'ktp_number': _ktpCtrl.text,
        'npwp_number': _npwpCtrl.text,
        'address_ktp': _addressKtpCtrl.text,
        'address_now': _addressNowCtrl.text,
        'education': _selectedEducation,
        'marital_status': _selectedMaritalStatus,
        'spouse_name': _spouseNameCtrl.text,
        'spouse_birth_date': _spouseBirthDateCtrl.text.isNotEmpty
            ? _spouseBirthDateCtrl.text
            : null,
        'children_data': childrenVal,
        'emergency_name': _emergencyNameCtrl.text,
        'emergency_phone': _emergencyPhoneCtrl.text,
        'jabatan_name': _jabatanCtrl.text,
        'department_id': _selectedDepartmentId,
        'join_date': _joinDateCtrl.text.isNotEmpty ? _joinDateCtrl.text : null,
        'role': _selectedRole,
        'position_id': positionId,
        'is_active': newIsActive,
        'employee_status': _selectedEmpStatus,
        'contract_number': contractNum,
        'contract_start': (_selectedEmpStatus == 'Kontrak' ||
                    _selectedEmpStatus == 'Magang') &&
                _contractStartCtrl.text.isNotEmpty
            ? _contractStartCtrl.text
            : null,
        'contract_end': (_selectedEmpStatus == 'Kontrak' ||
                    _selectedEmpStatus == 'Magang') &&
                _contractEndCtrl.text.isNotEmpty
            ? _contractEndCtrl.text
            : null,
      }).eq('id', widget.karyawan['id']);

      await AppLogger.log(
        activity: 'Memperbarui biodata karyawan: ${_nameCtrl.text}',
        module: 'Data Karyawan',
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Data dan status akun berhasil diperbarui',
                style: GoogleFonts.plusJakartaSans(fontSize: 12)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memperbarui: $e',
                style: GoogleFonts.plusJakartaSans(fontSize: 12)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd-MM-yyyy').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit Biodata Karyawan & Riwayat Kontrak',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _buildTextField(_nikCtrl, 'NIK', width: 300),
                        _buildTextField(_nameCtrl, 'Nama Lengkap', width: 300),
                        _buildTextField(_emailCtrl, 'Email', width: 300),
                        _buildTextField(_phoneCtrl, 'No. Telepon', width: 300),
                        _buildDropdownField(
                            'Jenis Kelamin',
                            _selectedGender,
                            _genderOptions,
                            (val) => setState(() => _selectedGender = val!)),
                        _buildDropdownField(
                            'Agama',
                            _selectedReligion,
                            _religionOptions,
                            (val) => setState(() => _selectedReligion = val!)),
                        _buildTextField(_birthPlaceCtrl, 'Tempat Lahir',
                            width: 300),
                        _buildTextField(_birthDateCtrl, 'Tanggal Lahir',
                            width: 300, readOnly: true, onTap: () async {
                          final p = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(1940),
                              lastDate: DateTime(2100));
                          if (p != null) {
                            setState(() => _birthDateCtrl.text =
                                DateFormat('yyyy-MM-dd').format(p));
                          }
                        }),
                        _buildTextField(_ktpCtrl, 'Nomor KTP', width: 300),
                        _buildTextField(_npwpCtrl, 'Nomor NPWP', width: 300),
                        _buildDropdownField(
                            'Pendidikan Terakhir',
                            _selectedEducation,
                            _educationOptions,
                            (val) => setState(() => _selectedEducation = val!)),
                        _buildDropdownField(
                            'Status Pernikahan',
                            _selectedMaritalStatus,
                            _maritalStatusOptions,
                            (val) =>
                                setState(() => _selectedMaritalStatus = val!),
                            width: 300),
                        _buildTextField(_spouseNameCtrl, 'Nama Pasangan',
                            width: 300),
                        _buildTextField(
                            _spouseBirthDateCtrl, 'Tgl Lahir Pasangan',
                            width: 300, readOnly: true, onTap: () async {
                          final p = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(1940),
                              lastDate: DateTime(2100));
                          if (p != null) {
                            setState(() => _spouseBirthDateCtrl.text =
                                DateFormat('yyyy-MM-dd').format(p));
                          }
                        }),
                        _buildTextField(
                            _childrenDataCtrl, 'Data Anak (Teks/JSON)',
                            width: 616),
                        _buildTextField(
                            _emergencyNameCtrl, 'Nama Kontak Darurat',
                            width: 300),
                        _buildTextField(
                            _emergencyPhoneCtrl, 'Telp Kontak Darurat',
                            width: 300),
                        _buildTextField(_addressKtpCtrl, 'Alamat KTP',
                            width: 616),
                        _buildTextField(
                            _addressNowCtrl, 'Alamat Domisili Sekarang',
                            width: 616),
                        _buildTextField(_jabatanCtrl, 'Jabatan', width: 300),
                        if (_departments.isNotEmpty)
                          SizedBox(
                            width: 300,
                            child: DropdownButtonFormField<int>(
                              value: _selectedDepartmentId,
                              items: _departments.map((dept) {
                                return DropdownMenuItem<int>(
                                  value: dept['id'],
                                  child: Text(dept['name'],
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12)),
                                );
                              }).toList(),
                              onChanged: (val) =>
                                  setState(() => _selectedDepartmentId = val),
                              decoration: InputDecoration(
                                labelText: 'Departemen/Divisi',
                                labelStyle:
                                    GoogleFonts.plusJakartaSans(fontSize: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                              ),
                            ),
                          ),
                        _buildTextField(_joinDateCtrl, 'Tanggal Masuk',
                            width: 300, readOnly: true, onTap: () async {
                          final p = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100));
                          if (p != null) {
                            setState(() => _joinDateCtrl.text =
                                DateFormat('yyyy-MM-dd').format(p));
                          }
                        }),
                        _buildDropdownField('Role', _selectedRole, _roleOptions,
                            (val) => setState(() => _selectedRole = val!)),
                        _buildDropdownField(
                            'Status Karyawan',
                            _selectedEmpStatus,
                            ['Tetap', 'Kontrak', 'Magang'],
                            (val) => setState(() => _selectedEmpStatus = val!)),
                        _buildDropdownField(
                            'Status Akun',
                            _selectedAccountStatus,
                            ['Aktif', 'Non-Aktif'],
                            (val) =>
                                setState(() => _selectedAccountStatus = val!)),
                        if (_selectedEmpStatus == 'Kontrak' ||
                            _selectedEmpStatus == 'Magang') ...[
                          _buildTextField(_contractNumberCtrl, 'No. Kontrak',
                              width: 616),
                          _buildTextField(_contractStartCtrl, 'Tgl Mulai',
                              width: 300, readOnly: true, onTap: () async {
                            final p = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100));
                            if (p != null) {
                              setState(() => _contractStartCtrl.text =
                                  DateFormat('yyyy-MM-dd').format(p));
                            }
                          }),
                          _buildTextField(_contractEndCtrl, 'Tgl Selesai',
                              width: 300, readOnly: true, onTap: () async {
                            final p = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100));
                            if (p != null) {
                              setState(() => _contractEndCtrl.text =
                                  DateFormat('yyyy-MM-dd').format(p));
                            }
                          }),
                        ],
                      ],
                    ),
                    if (_selectedEmpStatus == 'Kontrak' ||
                        _selectedEmpStatus == 'Magang') ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Riwayat Perpanjangan Kontrak',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[800])),
                          ElevatedButton.icon(
                            onPressed: _showAddContractDialog,
                            icon: const Icon(Icons.add, size: 14),
                            label: Text('Tambah Kontrak Baru',
                                style:
                                    GoogleFonts.plusJakartaSans(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _isLoadingContracts
                          ? const Center(child: CircularProgressIndicator())
                          : _contractHistory.isEmpty
                              ? Text('Belum ada riwayat kontrak.',
                                  style:
                                      GoogleFonts.plusJakartaSans(fontSize: 12))
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _contractHistory.length,
                                  itemBuilder: (context, index) {
                                    final c = _contractHistory[index];
                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: ListTile(
                                        title: Text(
                                            'Periode: ${_formatDate(c['contract_start'])} s/d ${_formatDate(c['contract_end'])}',
                                            style: GoogleFonts.plusJakartaSans(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold)),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (c['contract_number'] != null &&
                                                c['contract_number']
                                                    .toString()
                                                    .isNotEmpty)
                                              Text(
                                                  'No: ${c['contract_number']}   ',
                                                  style: GoogleFonts
                                                      .plusJakartaSans(
                                                          fontSize: 11,
                                                          color:
                                                              Colors.blue[700]))
                                            else
                                              Text('Tanpa No.   ',
                                                  style: GoogleFonts
                                                      .plusJakartaSans(
                                                          fontSize: 10,
                                                          color: Colors.grey)),
                                            if (c['contract_file'] != null &&
                                                c['contract_file']
                                                    .toString()
                                                    .isNotEmpty)
                                              IconButton(
                                                icon: const Icon(Icons.download,
                                                    color: Colors.teal,
                                                    size: 20),
                                                tooltip: 'Download PDF',
                                                onPressed: () => _downloadFile(
                                                    c['contract_file']),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Batal',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12))),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isSaving ? null : _updateData,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white),
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text('Simpan Perubahan',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label,
      {double width = 300, bool readOnly = false, VoidCallback? onTap}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        style: GoogleFonts.plusJakartaSans(fontSize: 12),
        decoration: InputDecoration(
            labelText: label,
            labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
      ),
    );
  }

  Widget _buildDropdownField(String label, String value, List<String> items,
      ValueChanged<String?> onChanged,
      {double width = 300}) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        value: items.contains(value) ? value : items.first,
        items: items
            .map((e) => DropdownMenuItem(
                value: e,
                child:
                    Text(e, style: GoogleFonts.plusJakartaSans(fontSize: 12))))
            .toList(),
        onChanged: onChanged,
        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.black87),
        decoration: InputDecoration(
            labelText: label,
            labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
      ),
    );
  }
}

class KaryawanLeaveBalanceDialog extends StatefulWidget {
  final dynamic userUuid;
  final String empName;
  final Map<String, dynamic>? initialBalance;
  final VoidCallback onSuccess;

  const KaryawanLeaveBalanceDialog({
    super.key,
    required this.userUuid,
    required this.empName,
    required this.initialBalance,
    required this.onSuccess,
  });

  @override
  State<KaryawanLeaveBalanceDialog> createState() =>
      _KaryawanLeaveBalanceDialogState();
}

class _KaryawanLeaveBalanceDialogState
    extends State<KaryawanLeaveBalanceDialog> {
  bool _isEditing = false;
  bool _isSaving = false;

  late TextEditingController _totalCtrl;
  late TextEditingController _usedCtrl;
  late TextEditingController _remainingCtrl;
  DateTime? _selectedResetDate;

  @override
  void initState() {
    super.initState();
    _totalCtrl = TextEditingController(
      text: widget.initialBalance?['total_leave']?.toString() ?? '12',
    );
    _usedCtrl = TextEditingController(
      text: widget.initialBalance?['used_leave']?.toString() ?? '0',
    );
    _remainingCtrl = TextEditingController(
      text: widget.initialBalance?['remaining_leave']?.toString() ?? '12',
    );

    if (widget.initialBalance?['next_reset_date'] != null) {
      _selectedResetDate = DateTime.tryParse(
        widget.initialBalance!['next_reset_date'].toString(),
      );
    }
  }

  @override
  void dispose() {
    _totalCtrl.dispose();
    _usedCtrl.dispose();
    _remainingCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickResetDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _selectedResetDate ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _selectedResetDate = picked);
    }
  }

  Future<void> _saveBalance() async {
    setState(() => _isSaving = true);
    try {
      if (widget.userUuid == null || widget.userUuid.toString().isEmpty) {
        throw 'User UUID tidak ditemukan.';
      }

      final total = int.tryParse(_totalCtrl.text) ?? 12;
      final used = int.tryParse(_usedCtrl.text) ?? 0;
      final remaining = int.tryParse(_remainingCtrl.text) ?? (total - used);

      final payload = {
        'user_id': widget.userUuid,
        'total_leave': total,
        'used_leave': used,
        'remaining_leave': remaining,
        'next_reset_date': _selectedResetDate != null
            ? DateFormat('yyyy-MM-dd').format(_selectedResetDate!)
            : null,
      };

      await Supabase.instance.client
          .from('leave_balance')
          .upsert(payload, onConflict: 'user_id');

      await AppLogger.log(
        activity:
            'Memperbarui saldo cuti untuk ${widget.empName} (Sisa: $remaining Hari)',
        module: 'Data Karyawan',
      );

      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saldo cuti berhasil diperbarui!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSuccess();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan saldo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatTgl(String? tgl) {
    if (tgl == null || tgl.isEmpty) return '-';
    try {
      DateTime dt = DateTime.parse(tgl.split('T')[0]);
      return DateFormat('dd-MM-yyyy').format(dt);
    } catch (_) {
      return tgl;
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextResetStr = _selectedResetDate != null
        ? DateFormat('dd-MM-yyyy').format(_selectedResetDate!)
        : _formatTgl(widget.initialBalance?['next_reset_date']);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 450),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Informasi & Saldo Cuti',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Karyawan: ${widget.empName}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[800],
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _isEditing = !_isEditing),
                    icon: Icon(_isEditing ? Icons.close : Icons.edit, size: 14),
                    label: Text(
                      _isEditing ? 'Batal Edit' : 'Edit Saldo',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: _isEditing
                    ? Column(
                        children: [
                          _buildEditRow('Total Kuota Cuti', _totalCtrl),
                          const SizedBox(height: 8),
                          _buildEditRow('Cuti Terpakai', _usedCtrl),
                          const SizedBox(height: 8),
                          _buildEditRow('Sisa Cuti', _remainingCtrl),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Expanded(
                                flex: 2,
                                child: Text(
                                  'Reset Berikutnya',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: OutlinedButton(
                                  onPressed: _pickResetDate,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    minimumSize: const Size(0, 32),
                                  ),
                                  child: Text(
                                    _selectedResetDate != null
                                        ? DateFormat(
                                            'dd-MM-yyyy',
                                          ).format(_selectedResetDate!)
                                        : 'Pilih Tgl',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _isSaving ? null : _saveBalance,
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Simpan Perubahan Saldo',
                                      style: TextStyle(fontSize: 12),
                                    ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _buildBalanceRow(
                            'Total Kuota Cuti',
                            '${_totalCtrl.text} Hari',
                          ),
                          const Divider(),
                          _buildBalanceRow(
                            'Cuti Terpakai',
                            '${_usedCtrl.text} Hari',
                            textColor: Colors.orange[800],
                          ),
                          const Divider(),
                          _buildBalanceRow(
                            'Sisa Cuti',
                            '${_remainingCtrl.text} Hari',
                            textColor: Colors.green[800],
                            isBold: true,
                          ),
                          const Divider(),
                          _buildBalanceRow('Reset Berikutnya', nextResetStr),
                        ],
                      ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
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
  }

  Widget _buildBalanceRow(
    String label,
    String value, {
    Color? textColor,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: textColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditRow(String label, TextEditingController ctrl) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 1,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            style: GoogleFonts.plusJakartaSans(fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}
