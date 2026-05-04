import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // ИСПОЛЬЗУЕМ НОВЫЙ ID (v10).
  // После замены ID обязательно удали приложение с телефона и установи заново!
  static const String _channelId = 'courier_notifications_v10';
  static const String _channelName = 'Доставка: Срочные заказы';

  static Future<void> init() async {
    // 1. Настройка иконки
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    // 2. Создаем канал с МАКСИМАЛЬНОЙ важностью
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Уведомления о новых заказах и изменении статусов',
      importance: Importance.max, // Делает уведомление всплывающим (heads-up)
      playSound: true,
      enableVibration: true,
      showBadge: true,
      enableLights: true,
    );

    // 3. Регистрация канала
    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
      // Запрос разрешений для Android 13+
      await androidPlugin.requestNotificationsPermission();
    }

    // 4. Инициализация
    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        print("🔔 [КЛИК]: Переход по уведомлению");
      },
    );

    print("🚀 [INIT]: NotificationService готов (Канал: $_channelId)");
  }

  static Future<void> showNotification(String title, String body, {String? payload}) async {
    try {
      // Уникальный ID на основе времени, чтобы уведомления не «схлопывались»
      final int id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await _notificationsPlugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Уведомления курьерской службы',
            importance: Importance.max,
            priority: Priority.high,
            ticker: 'ticker',
            icon: '@mipmap/ic_launcher',

            // ПРИНУДИТЕЛЬНЫЙ ЗВУК И ВИБРАЦИЯ
            playSound: true,
            enableVibration: true,
            // Паттерн: Пауза 0мс, Вибрация 500мс, Пауза 200мс, Вибрация 500мс
            vibrationPattern: Int64List.fromList([0, 500, 200, 500]),

            // Чтобы уведомление всплывало поверх приложений
            fullScreenIntent: false,
            category: AndroidNotificationCategory.status,
            visibility: NotificationVisibility.public,
          ),
        ),
        payload: payload,
      );
      print("✅ [SHOW]: Уведомление отправлено (ID: $id | Status: $title)");
    } catch (e) {
      print("❌ [ERROR]: Не удалось показать уведомление: $e");
    }
  }
}