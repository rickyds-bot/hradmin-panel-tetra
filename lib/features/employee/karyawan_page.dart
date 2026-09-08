import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';
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
import 'package:mobile_absensi/features/core/utils/app_logger.dart';
import 'package:flutter_html/flutter_html.dart' hide Marker;

// ============================================================================
// --- 1. CLASS UTAMA (KARYAWAN PAGE DENGAN GOJEK STYLE BOTTOM NAV) ---
// ============================================================================
class KaryawanPage extends StatefulWidget {
  @override
  _KaryawanPageState createState() => _KaryawanPageState();
}

class _KaryawanPageState extends State<KaryawanPage>
    with WidgetsBindingObserver {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  int _currentMenuIndex = 0;

  bool _skipMorningNotif = false;
  bool _skipEveningNotif = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializeDateFormatting('id_ID', null);
    _initProcess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed &&
        userData != null &&
        userData!['id'] != null) {
      NotificationService().recheckExactAlarmPermissionAndReschedule(
        skipMorning: _skipMorningNotif,
        skipEvening: _skipEveningNotif,
      );
    }
  }

  Future<void> _initProcess() async {
    await _fetchUserData();

    if (userData != null && userData!['id'] != null) {
      try {
        final notifService = NotificationService();
        await notifService.initialize();

        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final absensiToday = await Supabase.instance.client
            .from('attendance')
            .select('status')
            .eq('employee_id', userData!['id'])
            .gte('created_at', '${todayStr}T00:00:00')
            .lte('created_at', '${todayStr}T23:59:59');

        bool hasCheckIn = absensiToday
            .any((e) => e['status'].toString().toLowerCase() == 'check-in');
        bool hasCheckOut = absensiToday
            .any((e) => e['status'].toString().toLowerCase() == 'check-out');

        // Simpan supaya bisa dipakai ulang di didChangeAppLifecycleState.
        _skipMorningNotif = hasCheckIn;
        _skipEveningNotif = hasCheckOut;

        await notifService.setupAbsensiNotifications(
          skipMorning: hasCheckIn,
          skipEvening: hasCheckOut,
        );
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
      // 1. Ambil data karyawan utama terlebih dahulu
      final response = await Supabase.instance.client
          .from('employees')
          .select('*')
          .eq('email', currentUser.email!)
          .single();

      // 2. Wajib: Buat salinan (copy) dari response agar bisa ditambahkan data baru
      final Map<String, dynamic> data = Map<String, dynamic>.from(response);

      // 3. Tarik data relasi secara BERSAMAAN (Paralel) menggunakan Future.wait
      // Ini jauh lebih cepat daripada menunggu satu-satu (sekuensial)
      final results = await Future.wait([
        Supabase.instance.client
            .from('departments')
            .select('name')
            .eq('id', data['department_id'] ?? 0)
            .maybeSingle(),
        Supabase.instance.client
            .from('positions')
            .select('name')
            .eq('id', data['position_id'] ?? 0)
            .maybeSingle(),
        Supabase.instance.client
            .from('locations')
            .select('name')
            .eq('id', data['location_id'] ?? 0)
            .maybeSingle(),
      ]);

      // 4. Masukkan hasil tarikan paralel ke dalam map
      data['dept_name'] = results[0]?['name'] ?? '-';
      data['pos_name'] = results[1]?['name'] ?? '-';
      data['loc_name'] = results[2]?['name'] ?? '-';

      if (mounted) {
        setState(() {
          userData = data;
        });
      }
    } catch (e) {
      debugPrint("Error fetching data: $e");
    }
  }

  // =========================================================================
  // --- WIDGET CUSTOM BOTTOM NAV BAR ALA GOJEK ---
  // =========================================================================
  Widget _buildGojekBottomNav(
      List<Map<String, dynamic>> items, int currentIndex) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: List.generate(items.length, (index) {
            final isSelected = index == currentIndex;
            final item = items[index];

            return Expanded(
              child: InkWell(
                onTap: () => setState(() => _currentMenuIndex = index),
                child: Container(
                  decoration: isSelected
                      ? BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.blue.withOpacity(0.12),
                              Colors.white.withOpacity(0.0),
                            ],
                          ),
                        )
                      : null,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- GARIS GRADASI ATAS (INDICATOR ALA GOJEK) ---
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 3.5,
                        margin: const EdgeInsets.symmetric(horizontal: 0),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? LinearGradient(
                                  colors: [
                                    Colors.blue.shade400,
                                    Colors.blue.shade900,
                                  ],
                                )
                              : const LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Colors.transparent,
                                  ],
                                ),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // --- ICON TAB ---
                      Icon(
                        item['icon'],
                        color: isSelected
                            ? Colors.blue.shade900
                            : Colors.grey.shade500,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      // --- LABEL TEXT ---
                      Text(
                        item['label'],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? Colors.blue.shade900
                              : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
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

    final String userRole =
        (userData!['pos_name'] ?? '').toString().toLowerCase();
    final bool isApprover = (userRole.contains('supervisor') ||
        userRole.contains('manager') ||
        userRole.contains('admin'));

    final List<Widget> activePages = [];
    final List<Map<String, dynamic>> activeNavItems = [];
    final List<String> activeTitles = [];

    activePages.add(AbsensiKaryawanTab(userData: userData!));
    activeNavItems.add({
      'icon': Icons.dashboard_rounded,
      'label': "Beranda",
    });
    activeTitles.add("HRIS Tetra");

    activePages.add(CutiKaryawanTab(userData: userData!));
    activeNavItems.add({
      'icon': Icons.calendar_month_rounded,
      'label': "Cuti/Izin",
    });
    activeTitles.add("Pengajuan Cuti/Izin");

    if (isApprover) {
      activePages.add(
        ManagerApprovalTab(
          managerId: userData!['id'],
          departmentId: userData!['department_id'],
          managerRole: userRole,
        ),
      );
      activeNavItems.add({
        'icon': Icons.fact_check_rounded,
        'label': "Approval",
      });
      activeTitles.add("Approval");
    } else {
      activePages.add(LemburKaryawanTab(userData: userData!));
      activeNavItems.add({
        'icon': Icons.more_time_rounded,
        'label': "Lembur",
      });
      activeTitles.add("Pengajuan Lembur");
    }

    activePages.add(
      ProfilKaryawanTab(
        userData: userData!,
        onProfileUpdated: () => _fetchUserData(),
      ),
    );
    activeNavItems.add({
      'icon': Icons.person_rounded,
      'label': "Profile",
    });
    activeTitles.add("Profil Karyawan");

    int safeIndex = _currentMenuIndex;
    if (safeIndex >= activePages.length) {
      safeIndex = activePages.length - 1;
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      // --- UPDATE: Menghilangkan AppBar untuk Beranda DAN Profil ---
      appBar: (safeIndex == 0 || safeIndex == activePages.length - 1)
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
      body: activePages[safeIndex],
      bottomNavigationBar: _buildGojekBottomNav(activeNavItems, safeIndex),
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
  final Set<Marker> _markers = {};
  bool _isLoadingMap = true;

  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    userUuid = Supabase.instance.client.auth.currentUser?.id;
    _timeString = DateFormat('HH:mm:ss').format(DateTime.now());
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer t) => _updateTime(),
    );
    _getCurrentLocation();
    _checkNewAnnouncements();
    _refreshHistory();
  }

  void _refreshHistory() {
    _historyFuture = Supabase.instance.client
        .from('attendance')
        .select()
        .eq('employee_id', userId)
        .order('created_at', ascending: false)
        .limit(30);

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
        int latestId = data[0]['id'];
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

  // Menggerakkan kamera Google Maps ke posisi terbaru.
  // Tanpa ini, peta cuma diam di posisi awal (initialCameraPosition)
  // walaupun marker-nya sudah pindah -> kelihatan seperti "stuck".
  Future<void> _animateCameraTo(Position pos) async {
    if (_mapController == null) return;
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
    } catch (e) {
      debugPrint("Gagal animasi kamera map: $e");
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'GPS tidak aktif.';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // 1. Tampilkan lokasi terakhir yang tersimpan di memori HP agar Map langsung muncul
      Position? lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null && mounted) {
        setState(() {
          _currentPosition = lastPosition;
          _markers.add(
            Marker(
              markerId: const MarkerId('me'),
              position: LatLng(lastPosition.latitude, lastPosition.longitude),
            ),
          );
          _isLoadingMap = false; // Map langsung terbuka tanpa lag
        });
        _animateCameraTo(lastPosition);
      }

      // 2. Ambil lokasi real-time dengan akurasi medium (lebih cepat dari high).
      // Dikasih timeout supaya kalau sinyal GPS lemah, tidak menggantung
      // selamanya dan spinner _isLoadingMap tidak macet terus.
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (lastPosition != null) return lastPosition;
          throw 'Waktu tunggu GPS habis. Coba lagi di area dengan sinyal lebih baik.';
        },
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _markers.clear();
          _markers.add(
            Marker(
              markerId: const MarkerId('me'),
              position: LatLng(position.latitude, position.longitude),
            ),
          );
          _isLoadingMap = false;
        });
        _animateCameraTo(position);
      }
    } catch (e) {
      debugPrint("Gagal ambil lokasi: $e");
      if (mounted) setState(() => _isLoadingMap = false);
    }
  }

  Future<void> _absen(BuildContext context, String tipe) async {
    setState(() => _isLoading = true);
    try {
      final existingAbsen = await Supabase.instance.client
          .from('attendance')
          .select('created_at, status')
          .eq('employee_id', userId)
          .ilike('status', tipe)
          .order('created_at', ascending: false)
          .limit(5);

      final now = DateTime.now();
      bool hasAbsenToday = false;

      for (var row in existingAbsen) {
        if (row['created_at'] != null) {
          final createdAtLocal =
              DateTime.parse(row['created_at'].toString()).toLocal();
          if (createdAtLocal.year == now.year &&
              createdAtLocal.month == now.month &&
              createdAtLocal.day == now.day) {
            hasAbsenToday = true;
            break;
          }
        }
      }

      if (hasAbsenToday) {
        throw 'Anda sudah melakukan ${tipe.toUpperCase()} hari ini. Absen hanya dapat dilakukan 1 kali sehari.';
      }

      var cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted)
        throw 'Izin kamera diperlukan untuk absensi.';

      Position currentPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
            throw 'Gagal mendapatkan lokasi GPS. Pastikan GPS aktif dan sinyal cukup, lalu coba lagi.',
      );

      final empData = await Supabase.instance.client
          .from('employees')
          .select(
              'location_id, face_embedding, is_face_registered, is_free_location')
          .eq('id', userId)
          .single();

      final bool isFreeLocation = empData['is_free_location'] == true;
      final locId = empData['location_id'];

      if (!isFreeLocation && locId == null) {
        throw 'Lokasi kerja belum diatur.';
      }

      if (empData['is_face_registered'] != true ||
          empData['face_embedding'] == null) {
        throw 'Anda belum mendaftarkan wajah. Silakan ke menu Profil untuk mendaftar.';
      }

      List<double> registeredFace;
      try {
        final decoded = jsonDecode(empData['face_embedding'].toString());
        registeredFace = List<double>.from(decoded);
      } catch (e) {
        throw 'Data wajah korup. Silakan update data wajah di menu Profil.';
      }

      if (!isFreeLocation) {
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
      }

      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final String? photoPath = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => KameraAbsenPage(
            camera: frontCamera,
            registeredEmbedding: registeredFace,
          ),
        ),
      );

      if (photoPath == null) return;

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

        await AppLogger.log(
          activity: 'Melakukan $tipe (Absensi Wajah)',
          module: 'Absensi Mobile',
        );

        await file.delete();
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
    return Stack(
      children: [
        Container(
          height: 420,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.blue.shade900,
                Colors.blue.shade400,
                Colors.grey.shade100,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
        Column(
          children: [
            _buildHeader(),
            _buildQuickMetrics(),
            _buildMapSection(),
            _buildActionButtons(),
            _buildHistoryList(),
          ],
        ),
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

  bool _hasNewInfo = false;

  Widget _buildHeader() => Container(
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.of(context).padding.top + 15,
          20,
          25,
        ),
        child: Row(
          children: [
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
            const Spacer(),
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
                    setState(() => _hasNewInfo = false);
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

                    if (!mounted) return;

                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            const PengumumanPage(),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                          const begin = Offset(1.0, 0.0);
                          const end = Offset.zero;
                          const curve = Curves.easeInOut;
                          var tween = Tween(begin: begin, end: end)
                              .chain(CurveTween(curve: curve));
                          return SlideTransition(
                            position: animation.drive(tween),
                            child: child,
                          );
                        },
                      ),
                    ).then((_) {
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
          elevation: 6,
          shadowColor: Colors.black.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
                    onMapCreated: (controller) {
                      _mapController = controller;
                      // Kalau posisi sudah ada duluan (mis. dari getLastKnownPosition)
                      // sebelum map selesai dibuat, langsung snap ke sana.
                      if (_currentPosition != null) {
                        _animateCameraTo(_currentPosition!);
                      }
                    },
                  ),
          ),
        ),
      );

  Widget _buildActionButtons() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                "*Check-In/Check-Out dilakukan di lokasi kerja (kecuali akun diatur bebas lokasi) & wajib verifikasi wajah.",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black,
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
                'EEEE, dd-MM-yyyy, HH:mm',
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

  String _mode = 'Cuti';
  String? _selectedLeaveType;
  XFile? _lampiran;

  @override
  void initState() {
    super.initState();
    _fetchRemainingLeave();
  }

  Future<void> _fetchRemainingLeave() async {
    try {
      final userUuid = Supabase.instance.client.auth.currentUser?.id;
      if (userUuid == null) return;

      final data = await Supabase.instance.client
          .from('leave_balance')
          .select('*')
          .eq('user_id', userUuid)
          .maybeSingle();

      if (mounted && data != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        if (data['next_reset_date'] != null) {
          final DateTime nextReset = DateTime.parse(
            data['next_reset_date'].toString(),
          );

          if (today.isAfter(nextReset) || today.isAtSameMomentAs(nextReset)) {
            final DateTime newResetDate = DateTime(
              nextReset.year + 1,
              nextReset.month,
              nextReset.day,
            );

            await Supabase.instance.client.from('leave_balance').update({
              'total_leave': 12,
              'used_leave': 0,
              'remaining_leave': 12,
              'next_reset_date': DateFormat(
                'yyyy-MM-dd',
              ).format(newResetDate),
            }).eq('user_id', userUuid);

            setState(() {
              _remainingLeave = 12;
              _nextResetDate = newResetDate;
            });
            return;
          }
        }

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
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Pilih Sumber Foto',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.blue),
                title: const Text('Ambil dari Kamera'),
                onTap: () async {
                  Navigator.of(context).pop();
                  final XFile? file = await ImagePicker().pickImage(
                    source: ImageSource.camera,
                    imageQuality: 70,
                  );
                  if (file != null) {
                    setState(() => _lampiran = file);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.blue),
                title: const Text('Ambil dari Galeri'),
                onTap: () async {
                  Navigator.of(context).pop();
                  final XFile? file = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 70,
                  );
                  if (file != null) {
                    setState(() => _lampiran = file);
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
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

    if (_selectedLeaveType == 'Izin Sakit' && _lampiran == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Surat Dokter wajib dilampirkan untuk Izin Sakit!"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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

      if (_lampiran != null) {
        final bytes = await _lampiran!.readAsBytes();
        final fileExt = _lampiran!.name.split('.').last;
        final fileName =
            '${widget.userData['id']}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

        final compressedBytes = await FlutterImageCompress.compressWithFile(
          _lampiran!.path,
          minWidth: 800,
          minHeight: 800,
          quality: 50,
        );

        if (compressedBytes != null) {
          await Supabase.instance.client.storage
              .from('medical_document')
              .uploadBinary(fileName, compressedBytes);

          attachmentUrl = Supabase.instance.client.storage
              .from('medical_document')
              .getPublicUrl(fileName);
        } else {
          await Supabase.instance.client.storage
              .from('medical_document')
              .uploadBinary(fileName, bytes);

          attachmentUrl = Supabase.instance.client.storage
              .from('medical_document')
              .getPublicUrl(fileName);
        }
      }

      // 1. Simpan pengajuan cuti ke database
      await Supabase.instance.client.from('leave_requests').insert({
        'user_id': Supabase.instance.client.auth.currentUser!.id,
        'employee_id': widget.userData['id'],
        'leave_type': _selectedLeaveType,
        'start_date': DateFormat('yyyy-MM-dd').format(_dateRange!.start),
        'end_date': DateFormat('yyyy-MM-dd').format(_dateRange!.end),
        'reason': _reasonCtrl.text,
        'attachment_url': attachmentUrl,
        'status': 'pending',
      });

      // --- LOGIKA NOTIFIKASI DIHAPUS DARI APLIKASI (FLUTTER) ---
      // Karena telah ditangani oleh Webhook Database & Deno Edge Function

      await AppLogger.log(
        activity: 'Mengajukan $_selectedLeaveType ($_mode)',
        module: 'Cuti & Izin',
      );

      _riwayatKey.currentState?._loadData();

      _reasonCtrl.clear();
      setState(() {
        _dateRange = null;
        _lampiran = null;
        _selectedLeaveType = null;
      });
      _fetchRemainingLeave();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text("Pengajuan berhasil dikirim & Atasan telah diberitahu!"),
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

    return Stack(
      children: [
        Container(
          height: 420,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.blue.shade900,
                Colors.blue.shade400,
                Colors.grey.shade100,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
        Column(
          children: [
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
                      leading:
                          const Icon(Icons.info_outline, color: Colors.teal),
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
                    if (_nextResetDate != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          "Sisa cuti akan reset pada: ${DateFormat('dd-MM-yyyy').format(_nextResetDate!)}",
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.teal,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                elevation: 8,
                shadowColor: Colors.black.withOpacity(0.3),
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
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 10),
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
                                  _dateRange = null;
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
                                  _dateRange = null;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
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
                              (type) => DropdownMenuItem(
                                  value: type, child: Text(type)),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedLeaveType = val),
                      ),
                      const SizedBox(height: 15),
                      if (_selectedLeaveType == 'Izin Sakit') ...[
                        OutlinedButton.icon(
                          onPressed: _pickLampiran,
                          icon: Icon(
                            _lampiran == null
                                ? Icons.upload_file
                                : Icons.check_circle,
                            color:
                                _lampiran == null ? Colors.blue : Colors.green,
                          ),
                          label: Text(
                            _lampiran == null
                                ? "Unggah Surat Dokter (Wajib)"
                                : "Surat Dokter Dilampirkan",
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 45),
                            side: BorderSide(
                              color: _lampiran == null
                                  ? Colors.blue
                                  : Colors.green,
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                      ],
                      ElevatedButton.icon(
                        onPressed: () async {
                          DateTime firstAllowedDate = _mode == 'Cuti'
                              ? DateTime.now().add(const Duration(days: 7))
                              : DateTime.now()
                                  .subtract(const Duration(days: 14));

                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: firstAllowedDate,
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null)
                            setState(() => _dateRange = picked);
                        },
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          _dateRange == null
                              ? "Pilih Rentang Tanggal"
                              : "${DateFormat('dd-MM-yyyy').format(_dateRange!.start)} s/d ${DateFormat('dd-MM-yyyy').format(_dateRange!.end)}",
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 45),
                        ),
                      ),
                      if (_mode == 'Cuti')
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Center(
                            child: Text(
                              "*Pengajuan cuti tahunan minimal 7 hari sebelumnya",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 15),
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
                      SizedBox(
                        width: double.infinity,
                        child: _isSubmitting
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade700,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
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
            Expanded(
              child: RiwayatCutiList(
                key: _riwayatKey,
                userId: Supabase.instance.client.auth.currentUser!.id,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// --- KOMPONEN RIWAYAT CUTI ---
// ============================================================================
class RiwayatCutiList extends StatefulWidget {
  final String userId;
  const RiwayatCutiList({Key? key, required this.userId}) : super(key: key);

  @override
  _RiwayatCutiListState createState() => _RiwayatCutiListState();
}

class _RiwayatCutiListState extends State<RiwayatCutiList> {
  List<Map<String, dynamic>> _riwayatList = [];
  Map<int, String> _approverNames = {};
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
      return DateFormat('dd-MM-yyyy').format(dt);
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
          .limit(15);

      Set<int> approverIds = {};
      for (var row in data) {
        if (row['approved_by'] != null) {
          int? parsedId = int.tryParse(row['approved_by'].toString());
          if (parsedId != null) approverIds.add(parsedId);
        }
      }

      Map<int, String> tempNames = {};
      if (approverIds.isNotEmpty) {
        final approvers = await Supabase.instance.client
            .from('employees')
            .select('id, full_name');

        for (var a in approvers) {
          int empId = int.parse(a['id'].toString());
          if (approverIds.contains(empId)) {
            tempNames[empId] = a['full_name'].toString();
          }
        }
      }

      if (mounted) {
        setState(() {
          _riwayatList = List<Map<String, dynamic>>.from(data);
          _approverNames = tempNames;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error load riwayat: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_riwayatList.isEmpty)
      return const Center(child: Text("Belum ada riwayat cuti"));

    return ListView.builder(
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

        String approver = '';
        if (row['approved_by'] != null) {
          int? appId = int.tryParse(row['approved_by'].toString());
          if (appId != null) approver = _approverNames[appId] ?? '';
        }

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
                      fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text("Alasan: ${row['reason'] ?? '-'}",
                    style: const TextStyle(
                        fontSize: 11, fontStyle: FontStyle.italic)),
                if (status != 'PENDING' && approver.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text("Approved By: $approver",
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.blue.shade800,
                          fontWeight: FontWeight.bold)),
                ],
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor)),
              child: Text(status,
                  style: TextStyle(
                      fontSize: 9,
                      color: statusColor,
                      fontWeight: FontWeight.bold)),
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

      if (endDateTime.isBefore(startDateTime)) {
        endDateTime = endDateTime.add(const Duration(days: 1));
      }

      int durationInMinutes = endDateTime.difference(startDateTime).inMinutes;
      double durationInHours = durationInMinutes / 60.0;

      // 1. Simpan pengajuan lembur ke database
      await Supabase.instance.client.from('overtime_requests').insert({
        'user_id': Supabase.instance.client.auth.currentUser!.id,
        'employee_id': widget.userData['id'],
        'start_time': startDateTime.toIso8601String(),
        'end_time': endDateTime.toIso8601String(),
        'duration_hours': durationInHours,
        'reason': _reasonCtrl.text,
        'status': 'pending',
        'notes': null,
      });

      // --- PENGIRIMAN NOTIFIKASI KINI DITANGANI OLEH SUPABASE EDGE FUNCTION ---
      // (Kode pencarian token dan role atasan dihilangkan dari sisi klien/Flutter)

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
            content: Text(
                "Pengajuan Lembur berhasil dikirim & Atasan telah diberitahu!"),
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
    return Stack(
      children: [
        Container(
          height: 420,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.blue.shade900,
                Colors.blue.shade400,
                Colors.grey.shade100,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
        Column(
          children: [
            // --- FORM PENGAJUAN LEMBUR (TETAP SEPERTI ASLINYA) ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 8,
                shadowColor: Colors.black.withOpacity(0.3),
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
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 15),
                      ElevatedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          _selectedDate == null
                              ? "Pilih Tanggal Mulai Lembur"
                              : DateFormat('dd-MM-yyyy').format(_selectedDate!),
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
                              icon: const Icon(Icons.access_time_filled,
                                  size: 18),
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
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
            const SizedBox(height: 5),

            // --- RIWAYAT LEMBUR & FITUR LAPORAN ---
            Expanded(
              child: RiwayatLemburList(
                key: _riwayatKey,
                userId: Supabase.instance.client.auth.currentUser!.id,
                userData: widget.userData, // Pass userData untuk nama di PDF
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// --- KOMPONEN RIWAYAT LEMBUR (DENGAN EXPORT PDF & KOLOM APPROVED BY) ---
// ============================================================================
class RiwayatLemburList extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> userData; // Digunakan untuk nama di PDF

  const RiwayatLemburList({
    Key? key,
    required this.userId,
    required this.userData,
  }) : super(key: key);

  @override
  _RiwayatLemburListState createState() => _RiwayatLemburListState();
}

class _RiwayatLemburListState extends State<RiwayatLemburList> {
  List<Map<String, dynamic>> _riwayatList = [];
  Map<int, String> _approverNames = {};
  bool _isLoading = true;
  bool _isExporting = false; // Indikator loading saat memproses PDF

  // State untuk filter tanggal (Hanya untuk PDF)
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadData(); // Load 15 data terbaru untuk UI
  }

  String _formatTanggalCantik(String? tgl) {
    if (tgl == null || tgl == '-' || tgl == 'null') return '-';
    try {
      String datePart =
          tgl.contains('T') ? tgl.split('T')[0] : tgl.split(' ')[0];
      DateTime dt = DateTime.parse(datePart);
      return DateFormat('dd-MM-yyyy').format(dt);
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

  // Fungsi asli: Hanya untuk menampilkan 15 riwayat terbaru di UI
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('overtime_requests')
          .select('*')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false)
          .limit(15);

      Set<int> approverIds = {};
      for (var row in data) {
        if (row['approved_by'] != null) {
          int? parsedId = int.tryParse(row['approved_by'].toString());
          if (parsedId != null) approverIds.add(parsedId);
        }
      }

      Map<int, String> tempNames = {};
      if (approverIds.isNotEmpty) {
        final approvers = await Supabase.instance.client
            .from('employees')
            .select('id, full_name');

        for (var a in approvers) {
          int empId = int.parse(a['id'].toString());
          if (approverIds.contains(empId)) {
            tempNames[empId] = a['full_name'].toString();
          }
        }
      }

      if (mounted) {
        setState(() {
          _riwayatList = List<Map<String, dynamic>>.from(data);
          _approverNames = tempNames;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error load riwayat: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- FUNGSI EXPORT PDF (Tarik Data Sesuai Tanggal Khusus Untuk PDF) ---
  Future<void> _exportToPDF() async {
    setState(() => _isExporting = true);

    try {
      // 1. Tarik data dari database sesuai rentang tanggal yang dipilih
      final startStr = DateFormat('yyyy-MM-dd').format(_startDate);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate);

      final dataLaporan = await Supabase.instance.client
          .from('overtime_requests')
          .select('*')
          .eq('user_id', widget.userId)
          .gte('created_at', '${startStr}T00:00:00')
          .lte('created_at', '${endStr}T23:59:59')
          .order('created_at', ascending: true);

      if (dataLaporan.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    "Tidak ada data lembur pada rentang tanggal tersebut.")),
          );
        }
        setState(() => _isExporting = false);
        return;
      }

      // 2. Tarik nama approver khusus untuk data PDF ini
      Set<int> approverIds = {};
      for (var row in dataLaporan) {
        if (row['approved_by'] != null) {
          int? parsedId = int.tryParse(row['approved_by'].toString());
          if (parsedId != null) approverIds.add(parsedId);
        }
      }

      Map<int, String> namaApproverPdf = {};
      if (approverIds.isNotEmpty) {
        final approvers = await Supabase.instance.client
            .from('employees')
            .select('id, full_name');

        for (var a in approvers) {
          int empId = int.parse(a['id'].toString());
          if (approverIds.contains(empId)) {
            namaApproverPdf[empId] = a['full_name'].toString();
          }
        }
      }

      // 3. Buat file PDF
      final pdf = pw.Document();
      double totalKumulatif = 0.0;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Laporan Pekerjaan Lembur',
                        style: pw.TextStyle(
                            fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text(
                        'Nama Karyawan: ${widget.userData['full_name'] ?? '-'}',
                        style: pw.TextStyle(fontSize: 12)),
                    pw.Text(
                        'Periode: ${DateFormat('dd MMM yyyy').format(_startDate)} s/d ${DateFormat('dd MMM yyyy').format(_endDate)}',
                        style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(
                // MENAMBAHKAN HEADER APPROVED BY
                headers: [
                  'No',
                  'Tanggal',
                  'Pekerjaan Lembur',
                  'Mulai',
                  'Selesai',
                  'Total Jam',
                  'Status',
                  'Approved By'
                ],
                data: List<List<String>>.generate(dataLaporan.length, (index) {
                  final item = dataLaporan[index];
                  totalKumulatif += double.tryParse(
                          item['duration_hours']?.toString() ?? '0') ??
                      0.0;

                  String appName = '-';
                  if (item['approved_by'] != null) {
                    int? aId = int.tryParse(item['approved_by'].toString());
                    if (aId != null && namaApproverPdf.containsKey(aId)) {
                      appName = namaApproverPdf[aId]!;
                    }
                  }

                  return [
                    '${index + 1}',
                    _formatTanggalCantik(item['start_time']),
                    item['reason'] ?? item['description'] ?? '-',
                    _formatJam(item['start_time']),
                    _formatJam(item['end_time']),
                    '${item['duration_hours'] ?? '-'}',
                    (item['status'] ?? 'Pending').toString().toUpperCase(),
                    appName, // MEMASUKKAN DATA APPROVED BY
                  ];
                }),
                headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                    color: PdfColors.white),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.blue800),
                cellStyle: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(
                      'Total Keseluruhan Jam Lembur: ${totalKumulatif.toStringAsFixed(1)} Jam',
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ];
          },
        ),
      );

      // 4. Print / Bagikan PDF
      String empName =
          (widget.userData['full_name'] ?? 'karyawan').replaceAll(' ', '_');
      String dateStartStr = DateFormat('ddMMyy').format(_startDate);
      String dateEndStr = DateFormat('ddMMyy').format(_endDate);
      String fileName = 'Lembur_${empName}_${dateStartStr}_${dateEndStr}.pdf';

      await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Gagal ekspor PDF: $e"),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- SISIPAN BARIS FILTER & TOMBOL UNDUH PDF ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    "${DateFormat('dd/MM/yy').format(_startDate)} - ${DateFormat('dd/MM/yy').format(_endDate)}",
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      initialDateRange:
                          DateTimeRange(start: _startDate, end: _endDate),
                    );
                    if (picked != null) {
                      setState(() {
                        _startDate = picked.start;
                        _endDate = picked.end;
                      });
                      // Tidak memanggil _loadData() di sini agar UI riwayat tetap utuh!
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: _isExporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text("Unduh", style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isExporting ? null : _exportToPDF,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // --- DAFTAR RIWAYAT ASLI (TETAP MENAMPILKAN DEFAULT 15 DATA) ---
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _riwayatList.isEmpty
                  ? const Center(child: Text("Belum ada riwayat lembur"))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: _riwayatList.length,
                      itemBuilder: (context, index) {
                        final row = _riwayatList[index];
                        final status = (row['status'] ?? 'PENDING')
                            .toString()
                            .toUpperCase();

                        Color statusColor = Colors.orange;
                        if (status == 'APPROVED' || status == 'DISETUJUI')
                          statusColor = Colors.green;
                        if (status == 'REJECTED' || status == 'DITOLAK')
                          statusColor = Colors.red;

                        String approver = '';
                        if (row['approved_by'] != null) {
                          int? appId =
                              int.tryParse(row['approved_by'].toString());
                          if (appId != null)
                            approver = _approverNames[appId] ?? '';
                        }

                        String jamMulai =
                            _formatJam(row['start_time']?.toString());
                        String jamSelesai =
                            _formatJam(row['end_time']?.toString());
                        String durasi = _hitungDurasi(
                            row['start_time']?.toString(),
                            row['end_time']?.toString());

                        return Card(
                          margin: const EdgeInsets.only(bottom: 9),
                          child: ListTile(
                            dense: true,
                            title: const Text("Lembur",
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                    "${_formatTanggalCantik(row['overtime_date'] ?? row['start_time'])} \n$jamMulai - $jamSelesai WIB $durasi",
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(
                                    "Pekerjaan: ${row['reason'] ?? row['description'] ?? '-'}",
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic)),
                                if (status != 'PENDING' &&
                                    approver.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text("Approved by: $approver",
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.blue.shade800,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: statusColor)),
                              child: Text(status,
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: statusColor,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ============================================================================
// --- TAB MANAGER APPROVAL ---
// ============================================================================
class ManagerApprovalTab extends StatefulWidget {
  final int managerId;
  final int departmentId;
  final String managerRole;

  const ManagerApprovalTab({
    Key? key,
    required this.managerId,
    required this.departmentId,
    required this.managerRole,
  }) : super(key: key);

  @override
  _ManagerApprovalTabState createState() => _ManagerApprovalTabState();
}

class _ManagerApprovalTabState extends State<ManagerApprovalTab> {
  String _formatTanggalCantik(String? tgl) {
    if (tgl == null || tgl == '-' || tgl == 'null') return '-';
    try {
      String datePart =
          tgl.contains('T') ? tgl.split('T')[0] : tgl.split(' ')[0];
      DateTime dt = DateTime.parse(datePart);
      return DateFormat('dd-MM-yyyy').format(dt);
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

  Future<List<Map<String, dynamic>>> _fetchDataCuti() async {
    // 1. Ambil semua pegawai di departemen yang sama
    final empData = await Supabase.instance.client
        .from('employees')
        .select('id, full_name, position_id')
        .eq('department_id', widget.departmentId);

    final posData =
        await Supabase.instance.client.from('positions').select('id, name');

    Map<int, String> posMap = {};
    for (var p in posData) posMap[p['id']] = p['name'].toString().toLowerCase();

    String myRole = widget.managerRole.toLowerCase();
    Map<String, String> validEmpMap = {};

    for (var e in empData) {
      String empIdStr = e['id'].toString();
      if (empIdStr == widget.managerId.toString())
        continue; // Jangan masukkan diri sendiri

      String targetRole = posMap[e['position_id']] ?? '';
      bool isTargetAdmin = targetRole.contains('admin');
      bool isTargetManager = targetRole.contains('manager');
      bool isTargetSupervisor = targetRole.contains('supervisor');

      // --- PENERAPAN RULE HIERARKI ---
      if (myRole.contains('admin')) {
        // Admin bisa melihat semua staff, supervisor, dan manager di departemen ini
        validEmpMap[empIdStr] = e['full_name'].toString();
      } else if (myRole.contains('manager')) {
        // Manager HANYA boleh melihat Supervisor dan Staff (bukan sesama manager/admin)
        if (!isTargetAdmin && !isTargetManager) {
          validEmpMap[empIdStr] = e['full_name'].toString();
        }
      } else if (myRole.contains('supervisor')) {
        // Supervisor HANYA boleh melihat Staff (bukan supervisor, manager, atau admin)
        if (!isTargetAdmin && !isTargetManager && !isTargetSupervisor) {
          validEmpMap[empIdStr] = e['full_name'].toString();
        }
      }
    }

    final reqData = await Supabase.instance.client
        .from('leave_requests')
        .select('*')
        .order('created_at', ascending: false);

    List<Map<String, dynamic>> finalData = [];
    for (var req in reqData) {
      String empId = req['employee_id'].toString();
      // Pastikan pengajuan berasal dari pegawai yang valid sesuai hierarki & departemen
      if (validEmpMap.containsKey(empId)) {
        var row = Map<String, dynamic>.from(req);
        row['full_name'] = validEmpMap[empId];
        finalData.add(row);
      }
    }
    return finalData;
  }

  Future<List<Map<String, dynamic>>> _fetchDataLembur() async {
    final empData = await Supabase.instance.client
        .from('employees')
        .select('id, full_name, position_id')
        .eq('department_id', widget.departmentId);

    final posData =
        await Supabase.instance.client.from('positions').select('id, name');

    Map<int, String> posMap = {};
    for (var p in posData) posMap[p['id']] = p['name'].toString().toLowerCase();

    String myRole = widget.managerRole.toLowerCase();
    Map<String, String> validEmpMap = {};

    for (var e in empData) {
      String empIdStr = e['id'].toString();
      if (empIdStr == widget.managerId.toString()) continue;

      String targetRole = posMap[e['position_id']] ?? '';
      bool isTargetAdmin = targetRole.contains('admin');
      bool isTargetManager = targetRole.contains('manager');
      bool isTargetSupervisor = targetRole.contains('supervisor');

      // --- PENERAPAN RULE HIERARKI ---
      if (myRole.contains('admin')) {
        validEmpMap[empIdStr] = e['full_name'].toString();
      } else if (myRole.contains('manager')) {
        if (!isTargetAdmin && !isTargetManager) {
          validEmpMap[empIdStr] = e['full_name'].toString();
        }
      } else if (myRole.contains('supervisor')) {
        if (!isTargetAdmin && !isTargetManager && !isTargetSupervisor) {
          validEmpMap[empIdStr] = e['full_name'].toString();
        }
      }
    }

    final reqData = await Supabase.instance.client
        .from('overtime_requests')
        .select('*')
        .order('created_at', ascending: false);

    List<Map<String, dynamic>> finalData = [];
    for (var req in reqData) {
      String empId = req['employee_id'].toString();
      if (validEmpMap.containsKey(empId)) {
        var row = Map<String, dynamic>.from(req);
        row['full_name'] = validEmpMap[empId];
        finalData.add(row);
      }
    }
    return finalData;
  }

  Future<void> _updateStatusCuti(int id, String newStatus, String leaveType,
      String? userId, String startDate, String endDate) async {
    try {
      await Supabase.instance.client.from('leave_requests').update(
          {'status': newStatus, 'approved_by': widget.managerId}).eq('id', id);

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
            'remaining_leave': 12 - durasi
          });
        } else {
          int currentUsed = balanceData['used_leave'] ?? 0;
          int currentRemaining = balanceData['remaining_leave'] ?? 0;
          await Supabase.instance.client.from('leave_balance').update({
            'used_leave': currentUsed + durasi,
            'remaining_leave': currentRemaining - durasi
          }).eq('user_id', userId);
        }
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Berhasil memproses pengajuan!")));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _updateStatusLembur(
      int id, String newStatus, dynamic employeeId, double durasi) async {
    try {
      await Supabase.instance.client.from('overtime_requests').update(
          {'status': newStatus, 'approved_by': widget.managerId}).eq('id', id);

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
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lembur berhasil diproses!")));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  Widget _buildDaftarPersetujuanCuti() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchDataCuti(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty)
          return const Center(child: Text("Tidak ada pengajuan cuti."));

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
              color: Colors.grey.shade50,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.grey.shade300, width: 1)),
              child: ListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                title: Text("$empName • ${row['leave_type'] ?? 'Cuti'}",
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                        "${_formatTanggalCantik(row['start_date'])} s/d ${_formatTanggalCantik(row['end_date'])}",
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text("Alasan: ${row['reason'] ?? '-'}",
                        style: const TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Colors.black54)),
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
                                      row['end_date']),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red),
                                      minimumSize: const Size(0, 32),
                                      padding: EdgeInsets.zero),
                                  child: const Text("Tolak",
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: ElevatedButton(
                                  onPressed: () => _updateStatusCuti(
                                      row['id'],
                                      'approved',
                                      row['leave_type'],
                                      row['user_id']?.toString(),
                                      row['start_date'],
                                      row['end_date']),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(0, 32),
                                      padding: EdgeInsets.zero),
                                  child: const Text("Setujui",
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)))),
                        ],
                      ),
                    ],
                  ],
                ),
                trailing: rawStatus == 'pending'
                    ? null
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: statusColor, width: 1.2)),
                        child: Text(statusText,
                            style: TextStyle(
                                fontSize: 10,
                                color: statusColor,
                                fontWeight: FontWeight.bold))),
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
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty)
          return const Center(child: Text("Tidak ada pengajuan lembur."));

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
                row['start_time']?.toString(), row['end_time']?.toString());

            return Card(
              color: Colors.grey.shade50,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.grey.shade300, width: 1)),
              child: ListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                title: Text("$empName • Lembur",
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                        "${_formatTanggalCantik(row['overtime_date'] ?? row['start_time'])} \n$jamMulai - $jamSelesai WIB $durasi",
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text(
                        "Pekerjaan: ${row['reason'] ?? row['description'] ?? '-'}",
                        style: const TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Colors.black54)),
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
                                      double.tryParse(row['duration_hours']
                                                  ?.toString() ??
                                              '0') ??
                                          0.0),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red),
                                      minimumSize: const Size(0, 32),
                                      padding: EdgeInsets.zero),
                                  child: const Text("Tolak",
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: ElevatedButton(
                                  onPressed: () => _updateStatusLembur(
                                      row['id'],
                                      'approved',
                                      row['employee_id'],
                                      double.tryParse(row['duration_hours']
                                                  ?.toString() ??
                                              '0') ??
                                          0.0),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(0, 32),
                                      padding: EdgeInsets.zero),
                                  child: const Text("Setujui",
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)))),
                        ],
                      ),
                    ],
                  ],
                ),
                trailing: rawStatus == 'pending'
                    ? null
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: statusColor, width: 1.2)),
                        child: Text(statusText,
                            style: TextStyle(
                                fontSize: 10,
                                color: statusColor,
                                fontWeight: FontWeight.bold))),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 420,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.blue.shade900,
                Colors.blue.shade400,
                Colors.grey.shade100,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
        DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const TabBar(
                    labelColor: Colors.blue,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Colors.blue,
                    tabs: [
                      Tab(text: "Approval Cuti"),
                      Tab(text: "Approval Lembur"),
                    ],
                  ),
                ),
              ),
              Expanded(
                  child: TabBarView(children: [
                _buildDaftarPersetujuanCuti(),
                _buildDaftarPersetujuanLembur()
              ])),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// --- TAB 3: PROFIL KARYAWAN ---
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
  bool _isEditing = false;

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
  String? _selectedEducation;
  String? _selectedGender;
  String _selectedStatus = 'Single';
  bool _isSaving = false;

  String? _profileImageUrl;
  bool _isUploadingPhoto = false;

  DateTime? _parseDateAman(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty || dateStr == 'null')
      return null;
    try {
      if (dateStr.contains('-')) {
        var parts = dateStr.split('-');
        if (parts.length == 3) {
          if (parts[2].length == 4) {
            return DateTime(
              int.parse(parts[2]),
              int.parse(parts[1]),
              int.parse(parts[0]),
            );
          } else if (parts[0].length == 4) {
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

  @override
  void initState() {
    super.initState();
    _loadDataToForm();
  }

  @override
  void didUpdateWidget(ProfilKaryawanTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userData != oldWidget.userData) {
      _loadDataToForm();
    }
  }

  void _loadDataToForm() {
    _nameCtrl.text = widget.userData['full_name'] ?? '';
    _birthPlaceCtrl.text = widget.userData['birth_place'] ?? '';
    _religionCtrl_init();
    _genderCtrl_init();

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

    _birthDate = _parseDateAman(widget.userData['birth_date']?.toString());
    _spouseBirthDate = _parseDateAman(
      widget.userData['spouse_birth_date']?.toString(),
    );

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
            ci.birthDate = _parseDateAman(child['birth_date']?.toString());

            _childrenInputs.add(ci);
          }
        }
      } catch (e) {
        debugPrint("Gagal load data anak: $e");
      }
    }

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

  void _genderCtrl_init() {
    final gender = widget.userData['gender'];
    if (['Laki-laki', 'Perempuan'].contains(gender)) {
      _selectedGender = gender;
    } else {
      _selectedGender = null;
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
              'birth_date': c.birthDate != null
                  ? DateFormat('yyyy-MM-dd').format(c.birthDate!)
                  : null,
            },
          )
          .toList();

      await Supabase.instance.client.from('employees').update({
        'full_name': _nameCtrl.text,
        'birth_place': _birthPlaceCtrl.text,
        'birth_date': _birthDate != null
            ? DateFormat('yyyy-MM-dd').format(_birthDate!)
            : null,
        'gender': _selectedGender,
        'religion': _selectedReligion,
        'marital_status': _selectedStatus,
        'ktp_number': _ktpCtrl.text,
        'npwp_number': _npwpCtrl.text,
        'address_ktp': _addrKtpCtrl.text,
        'address_now': _addrNowCtrl.text,
        'phone': _phoneCtrl.text,
        'education': _selectedEducation,
        'spouse_name': _spouseCtrl.text,
        'spouse_birth_date': _spouseBirthDate != null
            ? DateFormat('yyyy-MM-dd').format(_spouseBirthDate!)
            : null,
        'children_data': childrenJson,
        'emergency_name': _emerNameCtrl.text,
        'emergency_phone': _emerPhoneCtrl.text,
      }).eq('id', widget.userData['id']);

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

  // --- UPDATE: Mengubah struktur dari SingleChildScrollView -> Stack > Column ---
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 420,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0D47A1),
                const Color(0xFF1E88E5),
                Colors.grey.shade100,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
        Column(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + 15,
                20,
                15,
              ),
              alignment: Alignment.centerLeft,
              child: const Text(
                "Profil Karyawan",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 1,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    children: [
                      Card(
                        elevation: 10,
                        shadowColor: Colors.black.withOpacity(0.3),
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
                              Builder(
                                builder: (context) {
                                  String divisi = widget.userData['dept_name']
                                          ?.toString() ??
                                      '-';
                                  String jabatan = widget
                                          .userData['jabatan_name']
                                          ?.toString() ??
                                      '-';

                                  String rawJoinDate = widget
                                          .userData['join_date']
                                          ?.toString() ??
                                      '';
                                  String joinDateFormatted = "-";

                                  if (rawJoinDate.isNotEmpty &&
                                      rawJoinDate != 'null') {
                                    try {
                                      String datePart =
                                          rawJoinDate.contains('T')
                                              ? rawJoinDate.split('T')[0]
                                              : rawJoinDate.split(' ')[0];
                                      DateTime dt = DateTime.parse(datePart);
                                      joinDateFormatted =
                                          DateFormat('dd MMM yyyy', 'id_ID')
                                              .format(dt);
                                    } catch (e) {
                                      joinDateFormatted = rawJoinDate;
                                    }
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8.0,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Text(
                                                "Divisi",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade500,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                divisi,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade800,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          height: 25,
                                          width: 1,
                                          color: Colors.grey.shade300,
                                        ),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Text(
                                                "Jabatan",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade500,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                jabatan,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade800,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          height: 25,
                                          width: 1,
                                          color: Colors.grey.shade300,
                                        ),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Text(
                                                "Join Date",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade500,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                joinDateFormatted,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 12,
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
                              leading: const Icon(
                                Icons.person_outline,
                                color: Colors.blue,
                              ),
                              title: const Text(
                                "Data Diri",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              maintainState: true,
                              childrenPadding: const EdgeInsets.all(16),
                              children: [
                                _buildField("Nama Lengkap", _nameCtrl),
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
                                  "Jenis Kelamin",
                                  _selectedGender,
                                  ['Laki-laki', 'Perempuan'],
                                  (val) =>
                                      setState(() => _selectedGender = val),
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
                                    'Konghucu',
                                    'Lainnya',
                                  ],
                                  (val) =>
                                      setState(() => _selectedReligion = val),
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
                                  (val) =>
                                      setState(() => _selectedEducation = val),
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
                                  fontSize: 13,
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
                                  (val) =>
                                      setState(() => _selectedStatus = val!),
                                ),
                                if (_selectedStatus != 'Single') ...[
                                  _buildField("Nama Suami/Istri", _spouseCtrl),
                                  _buildDatePickerField(
                                    "Tanggal Lahir Suami/Istri",
                                    _spouseBirthDate,
                                    () async {
                                      final picked = await _pickDate(
                                        _spouseBirthDate,
                                      );
                                      if (picked != null)
                                        setState(
                                            () => _spouseBirthDate = picked);
                                    },
                                  ),
                                ],
                                const Divider(),
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    "Data Anak",
                                    style: TextStyle(
                                      fontSize: 13,
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
                                ...List.generate(_childrenInputs.length,
                                    (index) {
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
                                                    () => _childrenInputs
                                                        .removeAt(
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
                                                _childrenInputs[index]
                                                    .birthDate,
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
                                      icon:
                                          const Icon(Icons.add_circle_outline),
                                      label: const Text("Tambah Data Anak"),
                                      onPressed: () => setState(
                                        () => _childrenInputs
                                            .add(ChildInputData()),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            ExpansionTile(
                              leading: const Icon(
                                Icons.contact_emergency_outlined,
                                color: Colors.blue,
                              ),
                              title: const Text(
                                "Kontak Darurat",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              childrenPadding: const EdgeInsets.all(16),
                              children: [
                                _buildField("Nama Kontak", _emerNameCtrl),
                                _buildField("Nomor HP", _emerPhoneCtrl),
                              ],
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: _buildActionButtons(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
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
                                color: isFaceRegistered
                                    ? Colors.green
                                    : Colors.orange,
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
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.grey))
                                  : const Text(
                                      "Daftarkan wajah untuk keperluan absensi",
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.red)),
                              trailing: const Icon(Icons.chevron_right,
                                  color: Colors.grey),
                              onTap: () async {
                                var cameraStatus =
                                    await Permission.camera.request();
                                if (!cameraStatus.isGranted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('Izin kamera diperlukan!')));
                                  return;
                                }

                                final cameras = await availableCameras();
                                final frontCamera = cameras.firstWhere(
                                  (cam) =>
                                      cam.lensDirection ==
                                      CameraLensDirection.front,
                                  orElse: () => cameras.first,
                                );

                                final bool? isRegistered = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        RegisterFacePage(camera: frontCamera),
                                  ),
                                );

                                if (isRegistered == true) {
                                  setState(() {});
                                  widget.onProfileUpdated();
                                }
                              },
                            ),
                          );
                        }),
                      if (!_isEditing) const SizedBox(height: 10),
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
                                fontSize: 13,
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
                      if (!_isEditing)
                        Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ListTile(
                            leading:
                                const Icon(Icons.logout, color: Colors.red),
                            title: const Text(
                              "Logout",
                              style: TextStyle(
                                fontSize: 13,
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
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: () async {
                                          Navigator.pop(dialogContext);

                                          // Bersihkan fcm_token saat logout agar tidak bertabrakan
                                          try {
                                            await Supabase.instance.client
                                                .from('employees')
                                                .update({'fcm_token': null}).eq(
                                                    'id',
                                                    widget.userData['id']);
                                          } catch (e) {
                                            debugPrint("Gagal reset token: $e");
                                          }

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
              ),
            ),
          ],
        ),
      ],
    );
  }

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
    String dateStr = date != null ? DateFormat('dd-MM-yyyy').format(date) : "-";
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
                    fontSize: 13,
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
  Future<void> _deleteAnnouncement(int id) async {
    try {
      await Supabase.instance.client
          .from('announcements')
          .delete()
          .eq('id', id);

      Navigator.pop(context);
      setState(() {});

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
                          'dd-MM-yyyy, HH:mm',
                        ).format(DateTime.parse(item['created_at']).toLocal())
                      : '',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const Divider(height: 30),
                Expanded(
                  child: SingleChildScrollView(
                    child: Html(
                      // Mengubah \n menjadi <br> agar enter/baris baru terbaca
                      data: (item['content'] ?? 'Tidak ada deskripsi')
                          .replaceAll('\n', '<br>'),
                      style: {
                        "body": Style(
                          fontSize: FontSize(15.0),
                          lineHeight: LineHeight(1.5),
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
                        ),
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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

              // Membersihkan semua tag HTML (<...>) hanya untuk preview list
              String rawContent = item['content'] ?? '';
              String plainTextPreview =
                  rawContent.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '');

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
                  plainTextPreview, // Gunakan teks yang sudah dibersihkan
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
