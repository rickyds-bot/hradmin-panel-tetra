import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart'
    as tzData; // <-- Alias dibedakan agar tidak bentrok
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

  Future<void> initialize() async {
    try {
      tzData.initializeTimeZones(); // Menggunakan alias yang benar
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
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint("Notifikasi diklik: ${response.payload}");
        },
      );

      final androidPlugin =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      // Plugin sudah mengurus izin exact alarm secara native, tidak perlu via permission_handler lagi
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();

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

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        const NotificationDetails(
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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );

      debugPrint("Alarm $id sukses dijadwalkan pada: $scheduledDate");
    } catch (e) {
      debugPrint("Gagal menjadwalkan notifikasi ID $id: $e");
    }
  }

  // LOGIKA BARU: Menerima status apakah hari ini sudah absen
  Future<void> setupAbsensiNotifications(
      {bool skipMorning = false, bool skipEvening = false}) async {
    for (int i = 1; i <= 5; i++) {
      bool isToday = DateTime.now().weekday == i;

      await _scheduleWeekly(
        100 + i,
        i,
        8,
        15,
        "Siap-siap Check-in!",
        "15 Menit lagi waktu check-in dimulai. Yuk bersiap!",
        skipToday: skipMorning && isToday,
      );
      await _scheduleWeekly(
        200 + i,
        i,
        8,
        30,
        "Waktunya Check-in!",
        "Sudah jam 08:30, jangan lupa absen pagi sekarang!",
        skipToday: skipMorning && isToday,
      );
      await _scheduleWeekly(
        300 + i,
        i,
        17,
        15,
        "Siap-siap Check-out!",
        "15 Menit lagi waktu check-out. Rapikan pekerjaanmu!",
        skipToday: skipEvening && isToday,
      );
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
  }

  Future<void> onCheckIn() async {
    int hariIni = DateTime.now().weekday;
    if (hariIni >= 1 && hariIni <= 5) {
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
