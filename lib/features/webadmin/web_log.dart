import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class WebLogPage extends StatefulWidget {
  const WebLogPage({super.key});

  @override
  State<WebLogPage> createState() => _WebLogPageState();
}

class _WebLogPageState extends State<WebLogPage> {
  List<dynamic> _logList = [];
  List<dynamic> _filteredList = [];
  bool _isLoading = true;

  final TextEditingController _searchNameCtrl = TextEditingController();
  DateTime? _selectedDateFilter;

  int _rowsPerPage = 50;
  final List<int> _pageOptions = [50, 100, 200];

  @override
  void initState() {
    super.initState();
    _fetchLogData();
  }

  @override
  void dispose() {
    _searchNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchLogData() async {
    setState(() => _isLoading = true);
    try {
      // Ambil data log aktivitas dari tabel (ganti 'activity_logs' sesuai nama tabel log di database Anda jika berbeda)
      final logResponse = await Supabase.instance.client
          .from('activity_logs')
          .select()
          .order('created_at', ascending: false);

      // Ambil data karyawan untuk mapping nama
      final employeesResponse = await Supabase.instance.client
          .from('employees')
          .select('id, full_name');

      final Map<dynamic, String> employeeMap = {};
      for (var emp in employeesResponse) {
        employeeMap[emp['id']] = emp['full_name'] ?? '-';
      }

      // Gabungkan data log dengan nama karyawan secara aman
      final List<dynamic> mergedData = logResponse.map((item) {
        final empId = item['employee_id'];
        return {
          ...item,
          'employees': {
            'full_name':
                employeeMap[empId] ?? 'Sistem / Karyawan Tidak Ditemukan',
          },
        };
      }).toList();

      _logList = mergedData;
      _applyLocalFilter();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal mengambil data log: $e',
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
    List<dynamic> temp = List.from(_logList);

    // Filter berdasarkan nama karyawan
    if (_searchNameCtrl.text.trim().isNotEmpty) {
      final search = _searchNameCtrl.text.trim().toLowerCase();
      temp = temp.where((item) {
        final empName = (item['employees']?['full_name'] ?? '')
            .toString()
            .toLowerCase();
        final activityText = (item['activity'] ?? item['description'] ?? '')
            .toString()
            .toLowerCase();
        return empName.contains(search) || activityText.contains(search);
      }).toList();
    }

    // Filter berdasarkan tanggal log
    if (_selectedDateFilter != null) {
      temp = temp.where((item) {
        if (item['created_at'] == null) return false;
        try {
          DateTime itemDate = DateTime.parse(item['created_at']).toLocal();
          return itemDate.year == _selectedDateFilter!.year &&
              itemDate.month == _selectedDateFilter!.month &&
              itemDate.day == _selectedDateFilter!.day;
        } catch (_) {
          return false;
        }
      }).toList();
    }

    setState(() {
      _filteredList = temp;
    });
  }

  Future<void> _pickFilterDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateFilter ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
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

  String _formatTanggalWaktu(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd-MM-yyyy, HH:mm:ss', 'id_ID').format(dt);
    } catch (_) {
      return dateStr;
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
                'Log Aktivitas Karyawan',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
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
                onPressed: _fetchLogData,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(
                  'Refresh Data',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Baris Filter & Search Sejajar Tinggi 42
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
                      hintText: 'Cari nama karyawan atau aktivitas...',
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
                          if (newValue != null)
                            setState(() => _rowsPerPage = newValue);
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
                            Icons.receipt_long,
                            size: 42,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Belum ada data log aktivitas.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          showCheckboxColumn: false,
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
                            DataColumn(label: Text('Waktu Aktivitas')),
                            DataColumn(label: Text('Nama Karyawan')),
                            DataColumn(label: Text('Aktivitas / Keterangan')),
                            DataColumn(label: Text('Modul / Menu')),
                          ],
                          rows: List<DataRow>.generate(
                            _filteredList.length > _rowsPerPage
                                ? _rowsPerPage
                                : _filteredList.length,
                            (index) {
                              final item = _filteredList[index];
                              final String empName =
                                  item['employees']?['full_name'] ?? 'Sistem';

                              return DataRow(
                                cells: [
                                  DataCell(Text('${index + 1}')),
                                  DataCell(
                                    Text(
                                      _formatTanggalWaktu(item['created_at']),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      empName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      item['activity'] ??
                                          item['description'] ??
                                          '-',
                                    ),
                                  ),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        item['module'] ??
                                            item['action_type'] ??
                                            'Umum',
                                        style: const TextStyle(
                                          color: Colors.blue,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
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
        ],
      ),
    );
  }
}
