import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class WebAbsensiPage extends StatefulWidget {
  const WebAbsensiPage({super.key});

  @override
  State<WebAbsensiPage> createState() => _WebAbsensiPageState();
}

class _WebAbsensiPageState extends State<WebAbsensiPage> {
  List<dynamic> _absensiList = [];
  List<dynamic> _filteredList = [];
  bool _isLoading = true;

  // Map untuk menyimpan data cuti/izin karyawan yang di-approve
  final Map<int, List<Map<String, DateTime>>> _approvedLeaves = {};

  // Map untuk menyimpan data hari libur nasional
  final Map<String, String> _holidaysMap = {};

  final TextEditingController _searchNameCtrl = TextEditingController();
  DateTime? _selectedDateFilter;

  int _rowsPerPage = 50;
  final List<int> _pageOptions = [50, 100, 200];

  // Scroll controllers
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchAbsensiData();
  }

  @override
  void dispose() {
    _searchNameCtrl.dispose();
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  Future<void> _fetchAbsensiData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Ambil data absen
      final absensiResponse = await Supabase.instance.client
          .from('attendance')
          .select()
          .order('created_at', ascending: false);

      // 2. Ambil data karyawan
      final employeesResponse = await Supabase.instance.client
          .from('employees')
          .select('id, full_name');

      final Map<dynamic, String> employeeMap = {};
      for (var emp in employeesResponse) {
        employeeMap[emp['id']] = emp['full_name'] ?? '-';
      }

      // 3. Ambil data cuti/izin (hanya yang berstatus approved)
      final leaveResponse = await Supabase.instance.client
          .from('leave_requests')
          .select('employee_id, start_date, end_date')
          .eq('status', 'approved');

      _approvedLeaves.clear();
      for (var l in leaveResponse) {
        int? eId = int.tryParse(l['employee_id']?.toString() ?? '');
        if (eId != null && l['start_date'] != null && l['end_date'] != null) {
          try {
            DateTime s = DateTime.parse(l['start_date']);
            DateTime e = DateTime.parse(l['end_date']);
            _approvedLeaves
                .putIfAbsent(eId, () => [])
                .add({'start': s, 'end': e});
          } catch (_) {}
        }
      }

      // 3.5 Ambil data hari libur nasional dari Supabase
      final holidaysResponse = await Supabase.instance.client
          .from('hari_libur')
          .select('holiday_date, description');

      _holidaysMap.clear();
      for (var h in holidaysResponse) {
        if (h['holiday_date'] != null) {
          _holidaysMap[h['holiday_date'].toString()] =
              h['description'] ?? 'Libur Nasional';
        }
      }

      // 4. Merge data
      final List<dynamic> mergedData = absensiResponse.map((item) {
        final empId = item['employee_id'];
        return {
          ...item,
          'employees': {
            'full_name': employeeMap[empId] ?? 'Karyawan Tidak Ditemukan',
          },
        };
      }).toList();

      _absensiList = mergedData;
      _applyLocalFilter();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal mengambil data absensi: $e',
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
    List<dynamic> temp = List.from(_absensiList);

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

  Future<void> _deleteAbsensi(Map<String, dynamic> item) async {
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
          'Yakin ingin menghapus data absensi $empName ini?',
          style: GoogleFonts.plusJakartaSans(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client
            .from('attendance')
            .delete()
            .eq('id', item['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Data absensi berhasil dihapus'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchAbsensiData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menghapus: $e'),
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
      return DateFormat('dd-MM-yyyy HH:mm:ss').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  Color _getStatusColor(String? status) {
    if (status == null) return Colors.grey;
    final s = status.toLowerCase();
    if (s.contains('out') || s.contains('pulang') || s.contains('keluar')) {
      return Colors.red;
    } else if (s.contains('in') || s.contains('masuk') || s.contains('hadir')) {
      return Colors.green;
    }
    return Colors.orange;
  }

  void _showMapPopup(dynamic lat, dynamic lng, String empName) {
    final double parsedLat =
        lat != null ? double.parse(lat.toString()) : -6.200000;
    final double parsedLng =
        lng != null ? double.parse(lng.toString()) : 106.816666;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Lokasi Absen: $empName',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[100]!),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.blueAccent,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Latitude : $parsedLat',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Longitude: $parsedLng',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Peta Lokasi Absen:',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 300,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(parsedLat, parsedLng),
                      zoom: 16,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('attendance_location'),
                        position: LatLng(parsedLat, parsedLng),
                        infoWindow: InfoWindow(
                          title: empName,
                          snippet: 'Lat: $parsedLat, Lng: $parsedLng',
                        ),
                      ),
                    },
                    zoomControlsEnabled: true,
                    myLocationButtonEnabled: false,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[800],
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showImageDialog(String imageUrl, String empName) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 450, maxHeight: 550),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Foto Absen: $empName',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) =>
                        const Text('Gagal memuat gambar.'),
                  ),
                ),
              ),
            ],
          ),
        ),
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
                'Data Absensi Karyawan',
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
                onPressed: _fetchAbsensiData,
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
                          child: Text(
                            'Data absensi tidak ditemukan.',
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
                                                label: Text('Waktu Absen')),
                                            DataColumn(
                                                label: Text('Nama Karyawan')),
                                            DataColumn(label: Text('Status')),
                                            DataColumn(
                                                label: Text('Bukti Foto')),
                                            DataColumn(label: Text('Lokasi')),
                                            DataColumn(
                                                label: Text('Aktifitas')),
                                            DataColumn(label: Text('Notes')),
                                            DataColumn(label: Text('Action')),
                                          ],
                                          rows: List<DataRow>.generate(
                                            _filteredList.length > _rowsPerPage
                                                ? _rowsPerPage
                                                : _filteredList.length,
                                            (index) {
                                              final item = _filteredList[index];

                                              final int? empId = int.tryParse(
                                                  item['employee_id']
                                                          ?.toString() ??
                                                      '');
                                              final String empName =
                                                  item['employees']
                                                          ?['full_name'] ??
                                                      'ID: $empId';
                                              final String rawStatus =
                                                  (item['status'] ?? 'Hadir')
                                                      .toString();
                                              final statusColor =
                                                  _getStatusColor(rawStatus);

                                              final lat = item['latitude'];
                                              final lng = item['longitude'];

                                              DateTime? attDate;
                                              if (item['created_at'] != null) {
                                                attDate = DateTime.tryParse(
                                                        item['created_at'])
                                                    ?.toLocal();
                                              }

                                              String aktifitas = 'Bekerja';
                                              String notes =
                                                  (item['notes'] ?? '')
                                                      .toString();

                                              if (attDate != null) {
                                                bool isLeave = false;

                                                if (empId != null &&
                                                    _approvedLeaves
                                                        .containsKey(empId)) {
                                                  DateTime dateOnly = DateTime(
                                                      attDate.year,
                                                      attDate.month,
                                                      attDate.day);
                                                  for (var range
                                                      in _approvedLeaves[
                                                          empId]!) {
                                                    DateTime s = DateTime(
                                                        range['start']!.year,
                                                        range['start']!.month,
                                                        range['start']!.day);
                                                    DateTime e = DateTime(
                                                        range['end']!.year,
                                                        range['end']!.month,
                                                        range['end']!.day);

                                                    if ((dateOnly
                                                                .isAtSameMomentAs(
                                                                    s) ||
                                                            dateOnly
                                                                .isAfter(s)) &&
                                                        (dateOnly
                                                                .isAtSameMomentAs(
                                                                    e) ||
                                                            dateOnly
                                                                .isBefore(e))) {
                                                      isLeave = true;
                                                      break;
                                                    }
                                                  }
                                                }

                                                // --- Cek Hari Libur ---
                                                String dateKey =
                                                    DateFormat('yyyy-MM-dd')
                                                        .format(attDate);
                                                bool isPublicHoliday =
                                                    _holidaysMap
                                                        .containsKey(dateKey);
                                                String publicHolidayName =
                                                    isPublicHoliday
                                                        ? _holidaysMap[dateKey]!
                                                        : '-';

                                                if (isLeave) {
                                                  notes = 'Cuti/Izin';
                                                } else if (isPublicHoliday) {
                                                  notes =
                                                      'Masuk di Hari Libur ($publicHolidayName)';
                                                } else {
                                                  bool isCheckIn = rawStatus
                                                          .toLowerCase()
                                                          .contains('in') ||
                                                      rawStatus
                                                          .toLowerCase()
                                                          .contains('masuk');

                                                  if (isCheckIn) {
                                                    if (attDate.hour > 8 ||
                                                        (attDate.hour == 8 &&
                                                            attDate.minute >
                                                                45)) {
                                                      notes = 'Terlambat';
                                                    }
                                                  }
                                                }

                                                bool hasCheckIn = false;
                                                bool hasCheckOut = false;
                                                DateTime dateOnly = DateTime(
                                                    attDate.year,
                                                    attDate.month,
                                                    attDate.day);
                                                for (var a in _absensiList) {
                                                  if (a['employee_id'] ==
                                                          empId &&
                                                      a['created_at'] != null) {
                                                    DateTime d = DateTime.parse(
                                                            a['created_at'])
                                                        .toLocal();
                                                    if (d.year ==
                                                            dateOnly.year &&
                                                        d.month ==
                                                            dateOnly.month &&
                                                        d.day == dateOnly.day) {
                                                      String st =
                                                          (a['status'] ?? '')
                                                              .toString()
                                                              .toLowerCase();
                                                      if (st.contains('in') ||
                                                          st.contains('masuk'))
                                                        hasCheckIn = true;
                                                      if (st.contains('out') ||
                                                          st.contains('pulang'))
                                                        hasCheckOut = true;
                                                    }
                                                  }
                                                }

                                                if (hasCheckIn && hasCheckOut) {
                                                  aktifitas = 'Bekerja';
                                                } else if (hasCheckIn &&
                                                    !hasCheckOut) {
                                                  aktifitas = 'Belum Checkout';
                                                } else {
                                                  aktifitas = 'Hanya Checkout';
                                                }
                                              }

                                              if (notes.isEmpty ||
                                                  notes == 'null') notes = '-';

                                              Color noteColor = Colors.black87;
                                              if (notes.toLowerCase() ==
                                                  'terlambat') {
                                                noteColor = Colors.red;
                                              } else if (notes.toLowerCase() ==
                                                  'cuti/izin') {
                                                noteColor = Colors.green;
                                              } else if (notes
                                                  .toLowerCase()
                                                  .contains('hari libur')) {
                                                noteColor = Colors.orange[800]!;
                                              }

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
                                                                .circular(4),
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
                                                    item['photo_url'] != null &&
                                                            item['photo_url']
                                                                .toString()
                                                                .isNotEmpty
                                                        ? ElevatedButton.icon(
                                                            icon: const Icon(
                                                              Icons.image,
                                                              size: 12,
                                                            ),
                                                            label: const Text(
                                                              'Foto',
                                                              style: TextStyle(
                                                                  fontSize: 11),
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
                                                            ),
                                                            onPressed: () =>
                                                                _showImageDialog(
                                                              item['photo_url'],
                                                              empName,
                                                            ),
                                                          )
                                                        : const Text('-'),
                                                  ),
                                                  DataCell(
                                                    (lat != null && lng != null)
                                                        ? IconButton(
                                                            icon: const Icon(
                                                              Icons
                                                                  .map_outlined,
                                                              color: Colors
                                                                  .blueAccent,
                                                              size: 20,
                                                            ),
                                                            tooltip:
                                                                'Lihat Peta Lokasi',
                                                            padding:
                                                                EdgeInsets.zero,
                                                            constraints:
                                                                const BoxConstraints(),
                                                            onPressed: () =>
                                                                _showMapPopup(
                                                              lat,
                                                              lng,
                                                              empName,
                                                            ),
                                                          )
                                                        : const Text('-'),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      aktifitas,
                                                      style: TextStyle(
                                                        color: aktifitas ==
                                                                'Bekerja'
                                                            ? Colors.green[700]
                                                            : Colors
                                                                .orange[800],
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      notes,
                                                      style: TextStyle(
                                                        color: noteColor,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.delete_outline,
                                                        color: Colors.red,
                                                        size: 18,
                                                      ),
                                                      onPressed: () =>
                                                          _deleteAbsensi(item),
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
