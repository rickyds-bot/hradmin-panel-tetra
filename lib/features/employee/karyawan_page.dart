import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:camera/camera.dart';
import 'kamera_absen_page.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'notification_services.dart';
import 'register_face_page.dart';

// ============================================================================
// --- 1. CLASS UTAMA (KARYAWAN PAGE) ---
// ============================================================================
class KaryawanPage extends StatefulWidget {
  @override
  _KaryawanPageState createState() => _KaryawanPageState();
}

class _KaryawanPageState extends State<KaryawanPage> {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  int _currentMenuIndex = 0;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('id_ID', null);
    _initProcess();
  }

  Future<void> _initProcess() async {
    // 1. Ambil Data Karyawan Dulu
    await _fetchUserData();

    // 2. Setup Semua Notifikasi (Aman & Tidak Bikin Crash)
    if (userData != null && userData!['id'] != null) {
      try {
        final notifService = NotificationService();
        await notifService.initialize();
        await notifService.setupAbsensiNotifications();
        await notifService.setupFCMToken(userData!['id']);
      } catch (e) {
        debugPrint("Peringatan: Gagal setup Notifikasi: $e");
      }
    }

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _fetchUserData() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    try {
      final data = await Supabase.instance.client
          .from('employees')
          .select('*')
          .eq('email', currentUser.email!)
          .single();

      final dept = await Supabase.instance.client
          .from('departments')
          .select('name')
          .eq('id', data['department_id'])
          .maybeSingle();

      final pos = await Supabase.instance.client
          .from('positions')
          .select('name')
          .eq('id', data['position_id'])
          .maybeSingle();

      final loc = await Supabase.instance.client
          .from('locations')
          .select('name')
          .eq('id', data['location_id'])
          .maybeSingle();

      data['dept_name'] = dept?['name'] ?? '-';
      data['pos_name'] = pos?['name'] ?? '-';
      data['loc_name'] = loc?['name'] ?? '-';

      setState(() {
        userData = data;
      });
    } catch (e) {
      debugPrint("Error fetching data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (userData == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 80, color: Colors.red),
                const SizedBox(height: 20),
                const Text(
                  "Gagal Memuat Profil Karyawan",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Akun Anda belum terdaftar di data karyawan atau telah dihapus.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text("Logout / Reset Sesi"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    if (!mounted) return;
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ===================================================================
    // --- LOGIKA ROLE BARU MENGGUNAKAN TEKS ---
    // ===================================================================
    final String userRole =
        (userData!['pos_name'] ?? '').toString().toLowerCase();
    final bool isApprover = (userRole.contains('supervisor') ||
        userRole.contains('manager') ||
        userRole.contains('admin'));

    final List<Widget> activePages = [];
    final List<BottomNavigationBarItem> activeNavItems = [];
    final List<String> activeTitles = [];

    // --- TAB 1: BERANDA ---
    activePages.add(AbsensiKaryawanTab(userData: userData!));
    activeNavItems.add(
      const BottomNavigationBarItem(
        icon: Icon(Icons.dashboard_rounded),
        label: "Beranda",
      ),
    );
    activeTitles.add("HRIS Tetra");

    // --- TAB 2: CUTI/IZIN ---
    activePages.add(CutiKaryawanTab(userData: userData!));
    activeNavItems.add(
      const BottomNavigationBarItem(
        icon: Icon(Icons.calendar_month_rounded),
        label: "Cuti/Izin",
      ),
    );
    activeTitles.add("Pengajuan Cuti/Izin");

    // --- TAB 3: DINAMIS (APPROVAL ATAU LEMBUR) ---
    if (isApprover) {
      activePages.add(
        ManagerApprovalTab(
          managerId: userData!['id'],
          departmentId: userData!['department_id'],
        ),
      );
      activeNavItems.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.fact_check_rounded),
          label: "Approval",
        ),
      );
      activeTitles.add("Approval");
    } else {
      activePages.add(LemburKaryawanTab(userData: userData!));
      activeNavItems.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.more_time_rounded),
          label: "Lembur",
        ),
      );
      activeTitles.add("Pengajuan Lembur");
    }

    // --- TAB 4: PROFIL ---
    activePages.add(
      ProfilKaryawanTab(
        userData: userData!,
        onProfileUpdated: () => _fetchUserData(),
      ),
    );
    activeNavItems.add(
      const BottomNavigationBarItem(
        icon: Icon(Icons.person_rounded),
        label: "Profile",
      ),
    );
    activeTitles.add("Profil Karyawan");

    int safeIndex = _currentMenuIndex;
    if (safeIndex >= activePages.length) {
      safeIndex =
          activePages.length - 1; // Mencegah crash jika jumlah tab berubah
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      // --- UBAH BAGIAN APPBAR INI ---
      appBar: safeIndex == 0
          ? null
          : AppBar(
              title: Text(
                activeTitles[safeIndex],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  fontSize: 16,
                ),
              ),
              elevation: 0,
              backgroundColor: Colors.blue.shade900,
              foregroundColor: Colors.white,
            ),
      // ------------------------------
      body: activePages[safeIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: safeIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue.shade900,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        onTap: (index) => setState(() => _currentMenuIndex = index),
        items: activeNavItems,
      ),
    );
  }
}

// ============================================================================
// --- 2. TAB BERANDA / ABSENSI ---
// ============================================================================
class AbsensiKaryawanTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  AbsensiKaryawanTab({required this.userData});

  @override
  _AbsensiKaryawanTabState createState() => _AbsensiKaryawanTabState();
}

class _AbsensiKaryawanTabState extends State<AbsensiKaryawanTab> {
  String? userUuid;
  int get userId => widget.userData['id'] ?? 0;
  bool _isLoading = false;
  String _timeString = "";
  late Timer _timer;

  GoogleMapController? _mapController;
  Position? _currentPosition;
  Set<Marker> _markers = {};
  bool _isLoadingMap = true;

  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    String _dapatkanSapaan() {
      final int jam = DateTime.now().hour;
      if (jam >= 4 && jam < 11) {
        return "Selamat Pagi,"; // 04:00 - 10:59
      } else if (jam >= 11 && jam < 15) {
        return "Selamat Siang,"; // 11:00 - 14:59
      } else if (jam >= 15 && jam < 18) {
        return "Selamat Sore,"; // 15:00 - 17:59
      } else {
        return "Selamat Malam,"; // 18:00 - 03:59
      }
    }

