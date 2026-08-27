import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzData;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Menyimpan hasil pengecekan izin exact alarm terakhir,
  // dipakai untuk memilih schedule mode yang aman (exact vs inexact).
  bool _canScheduleExact = false;

  Future<void> initialize() async {
    try {
      tzData.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('UTC'));
      }

      var status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('ic_notification');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint("Notifikasi diklik: ${response.payload}");
        },
      );

      final androidPlugin =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.requestNotificationsPermission();

      // --- PERBAIKAN UTAMA ---
      // requestExactAlarmsPermission() hanya membuka halaman Settings dan
      // langsung return, TIDAK menunggu user menekan toggle "Izinkan".
      // Karena itu kita cek status SEBENARNYA lewat canScheduleExactNotifications()
      // dan simpan hasilnya, supaya proses schedule tahu harus pakai mode
      // exact atau fallback ke inexact.
      _canScheduleExact =
          await androidPlugin?.canScheduleExactNotifications() ?? false;

      if (!_canScheduleExact) {
        await androidPlugin?.requestExactAlarmsPermission();
        // Cek ulang setelah request (biasanya masih false di titik ini
        // karena user belum sempat menjawab dialog Settings - itu wajar).
        _canScheduleExact =
            await androidPlugin?.canScheduleExactNotifications() ?? false;
        debugPrint(
            "Izin exact alarm setelah request: $_canScheduleExact (jika masih false, jadwal akan pakai mode inexact sampai izin diberikan & app dibuka ulang)");
      }

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'absensi_channel',
        'Absensi Reminder',
        description: 'Notifikasi pengingat check-in dan check-out absensi',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await androidPlugin?.createNotificationChannel(channel);

      _listenToForegroundNotifications();
    } catch (e) {
      debugPrint("Gagal initialize NotificationService: $e");
    }
  }

  Future<void> setupFCMToken(int employeeId) async {
    try {
      NotificationSettings settings =
          await FirebaseMessaging.instance.requestPermission();

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          await Supabase.instance.client
              .from('employees')
              .update({'fcm_token': fcmToken}).eq('id', employeeId);
        }
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
          await Supabase.instance.client
              .from('employees')
              .update({'fcm_token': newToken}).eq('id', employeeId);
        });
      }
    } catch (e) {
      debugPrint("Gagal setup FCM Token: $e");
    }
  }

  void _listenToForegroundNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        flutterLocalNotificationsPlugin.show(
          id: message.hashCode,
          title: message.notification!.title,
          body: message.notification!.body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'fcm_channel',
              'Pemberitahuan',
              importance: Importance.max,
              priority: Priority.high,
              channelShowBadge: true,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
        FlutterAppBadger.updateBadgeCount(1);
      }
    });
  }

  tz.TZDateTime _nextInstanceOfDayAndTime(
    int weekday,
    int hour,
    int minute, {
    bool skipToday = false,
  }) {
    tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (skipToday &&
        scheduledDate.day == now.day &&
        scheduledDate.month == now.month) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    while (scheduledDate.weekday != weekday || scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  Future<void> _scheduleWeekly(
    int id,
    int weekday,
    int hour,
    int minute,
    String title,
    String body, {
    bool skipToday = false,
  }) async {
    try {
      tz.TZDateTime scheduledDate = _nextInstanceOfDayAndTime(
        weekday,
        hour,
        minute,
        skipToday: skipToday,
      );

      // --- PERBAIKAN ---
      // Pilih schedule mode berdasarkan status izin yang SUDAH dikonfirmasi
      // (bukan asumsi selalu granted). Kalau exact alarm belum diizinkan,
      // fallback ke inexact supaya notifikasi tetap terpasang (meski waktunya
      // bisa meleset beberapa menit) daripada gagal total kena exception.
      final scheduleMode = _canScheduleExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'absensi_channel',
            'Absensi Reminder',
            channelDescription: 'Pengingat otomatis waktu absen',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            enableVibration: true,
            playSound: true,
          ),
        ),
        androidScheduleMode: scheduleMode,
        // uiLocalNotificationDateInterpretation dihapus sejak plugin v19.0.0
        // (sudah tidak relevan lagi, dulu hanya untuk iOS < 10).
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );

      debugPrint(
          "Alarm $id sukses dijadwalkan pada: $scheduledDate (mode: $scheduleMode)");
    } catch (e) {
      debugPrint("Gagal menjadwalkan notifikasi ID $id: $e");
    }
  }

  // LOGIKA: Hanya jam 08:30 (Check-in) dan jam 17:30 (Check-out)
  Future<void> setupAbsensiNotifications(
      {bool skipMorning = false, bool skipEvening = false}) async {
    for (int i = 1; i <= 5; i++) {
      bool isToday = DateTime.now().weekday == i;

      // 1. Pengingat Check-in (Jam 08:30)
      await _scheduleWeekly(
        200 + i,
        i,
        8,
        30,
        "Waktunya Check-in!",
        "Sudah jam 08:30, jangan lupa absen pagi sekarang!",
        skipToday: skipMorning && isToday,
      );

      // 2. Pengingat Check-out (Jam 17:30)
      await _scheduleWeekly(
        400 + i,
        i,
        17,
        30,
        "Waktunya Check-out!",
        "Kerjaan selesai? Yuk absen pulang!",
        skipToday: skipEvening && isToday,
      );
    }

    // Bantu verifikasi cepat lewat log setiap kali setup dijalankan.
    await debugPendingNotifications();
  }

  Future<void> onCheckIn() async {
    int hariIni = DateTime.now().weekday;
    if (hariIni >= 1 && hariIni <= 5) {
      await _scheduleWeekly(
        200 + hariIni,
        hariIni,
        8,
        30,
        "Waktunya Check-in!",
        "Sudah jam 08:30, jangan lupa absen pagi!",
        skipToday: true,
      );
    }
  }

  Future<void> onCheckOut() async {
    int hariIni = DateTime.now().weekday;
    if (hariIni >= 1 && hariIni <= 5) {
      await _scheduleWeekly(
        400 + hariIni,
        hariIni,
        17,
        30,
        "Waktunya Check-out!",
        "Kerjaan selesai? Yuk absen pulang!",
        skipToday: true,
      );
    }
  }

  /// Panggil ini kapan saja untuk mengecek notifikasi apa saja yang
  /// benar-benar berhasil terjadwal. Kalau hasilnya kosong padahal
  /// setupAbsensiNotifications() sudah dipanggil, berarti scheduling
  /// gagal (biasanya karena izin exact alarm) - cek log di atasnya.
  Future<void> debugPendingNotifications() async {
    final pending =
        await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    debugPrint("=== Total notifikasi pending: ${pending.length} ===");
    for (var n in pending) {
      debugPrint("id=${n.id} title=${n.title}");
    }
  }

  /// Panggil ini saat app kembali ke foreground (misal dari
  /// AppLifecycleState.resumed di widget utama). Berguna untuk
  /// menjadwalkan ulang begitu user baru saja memberi izin exact alarm
  /// lewat halaman Settings, tanpa harus menutup & membuka app dari awal.
  Future<void> recheckExactAlarmPermissionAndReschedule({
    bool skipMorning = false,
    bool skipEvening = false,
  }) async {
    final androidPlugin =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final nowAllowed =
        await androidPlugin?.canScheduleExactNotifications() ?? false;

    if (nowAllowed != _canScheduleExact) {
      _canScheduleExact = nowAllowed;
      debugPrint(
          "Izin exact alarm berubah menjadi: $_canScheduleExact, menjadwalkan ulang...");
      await setupAbsensiNotifications(
        skipMorning: skipMorning,
        skipEvening: skipEvening,
      );
    }
  }
}
