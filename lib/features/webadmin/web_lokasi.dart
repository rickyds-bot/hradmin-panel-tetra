import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class WebLokasiPage extends StatefulWidget {
  const WebLokasiPage({super.key});

  @override
  State<WebLokasiPage> createState() => _WebLokasiPageState();
}

class _WebLokasiPageState extends State<WebLokasiPage> {
  List<dynamic> _lokasiList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLokasi();
  }

  Future<void> _fetchLokasi() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('locations')
          .select()
          .order('created_at', ascending: false);

      setState(() {
        _lokasiList = data;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal mengambil data: $e',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteLokasi(Map<String, dynamic> lokasi) async {
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
          'Yakin ingin menghapus lokasi ${lokasi['name']}?',
          style: GoogleFonts.plusJakartaSans(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Batal',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
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
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client
            .from('locations')
            .delete()
            .eq('id', lokasi['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Lokasi berhasil dihapus',
                style: GoogleFonts.plusJakartaSans(fontSize: 13),
              ),
            ),
          );
          _fetchLokasi();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Gagal menghapus: $e',
                style: GoogleFonts.plusJakartaSans(fontSize: 13),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '-';
    return timeStr.substring(0, 5);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Data Lokasi',
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
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) =>
                        AddLokasiDialog(onSuccess: _fetchLokasi),
                  );
                },
                icon: const Icon(Icons.add_location_alt, size: 18),
                label: Text(
                  'Tambah Lokasi',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey[200]!),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _lokasiList.isEmpty
                      ? Center(
                          child: Text(
                            'Belum ada data lokasi.',
                            style: GoogleFonts.plusJakartaSans(fontSize: 13),
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              showCheckboxColumn: false,
                              headingRowColor: WidgetStateProperty.all(
                                Colors.grey[50],
                              ),
                              dataRowMaxHeight: 60,
                              headingTextStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              dataTextStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                              columns: const [
                                DataColumn(label: Text('No')),
                                DataColumn(label: Text('Nama Lokasi')),
                                DataColumn(label: Text('Tipe')),
                                DataColumn(label: Text('Alamat')),
                                DataColumn(label: Text('Jam Operasional')),
                                DataColumn(label: Text('Radius (m)')),
                                DataColumn(label: Text('Action')),
                              ],
                              rows: List<DataRow>.generate(_lokasiList.length, (
                                index,
                              ) {
                                final loc = _lokasiList[index];
                                return DataRow(
                                  cells: [
                                    DataCell(Text('${index + 1}')),
                                    DataCell(
                                      Text(
                                        loc['name'] ?? '-',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          loc['location_type'] ?? '-',
                                          style: const TextStyle(
                                            color: Colors.blue,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      SizedBox(
                                        width: 200,
                                        child: Text(
                                          loc['address'] ?? '-',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${_formatTime(loc['start_time'])} - ${_formatTime(loc['end_time'])} WIB',
                                      ),
                                    ),
                                    DataCell(
                                        Text('${loc['radius_meter'] ?? 0} m')),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              color: Colors.blue,
                                              size: 20,
                                            ),
                                            tooltip: 'Edit Lokasi',
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                barrierDismissible: false,
                                                builder: (context) =>
                                                    AddLokasiDialog(
                                                  lokasiData: loc,
                                                  onSuccess: _fetchLokasi,
                                                ),
                                              );
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.red,
                                              size: 20,
                                            ),
                                            tooltip: 'Hapus Lokasi',
                                            onPressed: () => _deleteLokasi(loc),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }),
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

class AddLokasiDialog extends StatefulWidget {
  final Map<String, dynamic>? lokasiData;
  final VoidCallback onSuccess;
  const AddLokasiDialog({super.key, this.lokasiData, required this.onSuccess});
  @override
  State<AddLokasiDialog> createState() => _AddLokasiDialogState();
}

class _AddLokasiDialogState extends State<AddLokasiDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _radiusCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;

  Timer? _debounce;
  GoogleMapController? _mapController;

  // Dihapus 'final' agar Set marker bisa dire-assign sepenuhnya (reaktif di Flutter)
  Set<Marker> _markers = {};

  String? _selectedType;
  final List<String> _typeList = ['Office', 'Proyek', 'Klien'];
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  late double _currentLat;
  late double _currentLng;

  // --- TAMBAHAN: State untuk Tipe Map (Normal / Satelit) ---
  MapType _currentMapType = MapType.normal;

  @override
  void initState() {
    super.initState();
    final data = widget.lokasiData;
    _nameCtrl = TextEditingController(text: data?['name'] ?? '');
    _addressCtrl = TextEditingController(text: data?['address'] ?? '');
    _radiusCtrl = TextEditingController(
      text: data?['radius_meter']?.toString() ?? '50',
    );

    _currentLat = data?['latitude'] != null
        ? double.parse(data!['latitude'].toString())
        : -6.200000;
    _currentLng = data?['longitude'] != null
        ? double.parse(data!['longitude'].toString())
        : 106.816666;

    _latCtrl = TextEditingController(text: _currentLat.toStringAsFixed(6));
    _lngCtrl = TextEditingController(text: _currentLng.toStringAsFixed(6));
    _selectedType = data?['location_type'];

    if (data != null && data['start_time'] != null) {
      final parts = data['start_time'].toString().split(':');
      if (parts.length >= 2) {
        _startTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
    } else {
      _startTime = const TimeOfDay(hour: 8, minute: 0);
    }

    if (data != null && data['end_time'] != null) {
      final parts = data['end_time'].toString().split(':');
      if (parts.length >= 2) {
        _endTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
    } else {
      _endTime = const TimeOfDay(hour: 17, minute: 0);
    }

    // Assign set marker pertama kali
    _markers = {
      Marker(
        markerId: const MarkerId('picked_location'),
        position: LatLng(_currentLat, _currentLng),
        draggable: true,
        onDragEnd: (newPosition) {
          _updatePosition(newPosition);
        },
      ),
    };
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _radiusCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // Fungsi diperbarui: me-reassign Set (tidak sekadar clear & add) agar State memicu perubahan pada UI GoogleMap
  void _updatePosition(LatLng position, {bool animateCamera = false}) {
    setState(() {
      _currentLat = position.latitude;
      _currentLng = position.longitude;
      _latCtrl.text = _currentLat.toStringAsFixed(6);
      _lngCtrl.text = _currentLng.toStringAsFixed(6);

      _markers = {
        Marker(
          markerId: const MarkerId('picked_location'),
          position: position,
          draggable: true,
          onDragEnd: (newPosition) {
            _updatePosition(newPosition);
          },
        ),
      };
    });

    if (animateCamera && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(position, 16));
    }
  }

  Future<void> _searchAddressOnMap(String address) async {
    if (address.isEmpty || address.length < 3) return;

    const String apiKey =
        'AIzaSyC0XAmTKERAE3TzPxYTCLPl4wfRYV6ZEP0'; // Disarankan menggunakan env/variabel aman
    final encodedAddress = Uri.encodeComponent(address);
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json?address=$encodedAddress&key=$apiKey',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          final location = data['results'][0]['geometry']['location'];
          double lat = location['lat'];
          double lng = location['lng'];

          LatLng newLatLng = LatLng(lat, lng);

          if (mounted) {
            _updatePosition(newLatLng, animateCamera: true);
          }
        } else {
          // Menampilkan pesan gagal dari API Google agar kita tahu masalah aslinya
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Lokasi tidak ditemukan (Status: ${data['status']})',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      // Mendeteksi dan menampilkan error CORS pada Web Browser
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal menghubungi Google Maps (Cek Koneksi atau Blokir CORS Web)',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      debugPrint('Error fetching geocode: $e');
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (_startTime ?? const TimeOfDay(hour: 8, minute: 0))
          : (_endTime ?? const TimeOfDay(hour: 17, minute: 0)),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Jam operasional wajib diisi!',
            style: GoogleFonts.plusJakartaSans(fontSize: 13),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      String startStr =
          '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}:00';
      String endStr =
          '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}:00';
      final payload = {
        'name': _nameCtrl.text,
        'location_type': _selectedType,
        'address': _addressCtrl.text,
        'latitude': double.parse(_latCtrl.text),
        'longitude': double.parse(_lngCtrl.text),
        'radius_meter': int.parse(_radiusCtrl.text),
        'start_time': startStr,
        'end_time': endStr,
      };

      if (widget.lokasiData == null) {
        await Supabase.instance.client.from('locations').insert(payload);
      } else {
        await Supabase.instance.client
            .from('locations')
            .update(payload)
            .eq('id', widget.lokasiData!['id']);
      }
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.lokasiData == null
                  ? 'Lokasi berhasil ditambahkan!'
                  : 'Lokasi berhasil diperbarui!',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
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
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEdit = widget.lokasiData != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 950),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isEdit ? Colors.blue[50] : Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isEdit ? Icons.edit_location : Icons.add_location,
                    color: isEdit ? Colors.blue : Colors.green,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  isEdit ? 'Edit Lokasi Absensi' : 'Tambah Lokasi Absensi Baru',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(),
            ),
            Flexible(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: SingleChildScrollView(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildTextField(
                              _nameCtrl,
                              'Nama Lokasi (ex: Kantor Pusat)',
                              isRequired: true,
                            ),
                            _buildDropdown(
                              'Tipe Lokasi',
                              _typeList,
                              _selectedType,
                              (val) => setState(() => _selectedType = val),
                            ),
                            _buildTextField(
                              _addressCtrl,
                              'Alamat Lengkap (Ketik untuk cari di Peta)',
                              maxLines: 2,
                              isRequired: true,
                              onChanged: (val) {
                                if (_debounce?.isActive ?? false) {
                                  _debounce!.cancel();
                                }
                                _debounce = Timer(
                                  const Duration(milliseconds: 1200),
                                  () {
                                    if (val.trim().length >= 3) {
                                      _searchAddressOnMap(val);
                                    }
                                  },
                                );
                              },
                              suffixIcon: IconButton(
                                icon: const Icon(
                                  Icons.search,
                                  color: Colors.blue,
                                  size: 18,
                                ),
                                onPressed: () =>
                                    _searchAddressOnMap(_addressCtrl.text),
                              ),
                            ),
                            _buildTextField(
                              _radiusCtrl,
                              'Radius Absen Toleransi (Meter)',
                              isNumber: true,
                              isRequired: true,
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _buildTimePicker(
                                      label: 'Jam Masuk',
                                      time: _startTime,
                                      onTap: () => _pickTime(isStart: true),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildTimePicker(
                                      label: 'Jam Pulang',
                                      time: _endTime,
                                      onTap: () => _pickTime(isStart: false),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    _latCtrl,
                                    'Latitude',
                                    isReadOnly: true,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildTextField(
                                    _lngCtrl,
                                    'Longitude',
                                    isReadOnly: true,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 1,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Tentukan Titik Koordinat',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ketik alamat di kiri atau klik/geser pada peta.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // --- TAMBAHAN: Stack digunakan untuk meletakkan tombol ganti mode map di atas GoogleMap ---
                          Container(
                            height: 380,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                children: [
                                  GoogleMap(
                                    // SET MAP TYPE DI SINI
                                    mapType: _currentMapType,
                                    initialCameraPosition: CameraPosition(
                                      target: LatLng(_currentLat, _currentLng),
                                      zoom: 16,
                                    ),
                                    markers: _markers,
                                    onMapCreated: (controller) {
                                      _mapController = controller;
                                      Future.delayed(
                                        const Duration(milliseconds: 500),
                                        () {
                                          if (mounted &&
                                              _mapController != null) {
                                            _mapController!.animateCamera(
                                              CameraUpdate.newLatLngZoom(
                                                LatLng(
                                                    _currentLat, _currentLng),
                                                16,
                                              ),
                                            );
                                          }
                                        },
                                      );
                                    },
                                    onTap: (LatLng position) {
                                      _updatePosition(position);
                                    },
                                  ),
                                  // TOMBOL TOGGLE VIEW
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: Card(
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: IconButton(
                                        tooltip:
                                            _currentMapType == MapType.normal
                                                ? 'Beralih ke Satelit'
                                                : 'Beralih ke Peta Normal',
                                        icon: Icon(
                                          _currentMapType == MapType.normal
                                              ? Icons.satellite_alt
                                              : Icons.map_outlined,
                                          color: Colors.blue[800],
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _currentMapType = _currentMapType ==
                                                    MapType.normal
                                                ? MapType.satellite
                                                : MapType.normal;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Batal',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveData,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          isEdit
                              ? 'Perbarui Data Lokasi'
                              : 'Simpan Data Lokasi',
                          style: GoogleFonts.plusJakartaSans(fontSize: 13),
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
    bool isNumber = false,
    int maxLines = 1,
    bool isReadOnly = false,
    Widget? suffixIcon,
    ValueChanged<String>? onSubmitted,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        readOnly: isReadOnly,
        maxLines: maxLines,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        onFieldSubmitted: onSubmitted,
        onChanged: onChanged,
        style: GoogleFonts.plusJakartaSans(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.plusJakartaSans(
            color: Colors.black54,
            fontSize: 13,
          ),
          filled: true,
          fillColor: isReadOnly ? Colors.grey[200] : Colors.grey[50],
          suffixIcon: suffixIcon,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: val,
        items: items
            .map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(
                  e,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
        style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.black87),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.plusJakartaSans(
            color: Colors.black54,
            fontSize: 13,
          ),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
        ),
        validator: (val) => val == null ? 'Wajib dipilih' : null,
      ),
    );
  }

  Widget _buildTimePicker({
    required String label,
    required TimeOfDay? time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.plusJakartaSans(
            color: Colors.black54,
            fontSize: 13,
          ),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              time == null
                  ? '--:--'
                  : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: time == null ? Colors.black38 : Colors.black87,
              ),
            ),
            const Icon(Icons.access_time, size: 16, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}
