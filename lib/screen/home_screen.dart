import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:courier_app/screen/profile_screen.dart';
import 'package:flutter/material.dart';
import 'order_history_screen.dart';
import 'orders_screen.dart';
import 'notification_service.dart'; // Убедись, что импорт верный

// Глобальные переменные для предотвращения дубликатов, как в клиентской части
final Map<String, String> _globalCourierProcessedOrders = {};
List<StreamSubscription>? _courierSubscriptions;

class CourierMainScreen extends StatefulWidget {
  final String courierId;
  final String courierPhone;

  const CourierMainScreen({
    super.key,
    required this.courierId,
    required this.courierPhone,
  });

  @override
  State<CourierMainScreen> createState() => _CourierMainScreenState();
}

class _CourierMainScreenState extends State<CourierMainScreen> {
  int _currentIndex = 0;
  late DateTime _appStartTime;

  final List<GlobalKey<NavigatorState>> _navigatorKeys =
  List.generate(3, (_) => GlobalKey<NavigatorState>());

  @override
  void initState() {
    super.initState();
    // Фиксируем время старта (с запасом 10 сек), чтобы не пищать на старые заказы
    _appStartTime = DateTime.now().subtract(const Duration(seconds: 10));

    // Запускаем прослушку всех категорий
    _startOrderListener();
  }

  @override
  void dispose() {
    // Если хочешь, чтобы уведомления не приходили после выхода из приложения,
    // раскомментируй строку ниже:
    // _courierSubscriptions?.forEach((s) => s.cancel());
    super.dispose();
  }

  // --- ЛОГИКА УВЕДОМЛЕНИЙ ---
  void _startOrderListener() {
    // Очищаем старые подписки, если они были
    _courierSubscriptions?.forEach((s) => s.cancel());
    _courierSubscriptions = [];

    final List<String> categories = [
      'orders',
      'delivery_orders',
      'cityOrders',
      'mejCityOrders'
    ];

    print("📡 [COURIER SERVICE]: Запуск прослушки 4 категорий...");

    for (String cat in categories) {
      final sub = FirebaseFirestore.instance
          .collectionGroup(cat)
          .snapshots()
          .listen((snapshot) {
        _processOrderChanges(snapshot, cat);
      }, onError: (e) => print("❌ Ошибка в $cat: $e"));

      _courierSubscriptions!.add(sub);
    }
  }

  void _processOrderChanges(QuerySnapshot snapshot, String category) {
    for (var change in snapshot.docChanges) {
      final data = change.doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final String orderId = change.doc.id;
      final String status = data['status'] ?? '';

      // Проверяем временную метку
      final Timestamp? timestamp = data['updatedAt'] as Timestamp?
          ?? data['createdAt'] as Timestamp?;

      if (timestamp == null && change.type == DocumentChangeType.added) continue;
      final DateTime eventTime = timestamp?.toDate() ?? DateTime.now();

      // Уникальный ключ для пары "Заказ_Статус"
      final String actionKey = "${orderId}_$status";

      // Если событие свежее и мы о нем еще не уведомляли
      if (eventTime.isAfter(_appStartTime) && !_globalCourierProcessedOrders.containsKey(actionKey)) {
        if (change.type == DocumentChangeType.modified || change.type == DocumentChangeType.added) {

          _globalCourierProcessedOrders[actionKey] = status;
          _triggerPush(category, status, orderId);

          print("🔔 [COURIER]: Поймали обновление! $category | $status");
        }
      }
    }
  }

  void _triggerPush(String category, String status, String orderId) {
    String title = "Обновление в $category";
    String body = "Заказ [$orderId] теперь в статусе: $status";

    switch (status) {
      case 'new':
        title = "🚀 НОВЫЙ ЗАКАЗ!";
        body = "Категория: $category. Срочно проверьте!";
        break;
      case 'preparing':
        title = "👨‍🍳 Готовится";
        body = "Заказ в $category начали готовить";
        break;
      case 'ready':
        title = "✅ ГОТОВ К ВЫДАЧЕ";
        body = "Заказ в $category можно забирать";
        break;
      case 'accepted':
        title = "🤝 Принят";
        body = "Вы подтвердили заказ в $category";
        break;
      case 'inProgress':
        title = "🚚 В ПУТИ";
        body = "Заказ из $category доставляется";
        break;
      case 'delivered':
        title = "🏁 ДОСТАВЛЕНО";
        body = "Заказ успешно завершен. Категория: $category";
        break;
    }

    if (status.isNotEmpty) {
      NotificationService.showNotification(title, body);
    }
  }

  // --- ЛОГИКА НАВИГАЦИИ ---
  Future<bool> _onWillPop() async {
    final isFirstRouteInCurrentTab =
    !await _navigatorKeys[_currentIndex].currentState!.maybePop();
    return isFirstRouteInCurrentTab;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildTabNavigator(0, CourierOrdersScreen(courierId: widget.courierId, courierPhone: widget.courierPhone)),
            _buildTabNavigator(1, OrderHistoryScreen(courierId: widget.courierId)),
            _buildTabNavigator(2, CourierProfileScreen(courierId: widget.courierId, courierPhone: widget.courierPhone)),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.deepOrange,
          unselectedItemColor: Colors.grey,
          onTap: (index) {
            if (index == _currentIndex) {
              _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
            } else {
              setState(() => _currentIndex = index);
            }
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Заказы'),
            BottomNavigationBarItem(icon: Icon(Icons.history), label: 'История'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Профиль'),
          ],
        ),
      ),
    );
  }

  Widget _buildTabNavigator(int index, Widget child) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child),
    );
  }
}