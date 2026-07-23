import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_app_badger/flutter_app_badger.dart';

class NotificationService {
  // --- Singleton Pattern ---
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // =======================================================
  // 1. INITIALIZE (DIPANGGIL DI main.dart ATAU AWAL APLIKASI)
  // =======================================================
  Future<void> initialize() async {
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));

      var status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await flutterLocalNotificationsPlugin.initialize(initializationSettings);

      // Jalankan listener FCM
      _listenToForegroundNotifications();
    } catch (e) {
      debugPrint("Gagal initialize NotificationService: $e");
    }
  }

  // =======================================================
  // 2. SETUP FCM TOKEN (DIPANGGIL SETELAH LOGIN/DAPAT DATA)
  // =======================================================
  Future<void> setupFCMToken(int employeeId) async {
    try {
      NotificationSettings settings = await FirebaseMessaging.instance
          .requestPermission();

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? fcmToken = await FirebaseMessaging.instance.getToken();

        if (fcmToken != null) {
          await Supabase.instance.client
              .from('employees')
              .update({'fcm_token': fcmToken})
              .eq('id', employeeId);
          debugPrint("FCM Token berhasil disimpan: $fcmToken");
        }

        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
          await Supabase.instance.client
              .from('employees')
              .update({'fcm_token': newToken})
              .eq('id', employeeId);
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
          message.hashCode,
          message.notification!.title,
          message.notification!.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'fcm_channel',
              'Pemberitahuan',
              importance: Importance.max,
              priority: Priority.high,
              channelShowBadge: true,
            ),
          ),
        );
        FlutterAppBadger.updateBadgeCount(1);
      }
    });
  }

  // =======================================================
  // 3. LOGIKA MENCARI HARI & WAKTU (LOCAL NOTIFICATION)
  // =======================================================
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

    // FIX: Menggeser jadwal minimal 1 hari ke depan jika skipToday aktif
    if (skipToday &&
        scheduledDate.day == now.day &&
        scheduledDate.month == now.month) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    // Geser hari sampai menemukan hari kerja yang tepat (Senin-Jumat)
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

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'absensi_channel',
            'Absensi Reminder',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } catch (e) {
      // FIX CRASH: Menangkap error jika Android menolak jadwal (misal karena waktu terlewat)
      debugPrint("Gagal menjadwalkan notifikasi ID $id: $e");
    }
  }

  // =======================================================
  // 4. JADWALKAN SEMUA ABSENSI
  // =======================================================
  Future<void> setupAbsensiNotifications() async {
    for (int i = 1; i <= 5; i++) {
      await _scheduleWeekly(
        100 + i,
        i,
        8,
        15,
        "Siap-siap Check-in!",
        "15 Menit lagi waktu check-in dimulai. Yuk bersiap!",
      );
      await _scheduleWeekly(
        200 + i,
        i,
        8,
        30,
        "Waktunya Check-in!",
        "Sudah jam 08:30, jangan lupa absen pagi sekarang!",
      );
      await _scheduleWeekly(
        300 + i,
        i,
        17,
        15,
        "Siap-siap Check-out!",
        "15 Menit lagi waktu check-out. Rapikan pekerjaanmu!",
      );
      await _scheduleWeekly(
        400 + i,
        i,
        17,
        30,
        "Waktunya Check-out!",
        "Kerjaan selesai? Yuk absen pulang!",
      );
    }
  }

  // =======================================================
  // 5. BATALKAN NOTIF (ON CHECK-IN & ON CHECK-OUT)
  // =======================================================
  Future<void> onCheckIn() async {
    int hariIni = DateTime.now().weekday;
    if (hariIni >= 1 && hariIni <= 5) {
      // Timpa jadwal hari ini ke minggu depan dengan mengaktifkan skipToday
      await _scheduleWeekly(
        100 + hariIni,
        hariIni,
        8,
        15,
        "Siap-siap Check-in!",
        "15 Menit lagi waktu check-in. Yuk bersiap!",
        skipToday: true,
      );
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
      // Timpa jadwal hari ini ke minggu depan dengan mengaktifkan skipToday
      await _scheduleWeekly(
        300 + hariIni,
        hariIni,
        17,
        15,
        "Siap-siap Check-out!",
        "15 Menit lagi waktu check-out. Rapikan pekerjaanmu!",
        skipToday: true,
      );
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
}
