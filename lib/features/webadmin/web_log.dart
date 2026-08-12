import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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

  // Scroll controllers untuk tabel
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();

  RealtimeChannel? _logSubscription;

  @override
  void initState() {
    super.initState();
    _fetchLogData();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _searchNameCtrl.dispose();
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    if (_logSubscription != null) {
      Supabase.instance.client.removeChannel(_logSubscription!);
    }
    super.dispose();
  }

  // --- SETUP REALTIME STREAM ---
  void _setupRealtimeSubscription() {
    _logSubscription = Supabase.instance.client
        .channel('public:activity_logs')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'activity_logs',
          callback: (payload) {
            // Ketika ada data log baru masuk, refresh data secara otomatis
            _fetchLogData();
          },
        )
        .subscribe();
  }

  Future<void> _fetchLogData() async {
    try {
      // Ambil data log aktivitas terbaru
      final logResponse = await Supabase.instance.client
          .from('activity_logs')
          .select()
          .order('created_at', ascending: false);

      // Ambil data karyawan untuk mapping nama (id bertipe int / int8)
      final employeesResponse = await Supabase.instance.client
          .from('employees')
          .select('id, full_name');

      // Buat Map dengan key tipe integer untuk mencocokkan id int8 employees
      final Map<int, String> employeeMap = {};
      for (var emp in employeesResponse) {
        int? empId = int.tryParse(emp['id'].toString());
        if (empId != null) {
          employeeMap[empId] = emp['full_name'] ?? '-';
        }
      }

      // Gabungkan data log dengan nama karyawan secara aman
      final List<dynamic> mergedData = logResponse.map((item) {
        int? empId = int.tryParse(item['employee_id']?.toString() ?? '');
        return {
          ...item,
          'employees': {
            'full_name': (empId != null && employeeMap.containsKey(empId))
                ? employeeMap[empId]
                : 'Sistem / Karyawan Tidak Ditemukan',
          },
        };
      }).toList();

      if (mounted) {
        setState(() {
          _logList = mergedData;
          _isLoading = false;
        });
        _applyLocalFilter();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
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
    }
  }

  void _applyLocalFilter() {
    List<dynamic> temp = List.from(_logList);

    // Filter berdasarkan nama karyawan atau aktivitas
    if (_searchNameCtrl.text.trim().isNotEmpty) {
      final search = _searchNameCtrl.text.trim().toLowerCase();
      temp = temp.where((item) {
        final empName =
            (item['employees']?['full_name'] ?? '').toString().toLowerCase();
        final activityText = (item['activity'] ?? item['description'] ?? '')
            .toString()
            .toLowerCase();
        final moduleText = (item['module'] ?? '').toString().toLowerCase();
        return empName.contains(search) ||
            activityText.contains(search) ||
            moduleText.contains(search);
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

      // Hapus 'id_ID' agar tidak memicu error inisialisasi intl
      return DateFormat('dd-MM-yyyy: HH:mm:ss').format(dt);
    } catch (e) {
      // Tambahkan print log ini agar jika masih gagal, kita bisa tahu penyebab di console
      debugPrint("Gagal format tanggal: $e");
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
              Row(
                children: [
                  Text(
                    'Log Aktifitas Karyawan',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Indikator Realtime Aktif
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle, size: 8, color: Colors.green),
                        const SizedBox(width: 5),
                        Text(
                          'Realtime Live',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                      hintText: 'Cari nama karyawan, modul, atau aktivitas...',
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
                                            DataColumn(
                                                label: Text('Waktu Aktifitas')),
                                            DataColumn(
                                                label: Text('Nama Karyawan')),
                                            DataColumn(
                                                label: Text(
                                                    'Aktifitas / Keterangan')),
                                            DataColumn(
                                                label: Text('Modul / Menu')),
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
                                                      'Sistem';

                                              return DataRow(
                                                cells: [
                                                  DataCell(
                                                      Text('${index + 1}')),
                                                  DataCell(
                                                    Text(
                                                      _formatTanggalWaktu(
                                                          item['created_at']),
                                                    ),
                                                  ),
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
                                                      item['activity'] ??
                                                          item['description'] ??
                                                          '-',
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
                                                        color: Colors.blue
                                                            .withOpacity(0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: Text(
                                                        item['module'] ??
                                                            item[
                                                                'action_type'] ??
                                                            'Umum',
                                                        style: const TextStyle(
                                                          color: Colors.blue,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
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
