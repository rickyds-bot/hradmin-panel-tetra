import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class WebLemburPage extends StatefulWidget {
  const WebLemburPage({super.key});

  @override
  State<WebLemburPage> createState() => _WebLemburPageState();
}

class _WebLemburPageState extends State<WebLemburPage> {
  List<dynamic> _lemburList = [];
  List<dynamic> _filteredList = [];
  bool _isLoading = true;

  final TextEditingController _searchNameCtrl = TextEditingController();
  DateTime? _selectedDateFilter;

  int _rowsPerPage = 50;
  final List<int> _pageOptions = [50, 100, 200];

  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchLemburData();
  }

  @override
  void dispose() {
    _searchNameCtrl.dispose();
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  Future<void> _fetchLemburData() async {
    setState(() => _isLoading = true);
    try {
      final lemburResponse = await Supabase.instance.client
          .from('overtime_requests')
          .select()
          .order('created_at', ascending: false);

      final employeesResponse = await Supabase.instance.client
          .from('employees')
          .select('id, full_name');

      final Map<int, String> employeeMap = {};
      for (var emp in employeesResponse) {
        if (emp['id'] != null) {
          int? parsedId = int.tryParse(emp['id'].toString());
          if (parsedId != null) {
            employeeMap[parsedId] = emp['full_name'] ?? '-';
          }
        }
      }

      final List<dynamic> mergedData = lemburResponse.map((item) {
        var mutableItem = Map<String, dynamic>.from(item);

        int? empId = int.tryParse(mutableItem['employee_id']?.toString() ?? '');
        int? approverId =
            int.tryParse(mutableItem['approved_by']?.toString() ?? '');

        mutableItem['employees'] = {
          'full_name': employeeMap[empId] ?? 'Karyawan Tidak Ditemukan',
        };
        mutableItem['approver_name'] = employeeMap[approverId] ?? '-';

        return mutableItem;
      }).toList();

      _lemburList = mergedData;
      _applyLocalFilter();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal mengambil data lembur: $e',
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
    List<dynamic> temp = List.from(_lemburList);

    if (_searchNameCtrl.text.trim().isNotEmpty) {
      final search = _searchNameCtrl.text.trim().toLowerCase();
      temp = temp.where((item) {
        final empName =
            (item['employees']?['full_name'] ?? '').toString().toLowerCase();
        return empName.contains(search);
      }).toList();
    }

    if (_selectedDateFilter != null) {
      final filterDateStr =
          DateFormat('yyyy-MM-dd').format(_selectedDateFilter!);
      temp = temp.where((item) {
        if (item['start_time'] == null) return false;
        try {
          final dt = DateTime.parse(item['start_time']).toLocal();
          final itemDateStr = DateFormat('yyyy-MM-dd').format(dt);
          return itemDateStr == filterDateStr;
        } catch (_) {
          return false;
        }
      }).toList();
    }

    setState(() {
      _filteredList = temp;
    });
  }

  Future<void> _deleteLembur(Map<String, dynamic> item) async {
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
          'Yakin ingin menghapus data lembur $empName?',
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
            .from('overtime_requests')
            .delete()
            .eq('id', item['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Data lembur dihapus',
                style: GoogleFonts.plusJakartaSans(fontSize: 12),
              ),
            ),
          );
          _fetchLemburData();
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
      lastDate: DateTime.now().add(const Duration(days: 30)),
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
    });
    _applyLocalFilter();
  }

  String _formatJamOnly(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      if (dateStr.contains('T')) {
        final timePart = dateStr.split('T')[1];
        final parts = timePart.split(':');
        if (parts.length >= 2) {
          return '${parts[0]}:${parts[1]}';
        }
      }
      final parsed = DateTime.parse(dateStr);
      return DateFormat('HH:mm').format(parsed);
    } catch (_) {
      return '-';
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
                'Data Pengajuan Lembur',
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
                onPressed: _fetchLemburData,
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
                          ? 'Pilih Tanggal'
                          : DateFormat('dd-MM-yyyy')
                              .format(_selectedDateFilter!),
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
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.more_time,
                                size: 42,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Data lembur tidak ditemukan.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
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
                                          dataRowMaxHeight: 48,
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
                                            DataColumn(
                                                label: Text('Waktu Lembur')),
                                            DataColumn(label: Text('Durasi')),
                                            DataColumn(
                                                label:
                                                    Text('Pekerjaan / Alasan')),
                                            DataColumn(label: Text('Status')),
                                            DataColumn(
                                                label: Text('Approved By')),
                                            DataColumn(
                                                // Kolom Baru: Catatan HR
                                                label: Text('Notes')),
                                            DataColumn(label: Text('Action')),
                                          ],
                                          rows: List<DataRow>.generate(
                                            _filteredList.length > _rowsPerPage
                                                ? _rowsPerPage
                                                : _filteredList.length,
                                            (index) {
                                              final item = _filteredList[index];
                                              final String empName = item[
                                                              'employees'] !=
                                                          null &&
                                                      item['employees']
                                                              ['full_name'] !=
                                                          null
                                                  ? item['employees']
                                                      ['full_name']
                                                  : 'ID: ${item['employee_id']}';

                                              final String rawStatus =
                                                  (item['status'] ?? 'pending')
                                                      .toString();
                                              final statusColor =
                                                  _getStatusColor(rawStatus);

                                              final String tglMulai = item[
                                                          'start_time'] !=
                                                      null
                                                  ? () {
                                                      try {
                                                        final datePart =
                                                            item['start_time']
                                                                .toString()
                                                                .split('T')[0];
                                                        final parts =
                                                            datePart.split('-');
                                                        if (parts.length == 3) {
                                                          return '${parts[2]}-${parts[1]}-${parts[0]}';
                                                        }
                                                        return DateFormat(
                                                          'dd-MM-yyyy',
                                                        ).format(
                                                          DateTime.parse(
                                                            item['start_time'],
                                                          ).toLocal(),
                                                        );
                                                      } catch (_) {
                                                        return '-';
                                                      }
                                                    }()
                                                  : '-';
                                              final String jamMulai =
                                                  _formatJamOnly(
                                                item['start_time'],
                                              );
                                              final String jamSelesai =
                                                  _formatJamOnly(
                                                item['end_time'],
                                              );

                                              return DataRow(
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
                                                    Text(
                                                      '$tglMulai\n$jamMulai - $jamSelesai WIB',
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      '${item['duration_hours'] ?? 0} Jam',
                                                    ),
                                                  ),
                                                  DataCell(
                                                    SizedBox(
                                                      width: 180,
                                                      child: Text(
                                                        item['reason'] ?? '-',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        maxLines: 2,
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
                                                  DataCell(
                                                    Text(
                                                      item['approver_name'] ??
                                                          '-',
                                                      style: TextStyle(
                                                        color: Colors.grey[700],
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    // Cell Baru: Tampilan Catatan HR
                                                    SizedBox(
                                                      width: 150,
                                                      child: Text(
                                                        item['notes'] != null &&
                                                                item['notes']
                                                                    .toString()
                                                                    .trim()
                                                                    .isNotEmpty
                                                            ? item['notes']
                                                            : '-',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        maxLines: 2,
                                                        style: TextStyle(
                                                          color:
                                                              Colors.grey[700],
                                                          fontStyle: item['notes'] !=
                                                                      null &&
                                                                  item['notes']
                                                                      .toString()
                                                                      .trim()
                                                                      .isNotEmpty
                                                              ? FontStyle.normal
                                                              : FontStyle
                                                                  .italic,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        IconButton(
                                                          icon: const Icon(
                                                            Icons.edit_note,
                                                            color: Colors.blue,
                                                            size: 18,
                                                          ),
                                                          tooltip:
                                                              'Ubah Status & Catatan',
                                                          onPressed: () {
                                                            showDialog(
                                                              context: context,
                                                              barrierDismissible:
                                                                  false,
                                                              builder: (context) =>
                                                                  EditStatusLemburDialog(
                                                                lemburData:
                                                                    item,
                                                                onSuccess:
                                                                    _fetchLemburData,
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                        IconButton(
                                                          icon: const Icon(
                                                            Icons
                                                                .delete_outline,
                                                            color: Colors.red,
                                                            size: 18,
                                                          ),
                                                          tooltip: 'Hapus Data',
                                                          onPressed: () =>
                                                              _deleteLembur(
                                                                  item),
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

class EditStatusLemburDialog extends StatefulWidget {
  final Map<String, dynamic> lemburData;
  final VoidCallback onSuccess;
  const EditStatusLemburDialog({
    super.key,
    required this.lemburData,
    required this.onSuccess,
  });
  @override
  State<EditStatusLemburDialog> createState() => _EditStatusLemburDialogState();
}

class _EditStatusLemburDialogState extends State<EditStatusLemburDialog> {
  bool _isSaving = false;
  late String _selectedStatus;
  final _notesCtrl = TextEditingController();

  late DateTime _startTime;
  late DateTime _endTime;
  late double _durationHours;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.lemburData['status'] ?? 'pending';
    _notesCtrl.text = widget.lemburData['notes'] ?? '';

    // Inisialisasi waktu dari database
    _startTime =
        DateTime.tryParse(widget.lemburData['start_time'] ?? '')?.toLocal() ??
            DateTime.now();
    _endTime =
        DateTime.tryParse(widget.lemburData['end_time'] ?? '')?.toLocal() ??
            DateTime.now();
    _recalculateDuration();
  }

  void _recalculateDuration() {
    final diffInMinutes = _endTime.difference(_startTime).inMinutes;
    _durationHours = diffInMinutes > 0
        ? double.parse((diffInMinutes / 60.0).toStringAsFixed(1))
        : 0.0;
  }

  Future<void> _selectDateTime(bool isStart) async {
    final initialDt = isStart ? _startTime : _endTime;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDt),
    );
    if (pickedTime == null) return;

    setState(() {
      final newDt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      if (isStart) {
        _startTime = newDt;
      } else {
        _endTime = newDt;
      }
      _recalculateDuration();
    });
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateStatus() async {
    if (_endTime.isBefore(_startTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Waktu selesai tidak boleh lebih awal dari waktu mulai',
            style: GoogleFonts.plusJakartaSans(fontSize: 12),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) throw 'Sesi admin tidak ditemukan';

      final adminData = await Supabase.instance.client
          .from('employees')
          .select('id')
          .eq('email', currentUser.email!)
          .maybeSingle();

      final int? adminEmpId = adminData?['id'];

      await Supabase.instance.client.from('overtime_requests').update({
        'status': _selectedStatus,
        'notes': _notesCtrl.text,
        'start_time': _startTime.toIso8601String(),
        'end_time': _endTime.toIso8601String(),
        'duration_hours': _durationHours,
        if (_selectedStatus != 'pending') 'approved_by': adminEmpId,
      }).eq('id', widget.lemburData['id']);

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Data lembur berhasil diperbarui!',
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
        widget.lemburData['employees']?['full_name'] ?? 'Karyawan';
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit & Proses Lembur',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Karyawan: $empName',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Colors.grey[700],
              ),
            ),
            const Divider(height: 20),

            // Form Edit Jam Mulai & Selesai
            Text(
              'Penyesuaian Waktu Lembur:',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDateTime(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.grey[50],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Mulai',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10, color: Colors.grey[600])),
                          const SizedBox(height: 2),
                          Text(dateFormat.format(_startTime),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDateTime(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.grey[50],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Selesai',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10, color: Colors.grey[600])),
                          const SizedBox(height: 2),
                          Text(dateFormat.format(_endTime),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Kalkulasi Durasi:',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: Colors.blue[900]),
                  ),
                  Text(
                    '$_durationHours Jam',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[900]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Form Status Approval
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
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
              decoration: InputDecoration(
                labelText: 'Notes HR / Admin (Opsional)',
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
}