    super.initState();
    userUuid = Supabase.instance.client.auth.currentUser?.id;
    _timeString = DateFormat('HH:mm:ss').format(DateTime.now());
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer t) => _updateTime(),
    );
    _getCurrentLocation();
    _checkNewAnnouncements();
    //_showAnnouncements();
    _refreshHistory();
  }

  void _refreshHistory() {
    _historyFuture = Supabase.instance.client
        .from('attendance')
        .select()
        .eq('employee_id', userId)
        .order('created_at', ascending: false)
        .limit(20);

    // Perbarui UI secara aman
    if (mounted) setState(() {});
  }

  void _updateTime() {
    if (mounted)
      setState(
        () => _timeString = DateFormat('HH:mm:ss').format(DateTime.now()),
      );
  }

  Future<void> _checkNewAnnouncements() async {
    try {
      final data = await Supabase.instance.client
          .from('announcements')
          .select('id')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1);

      if (mounted && data.isNotEmpty) {
        int latestId = data[0]['id']; // ID pengumuman terbaru dari database

        SharedPreferences prefs = await SharedPreferences.getInstance();
        int? lastSeenId = prefs.getInt('last_seen_announcement_id');

        if (lastSeenId != latestId) {
          setState(() {
            _hasNewInfo = true;
          });
        } else {
          setState(() {
            _hasNewInfo = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Gagal cek pengumuman: $e");
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'GPS tidak aktif.';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _markers.add(
            Marker(
              markerId: const MarkerId('me'),
              position: LatLng(position.latitude, position.longitude),
            ),
          );
          _isLoadingMap = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMap = false);
    }
  }

  Future<void> _absen(BuildContext context, String tipe) async {
    setState(() => _isLoading = true);
    try {
      // 1. Cek Permission Kamera & Lokasi
      var cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted)
        throw 'Izin kamera diperlukan untuk absensi.';

      // 2. Ambil Lokasi
      Position currentPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // --- AMBIL DATA KARYAWAN TERBARU (Termasuk Wajah) ---
      final empData = await Supabase.instance.client
          .from('employees')
          .select('location_id, face_embedding, is_face_registered')
          .eq('id', userId)
          .single();

      final locId = empData['location_id'];
      if (locId == null) throw 'Lokasi kerja belum diatur.';

      // --- VALIDASI WAJAH SUDAH DAFTAR ATAU BELUM ---
      if (empData['is_face_registered'] != true ||
          empData['face_embedding'] == null) {
        throw 'Anda belum mendaftarkan wajah. Silakan ke menu Profil untuk mendaftar.';
      }

      // Parse data vektor wajah dari database (JSON string ke List<double>)
      List<double> registeredFace;
      try {
        final decoded = jsonDecode(empData['face_embedding'].toString());
        registeredFace = List<double>.from(decoded);
      } catch (e) {
        throw 'Data wajah korup. Silakan update data wajah di menu Profil.';
      }
      // ---------------------------------------------------

      final locData = await Supabase.instance.client
          .from('locations')
          .select('*')
          .eq('id', locId)
          .single();

      double distance = Geolocator.distanceBetween(
        currentPos.latitude,
        currentPos.longitude,
        double.parse(locData['latitude'].toString()),
        double.parse(locData['longitude'].toString()),
      );

      if (distance > (locData['radius_meter'] ?? 50)) {
        throw 'Anda di luar radius (${distance.toStringAsFixed(0)}m).';
      }

      // 3. Buka Kamera Depan
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // Buka Halaman Auto-Capture & Face Verification
      final String? photoPath = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => KameraAbsenPage(
            camera: frontCamera,
            registeredEmbedding: registeredFace,
          ),
        ),
      );

      // Jika user membatalkan (menekan tombol silang / kembali)
      if (photoPath == null) return;

      // 4. Upload Foto Bukti & Insert Absen ke Database
      final file = File(photoPath);
      final bytes = await file.readAsBytes();
      final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final compressedFile = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 800,
        minHeight: 800,
        quality: 40,
      );

      if (compressedFile != null) {
        await Supabase.instance.client.storage
            .from('attendance_photos')
            .uploadBinary(fileName, compressedFile);

        final photoUrl = Supabase.instance.client.storage
            .from('attendance_photos')
            .getPublicUrl(fileName);

        await Supabase.instance.client.from('attendance').insert({
          'employee_id': userId,
          'status': tipe,
          'photo_url': photoUrl,
          'latitude': currentPos.latitude,
          'longitude': currentPos.longitude,
        });

        await file.delete(); // Hapus file lokal
        _refreshHistory();

        try {
          if (tipe == 'check-in')
            await NotificationService().onCheckIn();
          else if (tipe == 'check-out')
            await NotificationService().onCheckOut();
        } catch (e) {
          debugPrint("Info: Gagal menjalankan notifikasi lokal: $e");
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Berhasil absen dengan verifikasi wajah!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildQuickMetrics(),
        _buildMapSection(),
        _buildActionButtons(),
        _buildHistoryList(),
      ],
    );
  }

  String _dapatkanSapaan() {
    final int jam = DateTime.now().hour;
    if (jam >= 4 && jam < 11) {
      return "Selamat Pagi,";
    } else if (jam >= 11 && jam < 15) {
      return "Selamat Siang,";
    } else if (jam >= 15 && jam < 18) {
      return "Selamat Sore,";
    } else {
      return "Selamat Malam,";
    }
  }

  // --- POSISI BUILD HEADER  ---

  bool _hasNewInfo = false;

  Widget _buildHeader() => Container(
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.of(context).padding.top + 15,
          20,
          25,
        ),
        decoration: BoxDecoration(
          color: Colors.blue.shade900,
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(30)),
        ),
        child: Row(
          children: [
            // 1. Foto Profil
            CircleAvatar(
              key: ValueKey(widget.userData['photo_url']),
              radius: 32,
              backgroundColor: Colors.white24,
              backgroundImage: widget.userData['photo_url'] != null
                  ? NetworkImage(widget.userData['photo_url'])
                  : null,
              child: widget.userData['photo_url'] == null
                  ? const Icon(Icons.person, size: 32, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 15),

            // 2. Kolom Sapaan & Nama
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dapatkanSapaan(),
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.userData['full_name'] ?? 'User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ],
            ),

            // 3. Ikon Lonceng (Diletakkan di sini agar sejajar di kanan)
            const Spacer(), // Mendorong ikon ke paling kanan
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.notifications_none_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: () async {
                    // <--- KATA 'async' DITAMBAHKAN DI SINI
                    setState(() => _hasNewInfo = false);

                    // --- SIMPAN STATUS BACA KE MEMORI HP ---
                    try {
                      final data = await Supabase.instance.client
                          .from('announcements')
                          .select('id')
                          .eq('is_active', true)
                          .order('created_at', ascending: false)
                          .limit(1);

                      if (data.isNotEmpty) {
                        SharedPreferences prefs =
                            await SharedPreferences.getInstance();
                        await prefs.setInt(
                          'last_seen_announcement_id',
                          data[0]['id'],
                        );
                      }
                    } catch (e) {
                      debugPrint("Gagal simpan status baca: $e");
                    }
                    // ---------------------------------------

                    if (!mounted) return;

                    // Animasi Pindah Halaman Geser dari Kanan
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            const PengumumanPage(),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                          const begin = Offset(
                            1.0,
                            0.0,
                          ); // 1.0 berarti bergeser dari kanan
                          const end = Offset.zero;
                          const curve = Curves.easeInOut;
                          var tween = Tween(
                            begin: begin,
                            end: end,
                          ).chain(CurveTween(curve: curve));
                          return SlideTransition(
                            position: animation.drive(tween),
                            child: child,
                          );
                        },
                      ),
                    ).then((_) {
                      // Refresh cek titik merah saat user kembali dari halaman pengumuman
                      _checkNewAnnouncements();
                    });
                  },
                ),
                if (_hasNewInfo)
                  Positioned(
                    right: 10,
                    top: 10,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.blue.shade900, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );

  Widget _buildQuickMetrics() => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _metricCard("Status", "Aktif", Icons.verified, Colors.green),
            const SizedBox(width: 10),
            _metricCard(
                "Waktu", _timeString, Icons.timer, Colors.blue.shade900),
          ],
        ),
      );

  Widget _metricCard(String t, String v, IconData i, Color c) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Icon(i, color: c),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t, style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text(v, style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildMapSection() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          height: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: _isLoadingMap
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(
                        _currentPosition?.latitude ?? -6.2,
                        _currentPosition?.longitude ?? 106.8,
                      ),
                      zoom: 16,
                    ),
                    markers: _markers,
                  ),
          ),
        ),
      );

  Widget _buildActionButtons() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // --- Instruksi Manual ---
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                "*Check-In/Check-Out hanya dapat dilakukan di lokasi kerja yang telah ditentukan & wajib daftar pengenalan wajah.",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black,
                  //fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _absen(context, 'check-in'),
                          icon: const Icon(Icons.login),
                          label: const Text("Check-In"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _absen(context, 'check-out'),
                          icon: const Icon(Icons.logout),
                          label: const Text("Check-Out"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      );

  Widget _buildHistoryList() {
    if (userUuid == null)
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    return Expanded(
      // 5. Diubah ke FutureBuilder agar diam tidak berkedip
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());

          if (snapshot.hasError)
            return Center(child: Text("Error: ${snapshot.error}"));

          if (!snapshot.hasData || snapshot.data!.isEmpty)
            return const Center(child: Text("Belum ada riwayat absensi"));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, i) {
              final row = snapshot.data![i];
              final localTime = DateTime.parse(row['created_at']).toLocal();
              final formattedTime = DateFormat(
                'EEEE, dd MMM yyyy, HH:mm',
                'id_ID',
              ).format(localTime);
              final isCheckIn =
                  row['status'].toString().toLowerCase() == 'check-in';

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        row['status'].toString().toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isCheckIn
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                      Text(
                        formattedTime,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                    ],
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

// ============================================================================
// --- TAB PENGAJUAN CUTI / IZIN KARYAWAN ---
// ============================================================================
class CutiKaryawanTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  const CutiKaryawanTab({Key? key, required this.userData}) : super(key: key);

  @override
  _CutiKaryawanTabState createState() => _CutiKaryawanTabState();
}

class _CutiKaryawanTabState extends State<CutiKaryawanTab> {
  final GlobalKey<_RiwayatCutiListState> _riwayatKey = GlobalKey();
  final _reasonCtrl = TextEditingController();
  bool _isSubmitting = false;
  int _remainingLeave = 0;
  DateTimeRange? _dateRange;
  DateTime? _nextResetDate;

  String _mode = 'Cuti'; // 'Cuti' atau 'Izin'
  String? _selectedLeaveType;
  XFile? _lampiran;

  @override
  void initState() {
    super.initState();
    _fetchRemainingLeave();
  }

  Future<void> _fetchRemainingLeave() async {
    try {
      // --- WAJIB TAMBAHKAN 2 BARIS INI AGAR userUuid DIKENALI ---
      final userUuid = Supabase.instance.client.auth.currentUser?.id;
      if (userUuid == null) return;
      // ---------------------------------------------------------
      // 1. Ambil data lengkap (select '*') agar kolom next_reset_date ikut terbaca
      final data = await Supabase.instance.client
          .from('leave_balance')
          .select('*')
          .eq('user_id', userUuid)
          .maybeSingle();

      if (mounted && data != null) {
        final now = DateTime.now();
        final today = DateTime(
          now.year,
          now.month,
          now.day,
        ); // Menghilangkan data jam/menit agar akurat

        // 2. Cek apakah Admin sudah menentukan tanggal reset di Web Dashboard
        if (data['next_reset_date'] != null) {
          final DateTime nextReset = DateTime.parse(
            data['next_reset_date'].toString(),
          );

          // 3. Eksekusi OTOMATIS jika hari ini sudah masuk atau melewati tanggal reset dari Admin
          if (today.isAfter(nextReset) || today.isAtSameMomentAs(nextReset)) {
            // Hitung tanggal reset berikutnya untuk tahun depan (+1 tahun dari tanggal acuan saat ini)
            final DateTime newResetDate = DateTime(
              nextReset.year + 1,
              nextReset.month,
              nextReset.day,
            );

            // Update database Supabase secara otomatis
            await Supabase.instance.client.from('leave_balance').update({
              'total_leave': 12,
              'used_leave': 0,
              'remaining_leave': 12,
              'next_reset_date': DateFormat(
                'yyyy-MM-dd',
              ).format(newResetDate),
            }).eq('user_id', userUuid);

            // Perbarui UI ke angka jatah penuh
            setState(() {
              _remainingLeave = 12;
              _nextResetDate = newResetDate;
            });
            return;
          }
        }

        // 4. Jika belum waktunya reset, tampilkan saldo aktual sesuai sisa terakhir
        setState(() {
          _remainingLeave = data['remaining_leave'] ?? 0;
          if (data['next_reset_date'] != null) {
            _nextResetDate = DateTime.tryParse(
              data['next_reset_date'].toString(),
            );
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading leave balance: $e");
    }
  }

  Future<void> _pickLampiran() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    setState(() => _lampiran = file);
  }

  Future<void> _ajukanCuti(BuildContext context) async {
    final userUuid = Supabase.instance.client.auth.currentUser?.id;
    if (userUuid == null) return;
    if (_selectedLeaveType == null ||
        _dateRange == null ||
        _reasonCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mohon lengkapi semua data!")),
      );
      return;
    }

    // 1. Validasi Wajib Lampiran Surat Dokter
    if (_selectedLeaveType == 'Izin Sakit' && _lampiran == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Surat Dokter wajib dilampirkan untuk Izin Sakit!"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 2. Validasi Batas Minimal 7 Hari (HANYA UNTUK CUTI)
    if (_mode == 'Cuti') {
      DateTime now = DateTime.now();
      DateTime today = DateTime(now.year, now.month, now.day);
      DateTime startDate = DateTime(
        _dateRange!.start.year,
        _dateRange!.start.month,
        _dateRange!.start.day,
      );

      if (startDate.difference(today).inDays < 7) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Pengajuan cuti tahunan wajib minimal 7 hari sebelumnya!",
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final int duration =
        _dateRange!.end.difference(_dateRange!.start).inDays + 1;

    // 3. Validasi Saldo (HANYA jika memilih Cuti Tahunan)
    if (_selectedLeaveType == 'Cuti Tahunan' && duration > _remainingLeave) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Durasi cuti melebihi sisa saldo cuti tahunan!"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      String? attachmentUrl;

      // Upload lampiran jika ada
      if (_lampiran != null) {
        final bytes = await _lampiran!.readAsBytes();
        final fileExt = _lampiran!.name.split('.').last;
        final fileName =
            '${widget.userData['id']}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

        final compressedBytes = await FlutterImageCompress.compressWithFile(
          _lampiran!.path,
          minWidth: 800, // Lebar standar yang masih jelas terbaca
          minHeight: 800,
          quality: 50, // Kualitas diturunkan ke 50% untuk menghemat ukuran
        );

        if (compressedBytes != null) {
          // Upload menggunakan file yang sudah dikompres (compressedBytes)
          await Supabase.instance.client.storage
              .from('medical_document')
              .uploadBinary(fileName, compressedBytes);

          attachmentUrl = Supabase.instance.client.storage
              .from('medical_document')
              .getPublicUrl(fileName);
        }
        // --- AKHIR PENAMBAHAN KOMPRESI ---

        await Supabase.instance.client.storage
            .from('medical_document')
            .uploadBinary(fileName, bytes);

        attachmentUrl = Supabase.instance.client.storage
            .from('medical_document')
            .getPublicUrl(fileName);
      }

      await Supabase.instance.client.from('leave_requests').insert({
        'user_id':
            Supabase.instance.client.auth.currentUser!.id, // WAJIB TETAP UUID
        'employee_id': widget.userData['id'], // KITA TAMBAHKAN INI (ID Angka)
        'leave_type': _selectedLeaveType,
        'start_date': DateFormat('yyyy-MM-dd').format(_dateRange!.start),
        'end_date': DateFormat('yyyy-MM-dd').format(_dateRange!.end),
        'reason': _reasonCtrl.text,
        'attachment_url': attachmentUrl,
        'status': 'pending',
      });
      _riwayatKey.currentState?._loadData();

      _reasonCtrl.clear();
      setState(() {
        _dateRange = null;
        _lampiran = null;
        _selectedLeaveType = null;
      });
      _fetchRemainingLeave(); // Refresh saldo

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Pengajuan berhasil dikirim!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> opsiCuti = [
      'Cuti Tahunan',
      'Cuti Melahirkan',
      'Cuti Menikah',
      'Cuti Khusus',
    ];
    final List<String> opsiIzin = ['Izin Pribadi', 'Izin Sakit', 'Dinas Luar'];

    final List<String> currentOptions = _mode == 'Cuti' ? opsiCuti : opsiIzin;

    return Column(
      children: [
        // --- 1. INFO SISA CUTI ---
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            color: Colors.teal.shade50,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.teal.shade200),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.teal),
                  title: const Text("Jumlah Cuti Tahunan"),
                  trailing: Text(
                    "$_remainingLeave Hari",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.teal,
                    ),
                  ),
                ),
                // --- BARIS INFORMASI RESET ---
                if (_nextResetDate != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      "Sisa cuti akan reset pada: ${DateFormat('dd MMMM yyyy', 'id_ID').format(_nextResetDate!)}",
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.teal,
                        //fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center, // Posisi tengah
                    ),
                  ),
              ],
            ),
          ),
        ),

        // --- 2. FORM PENGAJUAN ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Form Pengajuan",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 10),

                  // Radio Mode
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            "Cuti",
                            style: TextStyle(fontSize: 14),
                          ),
                          value: "Cuti",
                          groupValue: _mode,
                          onChanged: (val) {
                            setState(() {
                              _mode = val!;
                              _selectedLeaveType = null;
                              _lampiran = null;
                              _dateRange =
                                  null; // Reset tanggal jika mode berubah
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            "Izin/Sakit",
                            style: TextStyle(fontSize: 14),
                          ),
                          value: "Izin",
                          groupValue: _mode,
                          onChanged: (val) {
                            setState(() {
                              _mode = val!;
                              _selectedLeaveType = null;
                              _dateRange =
                                  null; // Reset tanggal jika mode berubah
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),

                  // Dropdown Kategori
                  DropdownButtonFormField<String>(
                    value: _selectedLeaveType,
                    decoration: InputDecoration(
                      labelText:
                          _mode == 'Cuti' ? "Jenis Cuti" : "Kategori Izin",
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    items: currentOptions
                        .map(
                          (type) =>
                              DropdownMenuItem(value: type, child: Text(type)),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedLeaveType = val),
                  ),
                  const SizedBox(height: 15),

                  // Tombol Upload Lampiran
                  if (_selectedLeaveType == 'Izin Sakit') ...[
                    OutlinedButton.icon(
                      onPressed: _pickLampiran,
                      icon: Icon(
                        _lampiran == null
                            ? Icons.upload_file
                            : Icons.check_circle,
                        color: _lampiran == null ? Colors.blue : Colors.green,
                      ),
                      label: Text(
                        _lampiran == null
                            ? "Unggah Surat Dokter (Wajib)"
                            : "Surat Dokter Dilampirkan",
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 45),
                        side: BorderSide(
                          color: _lampiran == null ? Colors.blue : Colors.green,
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                  ],

                  // Tombol Tanggal (Dengan Batasan UX)
                  ElevatedButton.icon(
                    onPressed: () async {
                      // Jika Cuti: minimal H+7. Jika Izin: bisa mundur s/d 14 hari yang lalu
                      DateTime firstAllowedDate = _mode == 'Cuti'
                          ? DateTime.now().add(const Duration(days: 7))
                          : DateTime.now().subtract(const Duration(days: 14));

                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: firstAllowedDate,
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _dateRange = picked);
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _dateRange == null
                          ? "Pilih Rentang Tanggal"
                          : "${DateFormat('yyyy MMM dd', 'id_ID').format(_dateRange!.start)} - ${DateFormat('yyyy MMM dd', 'id_ID').format(_dateRange!.end)}",
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 45),
                    ),
                  ),

                  if (_mode == 'Cuti') // Pesan bantuan kecil
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Center(
                        child: Text(
                          "*Pengajuan cuti tahunan minimal 7 hari sebelumnya",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red,
                            //fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 15),

                  // Keterangan / Alasan
                  TextField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: "Keterangan/Alasan",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 15),

                  // Tombol Kirim
                  SizedBox(
                    width: double.infinity,
                    child: _isSubmitting
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => _ajukanCuti(context),
                            child: const Text(
                              "Kirim Pengajuan",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // --- 3. LIST RIWAYAT ---
        Expanded(
          // <--- BUNGKUS KEMBALI DENGAN EXPANDED
          child: RiwayatCutiList(
            userId: Supabase.instance.client.auth.currentUser!.id,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// --- KOMPONEN RIWAYAT CUTI (Dibatasi 10 Data Terakhir) ---
// ============================================================================
class RiwayatCutiList extends StatefulWidget {
  final String userId;
  const RiwayatCutiList({Key? key, required this.userId}) : super(key: key);

  @override
  _RiwayatCutiListState createState() => _RiwayatCutiListState();
}

class _RiwayatCutiListState extends State<RiwayatCutiList> {
  List<Map<String, dynamic>> _riwayatList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('leave_requests')
          .select('*')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false)
          .limit(10);

      if (mounted) {
        setState(() {
          _riwayatList = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_riwayatList.isEmpty)
      return const Center(child: Text("Belum ada riwayat cuti"));

    return ListView.builder(
      // SCROLL DIAKTIFKAN KEMBALI: shrinkWrap dan physics dihapus!
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _riwayatList.length,
      itemBuilder: (context, index) {
        final row = _riwayatList[index];
        final status = (row['status'] ?? 'PENDING').toString().toUpperCase();

        Color statusColor = Colors.orange;
        if (status == 'APPROVED' || status == 'DISETUJUI')
          statusColor = Colors.green;
        if (status == 'REJECTED' || status == 'DITOLAK')
          statusColor = Colors.red;

        return Card(
          margin: const EdgeInsets.only(bottom: 9),
          child: ListTile(
            dense: true,
            title: Text(
              row['leave_type']?.toString() ?? 'Cuti',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  "${_formatTanggalCantik(row['start_date'])} s/d ${_formatTanggalCantik(row['end_date'])}",
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                // INFO ALASAN DIPASTIKAN MUNCUL
                Text(
                  "Alasan: ${row['reason'] ?? '-'}",
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 9,
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// --- TAB PENGAJUAN LEMBUR KARYAWAN ---
// ============================================================================
class LemburKaryawanTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  const LemburKaryawanTab({Key? key, required this.userData}) : super(key: key);

  @override
  _LemburKaryawanTabState createState() => _LemburKaryawanTabState();
}

class _LemburKaryawanTabState extends State<LemburKaryawanTab> {
  final _reasonCtrl = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isSubmitting = false;

  Key _riwayatKey = UniqueKey();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 14)),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
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

  Future<void> _ajukanLembur(BuildContext context) async {
    if (_selectedDate == null ||
        _startTime == null ||
        _endTime == null ||
        _reasonCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mohon lengkapi semua data lembur!")),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // 1. Gabungkan Tanggal dan Jam menjadi DateTime utuh
      DateTime startDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _startTime!.hour,
        _startTime!.minute,
      );

      DateTime endDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _endTime!.hour,
        _endTime!.minute,
      );

      // 2. Logika Lembur Lintas Hari (Misal: 22:00 s/d 02:00)
      if (endDateTime.isBefore(startDateTime)) {
        endDateTime = endDateTime.add(const Duration(days: 1));
      }

      // 3. Hitung Durasi (dalam format desimal/jam)
      int durationInMinutes = endDateTime.difference(startDateTime).inMinutes;
      double durationInHours = durationInMinutes / 60.0;

      // 4. Insert ke tabel overtime_request yang sesuai dengan skema Anda
      await Supabase.instance.client.from('overtime_requests').insert({
        'user_id': Supabase.instance.client.auth.currentUser!.id,
        'employee_id': widget.userData['id'], // TAMBAHKAN INI JUGA
        'start_time': startDateTime.toIso8601String(), // Format timestamptz
        'end_time': endDateTime.toIso8601String(), // Format timestamptz
        'duration_hours': durationInHours,
        'reason': _reasonCtrl.text,
        'status': 'pending',
        'notes': null, // Opsional, dikosongkan saat pengajuan
      });

      _reasonCtrl.clear();
      setState(() {
        _selectedDate = null;
        _startTime = null;
        _endTime = null;
        _riwayatKey = UniqueKey();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Pengajuan Lembur berhasil dikirim!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- FORM PENGAJUAN LEMBUR ---
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Form Pengajuan Lembur",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _selectedDate == null
                          ? "Pilih Tanggal Mulai Lembur"
                          : DateFormat(
                              'dd MMMM yyyy',
                              'id_ID',
                            ).format(_selectedDate!),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 45),
                      backgroundColor: Colors.blue.shade50,
                      foregroundColor: Colors.blue.shade900,
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _pickTime(isStart: true),
                          icon: const Icon(Icons.access_time, size: 18),
                          label: Text(
                            _startTime == null
                                ? "Jam Mulai"
                                : "${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}",
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade50,
                            foregroundColor: Colors.blue.shade900,
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _pickTime(isStart: false),
                          icon: const Icon(Icons.access_time_filled, size: 18),
                          label: Text(
                            _endTime == null
                                ? "Jam Selesai"
                                : "${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}",
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade50,
                            foregroundColor: Colors.orange.shade900,
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: "Detail Pekerjaan Lembur",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: _isSubmitting
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => _ajukanLembur(context),
                            child: const Text(
                              "Kirim Pengajuan Lembur",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // --- RIWAYAT LEMBUR ---
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Align(
            alignment: Alignment.centerLeft,
            // child: Text(
            //   "Riwayat Lembur Anda",
            //   style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            // ),
          ),
        ),
        const SizedBox(height: 5),
        Expanded(
          child: RiwayatLemburList(
            userId: Supabase.instance.client.auth.currentUser!.id,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// --- KOMPONEN RIWAYAT LEMBUR (FIX SCROLL + DURASI JAM) ---
// ============================================================================
class RiwayatLemburList extends StatefulWidget {
  final String userId;
  const RiwayatLemburList({Key? key, required this.userId}) : super(key: key);

  @override
  _RiwayatLemburListState createState() => _RiwayatLemburListState();
}

class _RiwayatLemburListState extends State<RiwayatLemburList> {
  List<Map<String, dynamic>> _riwayatList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('overtime_requests')
          .select('*')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false)
          .limit(10);

      if (mounted) {
        setState(() {
          _riwayatList = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_riwayatList.isEmpty)
      return const Center(child: Text("Belum ada riwayat lembur"));

    return ListView.builder(
      // SCROLL DIAKTIFKAN KEMBALI
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _riwayatList.length,
      itemBuilder: (context, index) {
        final row = _riwayatList[index];
        final status = (row['status'] ?? 'PENDING').toString().toUpperCase();

        Color statusColor = Colors.orange;
        if (status == 'APPROVED' || status == 'DISETUJUI')
          statusColor = Colors.green;
        if (status == 'REJECTED' || status == 'DITOLAK')
          statusColor = Colors.red;

        String jamMulai = _formatJam(row['start_time']?.toString());
        String jamSelesai = _formatJam(row['end_time']?.toString());
        String durasi = _hitungDurasi(
          row['start_time']?.toString(),
          row['end_time']?.toString(),
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 9),
          child: ListTile(
            dense: true,
            title: const Text(
              "Lembur",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  "${_formatTanggalCantik(row['overtime_date'] ?? row['start_time'])} \n$jamMulai - $jamSelesai WIB $durasi",
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Pekerjaan: ${row['reason'] ?? row['description'] ?? '-'}",
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 9,
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// --- TAB MANAGER APPROVAL (FILTER BY DEPARTMENT) ---
// ============================================================================
class ManagerApprovalTab extends StatefulWidget {
  final int managerId;
  final int departmentId;

  const ManagerApprovalTab({
    Key? key,
    required this.managerId,
    required this.departmentId,
  }) : super(key: key);

  @override
  _ManagerApprovalTabState createState() => _ManagerApprovalTabState();
}

class _ManagerApprovalTabState extends State<ManagerApprovalTab> {
  // ==========================================================
  // FUNGSI PEMBANTU FORMAT TANGGAL & JAM (Sama dengan Riwayat Staf)
  // ==========================================================
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

  // ==========================================================
  // LOGIKA PENGAMBILAN & PENYARINGAN DATA SESUAI DEPARTEMEN
  // ==========================================================
  Future<List<Map<String, dynamic>>> _fetchDataCuti() async {
    final empData = await Supabase.instance.client
        .from('employees')
        .select('id, full_name')
        .eq('department_id', widget.departmentId);

    Map<String, String> empMap = {};
    for (var e in empData) {
      empMap[e['id'].toString()] = e['full_name'].toString();
    }

    final reqData = await Supabase.instance.client
        .from('leave_requests')
        .select('*')
        .order('created_at', ascending: false);

    List<Map<String, dynamic>> finalData = [];
    for (var req in reqData) {
      String empId = req['employee_id'].toString();
      if (empMap.containsKey(empId)) {
        var row = Map<String, dynamic>.from(req);
        row['full_name'] = empMap[empId];
        finalData.add(row);
      }
    }
    return finalData;
  }

  Future<List<Map<String, dynamic>>> _fetchDataLembur() async {
    final empData = await Supabase.instance.client
        .from('employees')
        .select('id, full_name')
        .eq('department_id', widget.departmentId);

    Map<String, String> empMap = {};
    for (var e in empData) {
      empMap[e['id'].toString()] = e['full_name'].toString();
    }

    final reqData = await Supabase.instance.client
        .from('overtime_requests')
        .select('*')
        .order('created_at', ascending: false);

    List<Map<String, dynamic>> finalData = [];
    for (var req in reqData) {
      String empId = req['employee_id'].toString();
      if (empMap.containsKey(empId)) {
        var row = Map<String, dynamic>.from(req);
        row['full_name'] = empMap[empId];
        finalData.add(row);
      }
    }
    return finalData;
  }

  // ==========================================================
  // FUNGSI UPDATE DATABASE
  // ==========================================================
  Future<void> _updateStatusCuti(
    int id,
    String newStatus,
    String leaveType,
    String? userId,
    String startDate,
    String endDate,
  ) async {
    try {
      await Supabase.instance.client
          .from('leave_requests')
          .update({'status': newStatus}).eq('id', id);

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
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Berhasil memproses pengajuan!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _updateStatusLembur(
    int id,
    String newStatus,
    dynamic employeeId,
    double durasi,
  ) async {
    try {
      await Supabase.instance.client.from('overtime_requests').update(
          {'status': newStatus, 'approved_by': widget.managerId}).eq('id', id);

      if (newStatus == 'approved' && employeeId != null) {
        final empData = await Supabase.instance.client
            .from('employees')
            .select('total_overtime_hours')
            .eq('id', employeeId)
            .single();
        double currentTotal = double.parse(
          (empData['total_overtime_hours'] ?? 0).toString(),
        );
        await Supabase.instance.client
            .from('employees')
            .update({'total_overtime_hours': currentTotal + durasi}).eq(
                'id', employeeId);
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lembur berhasil diproses!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  // ==========================================================
  // WIDGET UI (TAMPILAN)
  // ==========================================================
  Widget _buildDaftarPersetujuanCuti() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchDataCuti(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("Tidak ada pengajuan cuti."));
        }

        // Terapkan Limit Maksimal 15 Data
        final list = snapshot.data!.take(15).toList();

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final row = list[index];
            final empName = row['full_name'] ?? 'Karyawan';
            final rawStatus =
                (row['status'] ?? 'pending').toString().toLowerCase();

            Color statusColor = Colors.orange;
            String statusText = "PENDING";
            if (rawStatus == 'approved' || rawStatus == 'disetujui') {
              statusColor = Colors.green;
              statusText = "APPROVED";
            } else if (rawStatus == 'rejected' || rawStatus == 'ditolak') {
              statusColor = Colors.red;
              statusText = "REJECTED";
            }

            return Card(
              color: Colors.grey.shade50, // Latar mirip di gambar
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: BorderSide(
                  color: Colors.grey.shade300,
                  width: 1,
                ), // Garis luar
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                title: Text(
                  "$empName • ${row['leave_type'] ?? 'Cuti'}",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      "${_formatTanggalCantik(row['start_date'])} s/d ${_formatTanggalCantik(row['end_date'])}",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Alasan: ${row['reason'] ?? '-'}",
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.black54,
                      ),
                    ),

                    // --- MUNCULKAN TOMBOL HANYA JIKA STATUS MASIH PENDING ---
                    if (rawStatus == 'pending') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _updateStatusCuti(
                                row['id'],
                                'rejected',
                                row['leave_type'],
                                row['user_id']?.toString(),
                                row['start_date'],
                                row['end_date'],
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
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
                              onPressed: () => _updateStatusCuti(
                                row['id'],
                                'approved',
                                row['leave_type'],
                                row['user_id']?.toString(),
                                row['start_date'],
                                row['end_date'],
                              ),
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
                // --- MUNCULKAN BADGE (SEPERTI GAMBAR) JIKA SUDAH APPROVED/REJECTED ---
                trailing: rawStatus == 'pending'
                    ? null
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor, width: 1.2),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 10,
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDaftarPersetujuanLembur() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchDataLembur(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("Tidak ada pengajuan lembur."));
        }

        // Terapkan Limit Maksimal 15 Data
        final listLembur = snapshot.data!.take(15).toList();

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: listLembur.length,
          itemBuilder: (context, index) {
            final row = listLembur[index];
            final empName = row['full_name'] ?? 'Karyawan';
            final rawStatus =
                (row['status'] ?? 'pending').toString().toLowerCase();

            Color statusColor = Colors.orange;
            String statusText = "PENDING";
            if (rawStatus == 'approved' || rawStatus == 'disetujui') {
              statusColor = Colors.green;
              statusText = "APPROVED";
            } else if (rawStatus == 'rejected' || rawStatus == 'ditolak') {
              statusColor = Colors.red;
              statusText = "REJECTED";
            }

            String jamMulai = _formatJam(row['start_time']?.toString());
            String jamSelesai = _formatJam(row['end_time']?.toString());
            String durasi = _hitungDurasi(
              row['start_time']?.toString(),
              row['end_time']?.toString(),
            );

            return Card(
              color: Colors.grey.shade50, // Latar mirip di gambar
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: BorderSide(
                  color: Colors.grey.shade300,
                  width: 1,
                ), // Garis luar
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                title: Text(
                  "$empName • Lembur",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      _formatTanggalCantik(
                        row['overtime_date'] ?? row['start_time'],
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "$jamMulai - $jamSelesai WIB $durasi",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Pekerjaan: ${row['reason'] ?? row['description'] ?? '-'}",
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.black54,
                      ),
                    ),

                    // --- MUNCULKAN TOMBOL HANYA JIKA STATUS MASIH PENDING ---
                    if (rawStatus == 'pending') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _updateStatusLembur(
                                row['id'],
                                'rejected',
                                row['employee_id'],
                                double.tryParse(
                                      row['duration_hours']?.toString() ?? '0',
                                    ) ??
                                    0.0,
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
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
                              onPressed: () => _updateStatusLembur(
                                row['id'],
                                'approved',
                                row['employee_id'],
                                double.tryParse(
                                      row['duration_hours']?.toString() ?? '0',
                                    ) ??
                                    0.0,
                              ),
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
                // --- MUNCULKAN BADGE (SEPERTI GAMBAR) JIKA SUDAH APPROVED/REJECTED ---
                trailing: rawStatus == 'pending'
                    ? null
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor, width: 1.2),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 10,
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: [
              Tab(text: "Approval Cuti"),
              Tab(text: "Approval Lembur"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildDaftarPersetujuanCuti(),
                _buildDaftarPersetujuanLembur(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// --- TAB 3: PROFIL KARYAWAN (FULL UPDATE DENGAN VIEW/EDIT & DROPDOWN) ---
// ============================================================================
class ProfilKaryawanTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onProfileUpdated;

  const ProfilKaryawanTab({
    Key? key,
    required this.userData,
    required this.onProfileUpdated,
  }) : super(key: key);

  @override
  _ProfilKaryawanTabState createState() => _ProfilKaryawanTabState();
}

class ChildInputData {
  final TextEditingController nameCtrl = TextEditingController();
  DateTime? birthDate;
}

class _ProfilKaryawanTabState extends State<ProfilKaryawanTab> {
  // --- VARIABEL KONTROL MODE EDIT ---
  bool _isEditing = false;
  // ----------------------------------

  DateTime? _birthDate;
  DateTime? _spouseBirthDate;
  final _nameCtrl = TextEditingController();
  final _birthPlaceCtrl = TextEditingController();
  final _ktpCtrl = TextEditingController();
  final _npwpCtrl = TextEditingController();
  final _addrKtpCtrl = TextEditingController();
  final _addrNowCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _spouseCtrl = TextEditingController();
  final _spouseBirthCtrl = TextEditingController();
  final _emerNameCtrl = TextEditingController();
  final _emerPhoneCtrl = TextEditingController();

  List<ChildInputData> _childrenInputs = [];
  String? _selectedReligion;
  String? _selectedEducation; // Variabel untuk Dropdown Pendidikan
  String _selectedStatus = 'Single';
  bool _isSaving = false;

  String? _profileImageUrl;
  bool _isUploadingPhoto = false;

  @override
  // --- MESIN PENERJEMAH TANGGAL AMAN ---
  DateTime? _parseDateAman(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty || dateStr == 'null')
      return null;
    try {
      if (dateStr.contains('-')) {
        var parts = dateStr.split('-');
        if (parts.length == 3) {
          // Jika formatnya dd-MM-yyyy (contoh: 14-07-2026)
          if (parts[2].length == 4) {
            return DateTime(
              int.parse(parts[2]),
              int.parse(parts[1]),
              int.parse(parts[0]),
            );
          }
          // Jika formatnya yyyy-MM-dd (contoh: 2026-07-14)
          else if (parts[0].length == 4) {
            return DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          }
        }
      }
      return DateTime.tryParse(dateStr);
    } catch (e) {
      debugPrint("Gagal parse tanggal: $dateStr");
      return null;
    }
  }

  void initState() {
    super.initState();
    _loadDataToForm();
  }

  @override
  void didUpdateWidget(ProfilKaryawanTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Jika data dari database berubah (refresh), paksa form untuk update
    if (widget.userData != oldWidget.userData) {
      _loadDataToForm();
    }
  }

  void _loadDataToForm() {
    _nameCtrl.text = widget.userData['full_name'] ?? '';
    _birthPlaceCtrl.text = widget.userData['birth_place'] ?? '';
    _religionCtrl_init();

    // Inisialisasi Data Pendidikan (Khusus SMA/SMK ke Atas)
    final edu = widget.userData['education'];
    if (['SMA/SMK', 'D3', 'S1', 'S2', 'S3'].contains(edu)) {
      _selectedEducation = edu;
    } else {
      _selectedEducation = null;
    }

    _ktpCtrl.text = widget.userData['ktp_number'] ?? '';
    _npwpCtrl.text = widget.userData['npwp_number'] ?? '';
    _addrKtpCtrl.text = widget.userData['address_ktp'] ?? '';
    _addrNowCtrl.text = widget.userData['address_now'] ?? '';
    _phoneCtrl.text = widget.userData['phone'] ?? '';
    _spouseCtrl.text = widget.userData['spouse_name'] ?? '';
    _spouseBirthCtrl.text = widget.userData['spouse_birth_date'] ?? '';
    _emerNameCtrl.text = widget.userData['emergency_name'] ?? '';
    _emerPhoneCtrl.text = widget.userData['emergency_phone'] ?? '';
    _selectedStatus = widget.userData['marital_status'] ?? 'Single';

    _profileImageUrl = widget.userData['photo_url'];

    // Gunakan parser aman untuk tanggal karyawan & pasangan
    _birthDate = _parseDateAman(widget.userData['birth_date']?.toString());
    _spouseBirthDate = _parseDateAman(
      widget.userData['spouse_birth_date']?.toString(),
    );

    // --- FIX BACA DATA ANAK ---
    _childrenInputs.clear();
    final rawChildren = widget.userData['children_data'];

    if (rawChildren != null && rawChildren.toString() != 'null') {
      try {
        List<dynamic> childrenList = [];
        if (rawChildren is List) {
          childrenList = rawChildren;
        } else if (rawChildren is String) {
          childrenList = jsonDecode(rawChildren);
        }

        for (var child in childrenList) {
          if (child is Map) {
            final ci = ChildInputData();
            ci.nameCtrl.text = child['name']?.toString() ?? '';
            // Gunakan parser aman untuk tanggal lahir anak dari JSONB
            ci.birthDate = _parseDateAman(child['birth_date']?.toString());

            _childrenInputs.add(ci);
          }
        }
      } catch (e) {
        debugPrint("Gagal load data anak: $e");
      }
    }

    // Update setelah data masuk
    if (mounted) setState(() {});
  }

  void _religionCtrl_init() {
    final rel = widget.userData['religion'];
    if ([
      'Islam',
      'Kristen Protestan',
      'Kristen Katolik',
      'Hindu',
      'Budha',
    ].contains(rel)) {
      _selectedReligion = rel;
    }
  }

  Future<DateTime?> _pickDate(DateTime? initialDate) async {
    return await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime(1990),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
    );
  }

  Future<void> _uploadFotoProfil() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );

    if (image == null) return;

    setState(() => _isUploadingPhoto = true);

    try {
      final bytes = await image.readAsBytes();
      final fileExt = image.name.split('.').last;
      final fileName =
          'profil_${widget.userData['id']}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await Supabase.instance.client.storage
          .from('profile_photos')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      await Future.delayed(const Duration(milliseconds: 2000));

      final imageUrl = Supabase.instance.client.storage
              .from('profile_photos')
              .getPublicUrl(fileName) +
          "?v=${DateTime.now().millisecondsSinceEpoch}";

      await Supabase.instance.client
          .from('employees')
          .update({'photo_url': imageUrl}).eq('id', widget.userData['id']);

      setState(() {
        _profileImageUrl = imageUrl;
      });

      widget.onProfileUpdated();

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Foto profil berhasil diperbarui!"),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal upload: $e"),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _simpanProfil() async {
    setState(() => _isSaving = true);
    try {
      List<Map<String, dynamic>> childrenJson = _childrenInputs
          .map(
            (c) => {
              'name': c.nameCtrl.text,
              // Simpan dengan format yang sama dengan yang di-load
              'birth_date': c.birthDate != null
                  ? DateFormat('dd-MM-yyyy').format(c.birthDate!)
                  : null,
            },
          )
          .toList();

      await Supabase.instance.client.from('employees').update({
        'full_name': _nameCtrl.text,
        'birth_place': _birthPlaceCtrl.text,
        'birth_date': _birthDate != null
            ? DateFormat('dd-MM-yyyy').format(_birthDate!)
            : null,
        'religion': _selectedReligion,
        'marital_status': _selectedStatus,
        'ktp_number': _ktpCtrl.text,
        'npwp_number': _npwpCtrl.text,
        'address_ktp': _addrKtpCtrl.text,
        'address_now': _addrNowCtrl.text,
        'phone': _phoneCtrl.text,
        'education':
            _selectedEducation, // Menyimpan pilihan Dropdown Pendidikan
        'spouse_name': _spouseCtrl.text,
        'spouse_birth_date': _spouseBirthCtrl.text,
        'children_data': childrenJson,
        'emergency_name': _emerNameCtrl.text,
        'emergency_phone': _emerPhoneCtrl.text,
      }).eq('id', widget.userData['id']);

      // Kunci kembali form setelah berhasil disimpan
      setState(() {
        _isEditing = false;
      });

      widget.onProfileUpdated();

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Profil berhasil diperbarui!"),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // --- FUNGSI POPUP UBAH PASSWORD ---
  void _showChangePasswordDialog() {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool isUpdating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: const Row(
                children: [
                  Icon(Icons.lock_reset, color: Colors.blue),
                  SizedBox(width: 10),
                  Text("Ubah Password"),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: newPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: "Password Baru",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: confirmPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: "Konfirmasi Password Baru",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isUpdating ? null : () => Navigator.pop(context),
                  child: const Text(
                    "Batal",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade800,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isUpdating
                      ? null
                      : () async {
                          final pass = newPassCtrl.text;
                          final conf = confirmPassCtrl.text;

                          if (pass.isEmpty || conf.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Password tidak boleh kosong!"),
                              ),
                            );
                            return;
                          }
                          if (pass != conf) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Password baru tidak cocok!"),
                              ),
                            );
                            return;
                          }
                          if (pass.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Password minimal 6 karakter!"),
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isUpdating = true);
                          try {
                            await Supabase.instance.client.auth.updateUser(
                              UserAttributes(password: pass),
                            );

                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Password berhasil diubah!"),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Gagal mengubah password: $e"),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } finally {
                            if (mounted)
                              setDialogState(() => isUpdating = false);
                          }
                        },
                  child: isUpdating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text("Simpan"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Stack(
        children: [
          Container(
            height: 180,
            decoration: const BoxDecoration(
              color: Color(0xFF0D47A1),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              key: ValueKey(_profileImageUrl),
                              radius: 50,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage: _profileImageUrl != null
                                  ? NetworkImage(_profileImageUrl!)
                                  : null,
                              child: _profileImageUrl == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 38,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                            if (_isUploadingPhoto)
                              const Positioned.fill(
                                child: CircularProgressIndicator(),
                              ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _isUploadingPhoto
                                    ? null
                                    : _uploadFotoProfil,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Text(
                          _isEditing
                              ? "Mode Edit Profil"
                              : (widget.userData['full_name'] ?? '-'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _isEditing
                                ? Colors.orange.shade800
                                : Colors.black,
                          ),
                        ),
                        if (!_isEditing)
                          Text(
                            widget.userData['nik'] ?? '-',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 15,
                            ),
                          ),
                        const Divider(height: 30, thickness: 1),
                        // --- PASTE KODE BARU DI SINI (MENGGANTIKAN ROW YANG LAMA) ---
                        Builder(
                          builder: (context) {
                            // 1. Ambil Data
                            String divisi =
                                widget.userData['dept_name']?.toString() ?? '-';
                            String jabatan =
                                widget.userData['jabatan_name']?.toString() ??
                                    '-';

                            // 2. Format Join Date
                            String rawJoinDate =
                                widget.userData['join_date']?.toString() ?? '';
                            String joinDateFormatted = "-";

                            if (rawJoinDate.isNotEmpty &&
                                rawJoinDate != 'null') {
                              try {
                                String datePart = rawJoinDate.contains('T')
                                    ? rawJoinDate.split('T')[0]
                                    : rawJoinDate.split(' ')[0];
                                DateTime dt = DateTime.parse(datePart);
                                joinDateFormatted = DateFormat(
                                  'dd MMM yyyy',
                                  'id_ID',
                                ).format(dt);
                              } catch (e) {
                                joinDateFormatted = rawJoinDate;
                              }
                            }

                            // Sejajar 3 Kolom
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  // --- BLOK 1: DIVISI ---
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(
                                          "Divisi",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          divisi,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade800,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // --- GARIS PEMISAH ---
                                  Container(
                                    height: 25,
                                    width: 1,
                                    color: Colors.grey.shade300,
                                  ),

                                  // --- BLOK 2: JABATAN ---
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(
                                          "Jabatan",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          jabatan,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade800,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // --- GARIS PEMISAH ---
                                  Container(
                                    height: 25,
                                    width: 1,
                                    color: Colors.grey.shade300,
                                  ),

                                  // --- BLOK 3: JOIN DATE ---
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(
                                          "Join Date",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          joinDateFormatted,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade800,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    children: [
                      ExpansionTile(
                        //initiallyExpanded: true,
                        leading: const Icon(
                          Icons.person_outline,
                          color: Colors.blue,
                        ),
                        title: const Text(
                          "Data Diri",
                          style: TextStyle(
                            fontSize: 13, // <-- Di sinilah tempat yang benar
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        maintainState: true,
                        childrenPadding: const EdgeInsets.all(16),
                        children: [
                          _buildField("Nama Lengkap", _nameCtrl),

                          // --- DROPDOWN PENDIDIKAN ---
                          _buildField("Tempat Lahir", _birthPlaceCtrl),
                          _buildDatePickerField(
                            "Tanggal Lahir",
                            _birthDate,
                            () async {
                              final picked = await _pickDate(_birthDate);
                              if (picked != null)
                                setState(() => _birthDate = picked);
                            },
                          ),
                          _buildDropdown(
                            "Agama",
                            _selectedReligion,
                            [
                              'Islam',
                              'Kristen Protestan',
                              'Kristen Katolik',
                              'Hindu',
                              'Budha',
                            ],
                            (val) => setState(() => _selectedReligion = val),
                          ),
                          _buildField("Nomor KTP", _ktpCtrl),
                          _buildField("Nomor NPWP", _npwpCtrl),
                          _buildField(
                            "Alamat Sesuai KTP",
                            _addrKtpCtrl,
                            maxLines: 2,
                          ),
                          _buildField(
                            "Alamat Domisili",
                            _addrNowCtrl,
                            maxLines: 2,
                          ),
                          _buildField("Nomor HP", _phoneCtrl),
                          _buildDropdown(
                            "Pendidikan Terakhir",
                            _selectedEducation,
                            ['SMA/SMK', 'D3', 'S1', 'S2', 'S3'],
                            (val) => setState(() => _selectedEducation = val),
                          ),
                        ],
                      ),
                      const Divider(height: 1),
                      ExpansionTile(
                        leading: const Icon(
                          Icons.family_restroom,
                          color: Colors.blue,
                        ),
                        title: const Text(
                          "Data Keluarga",
                          style: TextStyle(
                            fontSize: 13, // <-- Di sinilah tempat yang benar
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        maintainState: true,
                        childrenPadding: const EdgeInsets.all(16),
                        children: [
                          _buildDropdown(
                            "Status Pernikahan",
                            _selectedStatus,
                            ['Single', 'Menikah', 'Bercerai'],
                            (val) => setState(() => _selectedStatus = val!),
                          ),
                          if (_selectedStatus != 'Single') ...[
                            _buildField("Nama Suami/Istri", _spouseCtrl),
                            _buildDatePickerField(
                              "Tanggal Lahir Suami/Istri",
                              _spouseBirthDate, // Gunakan variabel khusus istri
                              () async {
                                final picked = await _pickDate(
                                  _spouseBirthDate,
                                );
                                if (picked != null)
                                  setState(() => _spouseBirthDate = picked);
                              },
                            ),
                          ],
                          const Divider(),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Data Anak",
                              style: TextStyle(
                                fontSize:
                                    13, // <-- Di sinilah tempat yang benar
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (!_isEditing && _childrenInputs.isEmpty)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                "- Tidak ada data anak -",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ...List.generate(_childrenInputs.length, (index) {
                            return Card(
                              color: Colors.grey.shade50,
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "Anak ke-${index + 1}",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                        ),
                                        if (_isEditing)
                                          InkWell(
                                            onTap: () => setState(
                                              () => _childrenInputs.removeAt(
                                                index,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.remove_circle,
                                              color: Colors.red,
                                              size: 20,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    _buildField(
                                      "Nama Anak",
                                      _childrenInputs[index].nameCtrl,
                                    ),
                                    _buildDatePickerField(
                                      "Tanggal Lahir",
                                      _childrenInputs[index].birthDate,
                                      () async {
                                        final picked = await _pickDate(
                                          _childrenInputs[index].birthDate,
                                        );
                                        if (picked != null)
                                          setState(
                                            () => _childrenInputs[index]
                                                .birthDate = picked,
                                          );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          if (_isEditing && _childrenInputs.length < 5)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                icon: const Icon(Icons.add_circle_outline),
                                label: const Text("Tambah Data Anak"),
                                onPressed: () => setState(
                                  () => _childrenInputs.add(ChildInputData()),
                                ),
                              ),
                            ),
                        ],
                      ),
                      //const Divider(),
                      ExpansionTile(
                        leading: const Icon(
                          Icons.contact_emergency_outlined,
                          color: Colors.blue,
                        ),
                        title: const Text(
                          "Kontak Darurat",
                          style: TextStyle(
                            fontSize: 13, // <-- Di sinilah tempat yang benar
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        childrenPadding: const EdgeInsets.all(16),
                        children: [
                          _buildField("Nama Kontak", _emerNameCtrl),
                          _buildField("Nomor HP", _emerPhoneCtrl),
                        ],
                      ),
                      // 2. Tombol Simpan/Update diletakkan di luar (agar selalu terlihat)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildActionButtons(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ==========================================================
                // --- TAMBAHAN BARU: MENU DAFTARKAN WAJAH ---
                // ==========================================================
                if (!_isEditing)
                  Builder(builder: (context) {
                    bool isFaceRegistered =
                        widget.userData['is_face_registered'] == true;

                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: ListTile(
                        leading: Icon(
                          isFaceRegistered
                              ? Icons.face_retouching_natural
                              : Icons.face,
                          color:
                              isFaceRegistered ? Colors.green : Colors.orange,
                        ),
                        title: Text(
                          isFaceRegistered
                              ? "Update Data Wajah"
                              : "Daftarkan Wajah (Wajib)",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isFaceRegistered
                                ? Colors.green
                                : Colors.orange.shade900,
                          ),
                        ),
                        subtitle: isFaceRegistered
                            ? const Text("Data wajah sudah tersimpan",
                                style:
                                    TextStyle(fontSize: 10, color: Colors.grey))
                            : const Text(
                                "Daftarkan wajah untuk keperluan absensi",
                                style:
                                    TextStyle(fontSize: 10, color: Colors.red)),
                        trailing:
                            const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () async {
                          // 1. Cek Permission Kamera
                          var cameraStatus = await Permission.camera.request();
                          if (!cameraStatus.isGranted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Izin kamera diperlukan!')));
                            return;
                          }

                          // 2. Buka Kamera Depan
                          final cameras = await availableCameras();
                          final frontCamera = cameras.firstWhere(
                            (cam) =>
                                cam.lensDirection == CameraLensDirection.front,
                            orElse: () => cameras.first,
                          );

                          // 3. Buka Halaman RegisterFacePage menggunakan Navigator.push
                          final bool? isRegistered = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  RegisterFacePage(camera: frontCamera),
                            ),
                          );

                          // 4. Jika sukses daftar, refresh data profil
                          if (isRegistered == true) {
                            setState(() {}); // Refresh UI state lokal
                            widget
                                .onProfileUpdated(); // Memanggil fungsi update bawaan widget
                          }
                        },
                      ),
                    );
                  }),

                if (!_isEditing) const SizedBox(height: 10),

                // --- BAGIAN UBAH PASSWORD (Hanya Tampil Saat Read-Only) ---
                if (!_isEditing)
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.lock_outline,
                        color: Colors.red,
                      ),
                      title: const Text(
                        "Ubah Password",
                        style: TextStyle(
                          fontSize: 13, // <-- Di sinilah tempat yang benar
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.grey,
                      ),
                      onTap: () {
                        _showChangePasswordDialog();
                      },
                    ),
                  ),

                if (!_isEditing) const SizedBox(height: 10),

                // --- BAGIAN LOGOUT (Hanya Tampil Saat Read-Only) ---
                if (!_isEditing)
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text(
                        "Logout",
                        style: TextStyle(
                          fontSize: 13, // <-- Di sinilah tempat yang benar
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.grey,
                      ),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext dialogContext) {
                            return AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              title: const Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.orange,
                                    size: 28,
                                  ),
                                  SizedBox(width: 10),
                                  Text("Konfirmasi"),
                                ],
                              ),
                              content: const Text(
                                "Apakah Anda yakin ingin keluar dari aplikasi?",
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(dialogContext);
                                  },
                                  child: const Text(
                                    "Batal",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () async {
                                    Navigator.pop(dialogContext);
                                    await Supabase.instance.client.auth
                                        .signOut();
                                    if (mounted) {
                                      Navigator.pushReplacementNamed(
                                        context,
                                        '/login',
                                      );
                                    }
                                  },
                                  child: const Text("Ya, Keluar"),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- FUNGSI PEMBANTU WIDGETS (AUTO SWITCH VIEW/EDIT MODE) ---
  Widget _buildField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    if (!_isEditing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                controller.text.isEmpty ? '-' : controller.text,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String? value,
    List<String> items,
    Function(String?) onChanged,
  ) {
    if (!_isEditing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                value ?? '-',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDatePickerField(
    String label,
    DateTime? date,
    VoidCallback onTap,
  ) {
    String dateStr =
        date != null ? DateFormat('dd MMM yyyy').format(date) : "-";
    if (!_isEditing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                dateStr,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(date != null ? dateStr : "Pilih Tanggal"),
              const Icon(Icons.calendar_today, size: 20, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  // --- AREA TOMBOL DINAMIS (UPDATE vs SIMPAN/BATAL) ---
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.only(top: 15, bottom: 20),
      child: _isEditing
          ? Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Colors.red),
                      foregroundColor: Colors.red,
                    ),
                    onPressed: () {
                      setState(() => _isEditing = false);
                      _loadDataToForm();
                    },
                    child: const Text("Batal"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isSaving ? null : _simpanProfil,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "Simpan Perubahan",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            )
          : SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text(
                  "Update Data Profil",
                  style: TextStyle(
                    fontSize: 13, // <-- Di sinilah tempat yang benar
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  setState(() => _isEditing = true);
                },
              ),
            ),
    );
  }
}

// ============================================================================
// --- HALAMAN PENGUMUMAN (NOTIFIKASI) ---
// ============================================================================
class PengumumanPage extends StatefulWidget {
  const PengumumanPage({Key? key}) : super(key: key);

  @override
  _PengumumanPageState createState() => _PengumumanPageState();
}

class _PengumumanPageState extends State<PengumumanPage> {
  // --- Fungsi Hapus Pengumuman ---
  Future<void> _deleteAnnouncement(int id) async {
    try {
      await Supabase.instance.client
          .from('announcements')
          .delete()
          .eq('id', id);

      Navigator.pop(context); // Tutup Bottom Sheet
      setState(() {}); // Refresh list pengumuman di layar

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Pengumuman berhasil dihapus"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Gagal menghapus: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- Fungsi Menampilkan Bottom Sheet ---
  void _showDetailBottomSheet(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height * 0.3,
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  item['title'] ?? 'Tanpa Judul',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item['created_at'] != null
                      ? DateFormat(
                          'dd MMM yyyy, HH:mm',
                          'id_ID',
                        ).format(DateTime.parse(item['created_at']).toLocal())
                      : '',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const Divider(height: 30),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      item['content'] ?? 'Tidak ada deskripsi',
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Tombol Delete
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text("Hapus Pemberitahuan"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade100,
                      foregroundColor: Colors.red.shade900,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () {
                      _deleteAnnouncement(item['id']);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pemberitahuan"),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder(
        future: Supabase.instance.client
            .from('announcements')
            .select()
            .eq('is_active', true)
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData || (snapshot.data as List).isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    "Belum ada pemberitahuan.",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          final list = snapshot.data as List;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, i) {
              final item = list[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade50,
                  child: Icon(Icons.campaign, color: Colors.blue.shade900),
                ),
                title: Text(
                  item['title'] ?? 'Tanpa Judul',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  item['content'] ?? '',
                  maxLines: 2,
                  overflow:
                      TextOverflow.ellipsis, // Terpotong jika terlalu panjang
                ),
                onTap: () => _showDetailBottomSheet(item),
              );
            },
          );
        },
      ),
    );
  }
}
