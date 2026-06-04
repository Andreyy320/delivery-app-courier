import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:courier_app/screen/notification_service.dart'; // Убедись, что путь верный
import 'package:courier_app/screen/offline_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // 🔹 Добавлено для проверки интернета
import 'firebase_options.dart';
import 'screen/login_screen.dart';

// Храним связку "IDЗаказа_Статус", чтобы уведомлять о каждом изменении
final Set<String> _notifiedActions = {};
final List<StreamSubscription> _activeSubscriptions = [];

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("🔥 [FCM BACKGROUND]: Получено сообщение");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print("🚀 [MAIN]: Инициализация Firebase...");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Инициализация твоего сервиса (тот, что с каналом v5)
  await NotificationService.init();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const CourierApp());
}

class CourierApp extends StatefulWidget {
  const CourierApp({super.key});
  @override
  State<CourierApp> createState() => _CourierAppState();
}

class _CourierAppState extends State<CourierApp> {
  DateTime? _appStartTime;

  // 🛠️ ТЕСТОВЫЙ ТУМБЛЕР ДЛЯ ЭМУЛЯТОРА КУРЬЕРА:
  // Поставь true — чтобы принудительно протестировать экран "Нет интернета"
  // Поставь false — для реальной работы сети
  static const bool testOfflineMode = false;

  @override
  void initState() {
    super.initState();
    _appStartTime = DateTime.now().subtract(const Duration(minutes: 1)); // Запас 1 мин
    _setupMessaging();

    // Слушаем вход/выход курьера
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        print("👤 [AUTH]: Курьер вошел: ${user.uid}");
        _startListeningToAllOrders(user.uid);
      } else {
        print("👤 [AUTH]: Выход из системы");
        _stopListening();
      }
    });
  }

  Future<void> _setupMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        NotificationService.showNotification(
          message.notification!.title ?? "Заказ",
          message.notification!.body ?? "",
        );
      }
    });
  }

  void _startListeningToAllOrders(String courierId) {
    _stopListening();
    print("📡 [СЕРВИС]: Запуск прослушки 4-х категорий...");

    // Список всех твоих категорий
    List<String> categories = ['orders', 'delivery_orders', 'cityOrders', 'mejCityOrders'];
    // Статусы, на которые мы хотим пищать
    List<String> targetStatuses = ['new', 'preparing', 'ready', 'accepted', 'inProgress', 'delivered'];

    for (String cat in categories) {
      var sub = FirebaseFirestore.instance
          .collectionGroup(cat)
          .where('status', whereIn: targetStatuses)
          .snapshots()
          .listen((snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
            final data = change.doc.data() as Map<String, dynamic>;
            final String orderId = change.doc.id;
            final String status = data['status'] ?? '';

            // 1. Проверяем rejectedBy
            final List rejectedBy = data['rejectedBy'] ?? [];
            if (rejectedBy.contains(courierId)) continue;

            // 2. Проверяем время (updatedAt или createdAt)
            Timestamp? ts = data['updatedAt'] as Timestamp? ?? data['createdAt'] as Timestamp?;
            DateTime eventTime = ts != null ? ts.toDate() : DateTime.now();

            // Ключ: ID + Статус (чтобы пришло уведомление и на 'ready', и на 'accepted')
            final String actionKey = "${orderId}_$status";

            if (eventTime.isAfter(_appStartTime!) && !_notifiedActions.contains(actionKey)) {
              print("🔔 [EVENT]: $cat | $status | $orderId");
              _notifiedActions.add(actionKey);
              _triggerNotification(status, cat, orderId);
            }
          }
        }
      }, onError: (e) => print("❌ [FIRESTORE ERROR]: $cat -> $e"));

      _activeSubscriptions.add(sub);
    }
  }

  void _triggerNotification(String status, String category, String orderId) {
    String title = "Обновление заказа";
    String body = "Статус: $status (Категория: $category)";

    // Красивые заголовки
    switch (status) {
      case 'new':
        title = "🚀 НОВЫЙ ЗАКАЗ!";
        body = "Категория $category, проверьте список";
        break;
      case 'preparing':
        title = "👨‍🍳 Готовится";
        body = "Заказ $orderId начали готовить";
        break;
      case 'ready':
        title = "✅ ГОТОВ К ВЫДАЧЕ";
        body = "Заказ в $category можно забирать";
        break;
      case 'accepted':
        title = "🤝 Вы приняли заказ";
        body = "Успешно закреплено за вами";
        break;
      case 'inProgress':
        title = "🚚 В ПУТИ";
        body = "Доставка заказа $orderId началась";
        break;
      case 'delivered':
        title = "🏁 ДОСТАВЛЕНО";
        body = "Заказ $orderId завершен!";
        break;
    }

    NotificationService.showNotification(title, body);
  }

  void _stopListening() {
    for (var sub in _activeSubscriptions) { sub.cancel(); }
    _activeSubscriptions.clear();
    _notifiedActions.clear();
    print("🚫 [СЕРВИС]: Остановлено");
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // 🔹 ДОБАВЛЕН ГЛОБАЛЬНЫЙ ПЕРЕХВАТЧИК СЕТИ ДЛЯ КУРЬЕРА
      builder: (context, child) {
        return StreamBuilder<List<ConnectivityResult>>(
          stream: Connectivity().onConnectivityChanged,
          builder: (context, snapshot) {
            print("=== СТАТУС СЕТИ КУРЬЕРА: ${snapshot.data} ===");

            // 1. Ждем инициализации потока при первом старте
            if (snapshot.connectionState == ConnectionState.waiting) {
              return child ?? const SizedBox.shrink();
            }

            // Проверка тумблера искусственного офлайна для эмулятора
            final connectivity = testOfflineMode
                ? <ConnectivityResult>[ConnectivityResult.none]
                : snapshot.data;

            // 2. Если интернета нет — блокируем экраном офлайна
            if (connectivity == null ||
                connectivity.isEmpty ||
                connectivity.contains(ConnectivityResult.none)) {
              return const OfflineScreen();
            }

            // 3. Если всё в порядке — показываем рабочую область курьера
            return child!;
          },
        );
      },
      home: const LoginScreen(),
    );
  }
}