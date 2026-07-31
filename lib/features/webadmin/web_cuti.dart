import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class WebCutiPage extends StatefulWidget {
  const WebCutiPage({super.key});

  @override
  State<WebCutiPage> createState() => _WebCutiPageState();
}

class _WebCutiPageState extends State<WebCutiPage> {
  List<dynamic> _cutiList = [];
  List<dynamic> _filteredList = [];
  bool _isLoading = true;

  final TextEditingController _searchNameCtrl = TextEditingController();
  DateTime? _selectedDateFilter;
  String _selectedStatusFilter = 'all';

  int _rowsPerPage = 50;
  final List<int> _pageOptions = [50, 100, 200];

  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchCutiData();
  }

  @override
  void dispose() {
    _searchNameCtrl.dispose();
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  Future<void> _fetchCutiData() async {
    setState(() => _isLoading = true);
    try {
      final cutiResponse = await Supabase.instance.client
          .from('leave_requests')
          .select()
          .order('created_at', ascending: false);

      final employeesResponse = await Supabase.instance.client
          .from('employees')
          .select('id, full_name');

      // Mengubah mapping ke bentuk Integer (angka) agar sesuai dengan struktur DB
      final Map<int, String> employeeMap = {};
      for (var emp in employeesResponse) {
        if (emp['id'] != null) {
          int? parsedId = int.tryParse(emp['id'].toString());
          if (parsedId != null) {
            employeeMap[parsedId] = emp['full_name'] ?? '-';
          }
        }
      }

      List<dynamic> processedData = [];

      for (var item in cutiResponse) {
        var mutableItem = Map<String, dynamic>.from(item);

        // Parsing aman ID ke integer
        int? empId = int.tryParse(mutableItem['employee_id']?.toString() ?? '');
        int? approverId =
            int.tryParse(mutableItem['approved_by']?.toString() ?? '');

        mutableItem['employees'] = {
          'full_name': employeeMap[empId] ?? 'Karyawan Tidak Ditemukan',
        };
        // Menyimpan nama Admin/Approver
        mutableItem['approver_name'] = employeeMap[approverId] ?? '-';

        processedData.add(mutableItem);
      }

      _cutiList = processedData;
      _applyLocalFilter();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal mengambil data cuti: $e',
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

  void _applyLocalFilter() {
    List<dynamic> temp = List.from(_cutiList);

    if (_selectedStatusFilter != 'all') {
      temp = temp.where((item) {
        final status =
            (item['status'] ?? 'pending').toString().trim().toLowerCase();
        return status == _selectedStatusFilter;
      }).toList();
    }

    if (_searchNameCtrl.text.trim().isNotEmpty) {
      final search = _searchNameCtrl.text.trim().toLowerCase();
      temp = temp.where((item) {
        final empName =
            (item['employees']?['full_name'] ?? '').toString().toLowerCase();
        return empName.contains(search);
      }).toList();
    }

    if (_selectedDateFilter != null) {
      temp = temp.where((item) {
        if (item['start_date'] == null || item['end_date'] == null) {
          return false;
        }
        try {
          DateTime start = DateTime.parse(item['start_date']);
          DateTime end = DateTime.parse(item['end_date']);
          DateTime filter = DateTime(
            _selectedDateFilter!.year,
            _selectedDateFilter!.month,
            _selectedDateFilter!.day,
          );

          DateTime startDateOnly = DateTime(start.year, start.month, start.day);
          DateTime endDateOnly = DateTime(end.year, end.month, end.day);

          return (filter.isAtSameMomentAs(startDateOnly) ||
                  filter.isAfter(startDateOnly)) &&
              (filter.isAtSameMomentAs(endDateOnly) ||
                  filter.isBefore(endDateOnly));
        } catch (_) {
          return false;
        }
      }).toList();
    }

    setState(() {
      _filteredList = temp;
    });
  }

  Future<void> _deleteCuti(Map<String, dynamic> item) async {
    final empName = item['employees']?['full_name'] ?? 'Karyawan';
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
          'Yakin ingin menghapus pengajuan cuti/izin $empName?',
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
            .from('leave_requests')
            .delete()
            .eq('id', item['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Data berhasil dihapus',
                style: GoogleFonts.plusJakartaSans(fontSize: 12),
              ),
            ),
          );
          _fetchCutiData();
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

  Future<void> _pickFilterDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateFilter ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDateFilter = picked);
      _applyLocalFilter();
    }
  }

  void _clearFilter() {
    setState(() {
      _searchNameCtrl.clear();
      _selectedDateFilter = null;
      _selectedStatusFilter = 'all';
    });
    _applyLocalFilter();
  }

  String _formatTanggal(String? tgl) {
    if (tgl == null || tgl.isEmpty) return '-';
    try {
      DateTime dt = DateTime.parse(tgl.split('T')[0]);
      return DateFormat('dd-MM-yyyy').format(dt);
    } catch (_) {
      return tgl;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'disetujui':
        return Colors.green;
      case 'rejected':
      case 'ditolak':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Future<void> _showLeaveBalanceDialog(Map<String, dynamic> item) async {
    final empIdRaw = item['employee_id'];
    final int? empId =
        empIdRaw != null ? int.tryParse(empIdRaw.toString()) : null;
    final userUuid = item['user_id'];
    final empName = item['employees']?['full_name'] ?? 'Karyawan';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic>? balanceData;
    try {
      if (userUuid != null) {
        balanceData = await Supabase.instance.client
            .from('leave_balance')
            .select()
            .eq('user_id', userUuid)
            .maybeSingle();
      }

      if (balanceData == null && empId != null) {
        balanceData = await Supabase.instance.client
            .from('leave_balance')
            .select()
            .eq('employee_id', empId)
            .maybeSingle();
      }

      if (balanceData == null) {
        final allBalances =
            await Supabase.instance.client.from('leave_balance').select();
        for (var bal in allBalances) {
          if ((bal['employee_id'] != null &&
                  bal['employee_id'].toString() == empId?.toString()) ||
              (bal['user_id'] != null &&
                  bal['user_id'].toString() == userUuid?.toString())) {
            balanceData = bal;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching balance: $e');
      balanceData = null;
    }

    if (mounted) Navigator.pop(context);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => LeaveBalanceDetailDialog(
        empId: empId,
        userUuid: userUuid,
        empName: empName,
        initialBalance: balanceData,
        leaveRequestItem: item,
        onSuccess: _fetchCutiData,
      ),
    );
  }

  void _showAttachmentDialog(String? url, String empName) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Lampiran: $empName',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: url != null && url.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: InteractiveViewer(
                          child: Image.network(
                            url,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                              child: Text(
                                'Gagal memuat pratinjau gambar.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      )
                    : const Center(
                        child: Text('Tidak ada lampiran yang diunggah.'),
                      ),
              ),
              const SizedBox(height: 16),
              if (url != null && url.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Gagal mengunduh file lampiran.'),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(
                      'Download / Buka di Tab Baru',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateStatusCutiAdmin(
    int id,
    String newStatus,
    dynamic empIdRaw,
    dynamic userUuid,
    String startDate,
    String endDate,
  ) async {
    try {
      // 1. Ambil UUID dan Email Admin yang sedang login
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) throw 'Sesi admin tidak ditemukan';

      // 2. Cari ID Integer Admin dari tabel employees berdasarkan email
      final adminData = await Supabase.instance.client
          .from('employees')
          .select('id')
          .eq('email', currentUser.email!)
          .maybeSingle();

      final int? adminEmpId = adminData?['id']; // Ini adalah BigInt / Integer

      final int? empId =
          empIdRaw != null ? int.tryParse(empIdRaw.toString()) : null;

      // 3. Simpan adminEmpId (integer) ke approved_by
      await Supabase.instance.client.from('leave_requests').update({
        'status': newStatus,
        if (newStatus != 'pending') 'approved_by': adminEmpId
      }).eq('id', id);

      if (newStatus == 'approved') {
        DateTime start = DateTime.parse(startDate);
        DateTime end = DateTime.parse(endDate);
        int durasi = end.difference(start).inDays + 1;

        Map<String, dynamic>? balanceData;
        if (userUuid != null) {
          balanceData = await Supabase.instance.client
              .from('leave_balance')
              .select('*')
              .eq('user_id', userUuid)
              .maybeSingle();
        }
        if (balanceData == null && empId != null) {
          balanceData = await Supabase.instance.client
              .from('leave_balance')
              .select('*')
              .eq('employee_id', empId)
              .maybeSingle();
        }

        if (balanceData == null) {
          await Supabase.instance.client.from('leave_balance').insert({
            if (userUuid != null) 'user_id': userUuid,
            if (empId != null) 'employee_id': empId,
            'total_leave': 12,
            'used_leave': durasi,
            'remaining_leave': 12 - durasi,
          });
        } else {
          int currentUsed = balanceData['used_leave'] ?? 0;
          int currentRemaining = balanceData['remaining_leave'] ?? 12;

          final query = Supabase.instance.client.from('leave_balance').update({
            'used_leave': currentUsed + durasi,
            'remaining_leave': currentRemaining - durasi,
          });

          if (balanceData['id'] != null) {
            await query.eq('id', balanceData['id']);
          } else if (userUuid != null) {
            await query.eq('user_id', userUuid);
          } else if (empId != null) {
            await query.eq('employee_id', empId);
          }
        }
      }
      _fetchCutiData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Status cuti berhasil diperbarui!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal memperbarui status: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
                'Data Pengajuan Cuti & Izin',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[50],
                  foregroundColor: Colors.blue[900],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                onPressed: _fetchCutiData,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(
                  'Refresh Data',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: DropdownButton<String>(
                  value: _selectedStatusFilter,
                  underline: const SizedBox(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Semua Status')),
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text('Pending Saja'),
                    ),
                    DropdownMenuItem(
                      value: 'approved',
                      child: Text('Approved'),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rejected'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedStatusFilter = val);
                      _applyLocalFilter();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchNameCtrl,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Cari nama karyawan...',
                      hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 0,
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
                    onChanged: (val) => _applyLocalFilter(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: _pickFilterDate,
                    icon: const Icon(Icons.calendar_month, size: 16),
                    label: Text(
                      _selectedDateFilter == null
                          ? 'Filter Tanggal'
                          : DateFormat(
                              'dd-MM-yyyy',
                            ).format(_selectedDateFilter!),
                      style: GoogleFonts.plusJakartaSans(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Reset Filter',
                child: SizedBox(
                  height: 42,
                  width: 42,
                  child: OutlinedButton(
                    onPressed: _clearFilter,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                    child: const Icon(
                      Icons.refresh,
                      color: Colors.grey,
                      size: 18,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 42,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                    ],
                  ),
                ),
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
                            'Data cuti atau izin tidak ditemukan.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            return ScrollConfiguration(
                              behavior:
                                  ScrollConfiguration.of(context).copyWith(
                                dragDevices: {
                                  PointerDeviceKind.touch,
                                  PointerDeviceKind.mouse,
                                  PointerDeviceKind.trackpad,
                                },
                              ),
                              child: Scrollbar(
                                controller: _horizontalScroll,
                                thumbVisibility: true,
                                trackVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _horizontalScroll,
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth,
                                    ),
                                    child: Scrollbar(
                                      controller: _verticalScroll,
                                      thumbVisibility: true,
                                      child: SingleChildScrollView(
                                        controller: _verticalScroll,
                                        scrollDirection: Axis.vertical,
                                        child: DataTable(
                                          showCheckboxColumn: false,
                                          headingRowColor:
                                              WidgetStateProperty.all(
                                            Colors.grey[50],
                                          ),
                                          dataRowMaxHeight: 65,
                                          headingTextStyle:
                                              GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                          dataTextStyle:
                                              GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            color: Colors.black87,
                                          ),
                                          columns: const [
                                            DataColumn(label: Text('No')),
                                            DataColumn(label: Text('Karyawan')),
                                            DataColumn(label: Text('Jenis')),
                                            DataColumn(
                                              label: Text('Rentang Tanggal'),
                                            ),
                                            DataColumn(label: Text('Alasan')),
                                            DataColumn(label: Text('Lampiran')),
                                            DataColumn(label: Text('Status')),
                                            DataColumn(
                                                label: Text('Approved By')),
                                            DataColumn(label: Text('Action')),
                                          ],
                                          rows: List<DataRow>.generate(
                                            _filteredList.length > _rowsPerPage
                                                ? _rowsPerPage
                                                : _filteredList.length,
                                            (index) {
                                              final item = _filteredList[index];
                                              final String empName =
                                                  item['employees']
                                                          ?['full_name'] ??
                                                      'Karyawan';
                                              final String rawStatus =
                                                  (item['status'] ?? 'pending')
                                                      .toString()
                                                      .trim()
                                                      .toLowerCase();
                                              final statusColor =
                                                  _getStatusColor(
                                                rawStatus,
                                              );

                                              return DataRow(
                                                onSelectChanged: (selected) {
                                                  _showLeaveBalanceDialog(item);
                                                },
                                                cells: [
                                                  DataCell(
                                                      Text('${index + 1}')),
                                                  DataCell(
                                                    Text(
                                                      empName,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue
                                                            .withOpacity(0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                          4,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        item['leave_type'] ??
                                                            'Cuti',
                                                        style: const TextStyle(
                                                          color: Colors.blue,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      '${_formatTanggal(item['start_date'])} s/d ${_formatTanggal(item['end_date'])}',
                                                    ),
                                                  ),
                                                  DataCell(
                                                    SizedBox(
                                                      width: 160,
                                                      child: Text(
                                                        item['reason'] ?? '-',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        maxLines: 2,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    item['attachment_url'] !=
                                                            null
                                                        ? ElevatedButton.icon(
                                                            icon: const Icon(
                                                              Icons.attach_file,
                                                              size: 12,
                                                            ),
                                                            label: const Text(
                                                              'Lihat',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                              ),
                                                            ),
                                                            style:
                                                                ElevatedButton
                                                                    .styleFrom(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 8,
                                                                vertical: 2,
                                                              ),
                                                              backgroundColor:
                                                                  Colors
                                                                      .teal[50],
                                                              foregroundColor:
                                                                  Colors.teal[
                                                                      800],
                                                              elevation: 0,
                                                            ),
                                                            onPressed: () =>
                                                                _showAttachmentDialog(
                                                              item[
                                                                  'attachment_url'],
                                                              empName,
                                                            ),
                                                          )
                                                        : const Text(
                                                            '-',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.grey,
                                                            ),
                                                          ),
                                                  ),
                                                  DataCell(
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: statusColor
                                                            .withOpacity(0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                          4,
                                                        ),
                                                        border: Border.all(
                                                          color: statusColor,
                                                          width: 0.5,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        rawStatus.toUpperCase(),
                                                        style: TextStyle(
                                                          color: statusColor,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(Text(
                                                      item['approver_name'] ??
                                                          '-',
                                                      style: TextStyle(
                                                          color:
                                                              Colors.grey[700],
                                                          fontStyle: FontStyle
                                                              .italic))),
                                                  DataCell(
                                                    Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        if (rawStatus ==
                                                            'pending') ...[
                                                          ElevatedButton(
                                                            style:
                                                                ElevatedButton
                                                                    .styleFrom(
                                                              backgroundColor:
                                                                  Colors.green,
                                                              foregroundColor:
                                                                  Colors.white,
                                                              minimumSize:
                                                                  const Size(
                                                                60,
                                                                30,
                                                              ),
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 10,
                                                              ),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                  6,
                                                                ),
                                                              ),
                                                            ),
                                                            onPressed: () =>
                                                                _updateStatusCutiAdmin(
                                                              item['id'],
                                                              'approved',
                                                              item[
                                                                  'employee_id'],
                                                              item['user_id'],
                                                              item[
                                                                  'start_date'],
                                                              item['end_date'],
                                                            ),
                                                            child: const Text(
                                                              'Setujui',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 8),
                                                          OutlinedButton(
                                                            style:
                                                                OutlinedButton
                                                                    .styleFrom(
                                                              foregroundColor:
                                                                  Colors.red,
                                                              side:
                                                                  const BorderSide(
                                                                color:
                                                                    Colors.red,
                                                              ),
                                                              minimumSize:
                                                                  const Size(
                                                                50,
                                                                30,
                                                              ),
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 10,
                                                              ),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                  6,
                                                                ),
                                                              ),
                                                            ),
                                                            onPressed: () =>
                                                                _updateStatusCutiAdmin(
                                                              item['id'],
                                                              'rejected',
                                                              item[
                                                                  'employee_id'],
                                                              item['user_id'],
                                                              item[
                                                                  'start_date'],
                                                              item['end_date'],
                                                            ),
                                                            child: const Text(
                                                              'Tolak',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 8),
                                                        ],
                                                        IconButton(
                                                          icon: const Icon(
                                                            Icons.edit_note,
                                                            color: Colors.blue,
                                                            size: 20,
                                                          ),
                                                          tooltip:
                                                              'Ubah Status',
                                                          padding:
                                                              EdgeInsets.zero,
                                                          constraints:
                                                              const BoxConstraints(),
                                                          onPressed: () {
                                                            showDialog(
                                                              context: context,
                                                              barrierDismissible:
                                                                  false,
                                                              builder: (context) =>
                                                                  EditStatusCutiDialog(
                                                                cutiData: item,
                                                                onSuccess:
                                                                    _fetchCutiData,
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                        IconButton(
                                                          icon: const Icon(
                                                            Icons
                                                                .delete_outline,
                                                            color: Colors.red,
                                                            size: 20,
                                                          ),
                                                          tooltip: 'Hapus Data',
                                                          padding:
                                                              EdgeInsets.zero,
                                                          constraints:
                                                              const BoxConstraints(),
                                                          onPressed: () =>
                                                              _deleteCuti(item),
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
// DIALOG DETAIL & EDIT SALDO CUTI (LEAVE BALANCE)
// ============================================================================
class LeaveBalanceDetailDialog extends StatefulWidget {
  final dynamic empId;
  final dynamic userUuid;
  final String empName;
  final Map<String, dynamic>? initialBalance;
  final Map<String, dynamic> leaveRequestItem;
  final VoidCallback onSuccess;

  const LeaveBalanceDetailDialog({
    super.key,
    required this.empId,
    required this.userUuid,
    required this.empName,
    required this.initialBalance,
    required this.leaveRequestItem,
    required this.onSuccess,
  });

  @override
  State<LeaveBalanceDetailDialog> createState() =>
      _LeaveBalanceDetailDialogState();
}

class _LeaveBalanceDetailDialogState extends State<LeaveBalanceDetailDialog> {
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
      final total = int.tryParse(_totalCtrl.text) ?? 12;
      final used = int.tryParse(_usedCtrl.text) ?? 0;
      final remaining = int.tryParse(_remainingCtrl.text) ?? (total - used);
      final int? parsedEmpId =
          widget.empId != null ? int.tryParse(widget.empId.toString()) : null;

      final payload = {
        if (widget.userUuid != null) 'user_id': widget.userUuid,
        if (parsedEmpId != null) 'employee_id': parsedEmpId,
        'total_leave': total,
        'used_leave': used,
        'remaining_leave': remaining,
        'next_reset_date': _selectedResetDate != null
            ? DateFormat('yyyy-MM-dd').format(_selectedResetDate!)
            : null,
      };

      if (widget.initialBalance != null &&
          widget.initialBalance!['id'] != null) {
        await Supabase.instance.client
            .from('leave_balance')
            .update(payload)
            .eq('id', widget.initialBalance!['id']);
      } else {
        await Supabase.instance.client.from('leave_balance').insert(payload);
      }

      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saldo cuti berhasil diperbarui!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSuccess();
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
    final item = widget.leaveRequestItem;
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
              const SizedBox(height: 16),
              Text(
                'Detail Pengajuan Ini:',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '• Jenis: ${item['leave_type'] ?? 'Cuti'}\n• Tanggal: ${_formatTgl(item['start_date'])} s/d ${_formatTgl(item['end_date'])}\n• Alasan: ${item['reason'] ?? '-'}\n• Status: ${(item['status'] ?? 'pending').toString().toUpperCase()}\n• Disetujui Oleh: ${item['approver_name'] ?? '-'}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Colors.grey[700],
                  height: 1.4,
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

class EditStatusCutiDialog extends StatefulWidget {
  final Map<String, dynamic> cutiData;
  final VoidCallback onSuccess;
  const EditStatusCutiDialog({
    super.key,
    required this.cutiData,
    required this.onSuccess,
  });
  @override
  State<EditStatusCutiDialog> createState() => _EditStatusCutiDialogState();
}

class _EditStatusCutiDialogState extends State<EditStatusCutiDialog> {
  bool _isSaving = false;
  late String _selectedStatus;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.cutiData['status'] ?? 'pending';
  }

  Future<void> _updateStatus() async {
    setState(() => _isSaving = true);
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;

      // Ambil ID Integer dari Admin yang sedang login
      final adminData = await Supabase.instance.client
          .from('employees')
          .select('id')
          .eq('email', currentUser!.email!)
          .maybeSingle();

      final int? adminEmpId = adminData?['id'];

      // Gunakan ID Integer untuk update field approved_by
      await Supabase.instance.client.from('leave_requests').update({
        'status': _selectedStatus,
        if (_selectedStatus != 'pending') 'approved_by': adminEmpId,
      }).eq('id', widget.cutiData['id']);

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Status cuti diperbarui!',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String empName =
        widget.cutiData['employees']?['full_name'] ?? 'Karyawan';
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Proses Pengajuan Cuti',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Karyawan: $empName',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Colors.grey[700],
              ),
            ),
            const Divider(height: 24),
            DropdownButtonFormField<String>(
              value: _selectedStatus,
              items: [
                DropdownMenuItem(
                  value: 'pending',
                  child: Text(
                    'Pending (Menunggu)',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  ),
                ),
                DropdownMenuItem(
                  value: 'approved',
                  child: Text(
                    'Approved (Disetujui)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                DropdownMenuItem(
                  value: 'rejected',
                  child: Text(
                    'Rejected (Ditolak)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              onChanged: (val) => setState(() => _selectedStatus = val!),
              decoration: InputDecoration(
                labelText: 'Ubah Status',
                labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Batal',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isSaving ? null : _updateStatus,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
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
                          'Simpan Status',
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
}
