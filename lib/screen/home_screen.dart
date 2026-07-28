import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:courier_app/screen/profile_screen.dart';
import 'package:flutter/material.dart';
import 'Location_Screen.dart';
import 'order_history_screen.dart';
import 'notification_service.dart';
import 'orders_screen.dart';

// Глобальные переменные для предотвращения дубликатов в рамках сессии
final Set<String> _globalCourierProcessedOrders = {};
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

  final List<GlobalKey<NavigatorState>> _navigatorKeys =
  List.generate(3, (_) => GlobalKey<NavigatorState>());

  // --- СВЕТЛЫЙ ДИЗАЙН И АКЦЕНТЫ ---
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color textMuted = Color(0xFF64748B);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color borderColor = Color(0xFFE2E8F0);

  // Флаг, чтобы модалка открывалась строго по одному разу для текущего заказа
  bool _isModalShowing = false;

  @override
  void initState() {
    super.initState();
    // ignore: avoid_print
    print("🚀 [INIT]: CourierMainScreen запущен для курьера ID: ${widget.courierId}");

    // Запускаем централизованную проверку очереди заказов
    _startOrderListeners();

    // 📍 Запускаем фоновый трекинг геолокации курьера
    LocationService.startTracking(widget.courierId);
  }

  @override
  void dispose() {
    // 🛑 Останавливаем трекинг геолокации и подписки при выходе с экрана
    LocationService.stopTracking();
    _courierSubscriptions?.forEach((s) => s.cancel());
    super.dispose();
  }

  // Вспомогательная функция для расчета расстояния в метрах (формула гаверсинусов)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // Радианы
    final c = cos;
    final a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 1000 * 12742 * asin(sqrt(a)); // Результат в метрах
  }

  // --- УМНАЯ ОЧЕРЕДЬ: ЕДИНЫЙ СЛУШАТЕЛЬ ДЛЯ РАСПРЕДЕЛЕНИЯ САМОГО СТАРОГО ЗАКАЗА ---
  void _startOrderListeners() {
    _courierSubscriptions?.forEach((s) => s.cancel());
    _courierSubscriptions = [];

    // ignore: avoid_print
    print("🔔 [COURIER SERVICE]: Запуск централизованного распределения заказов...");

    // Слушаем обычные заказы (реагирует моментально на любые изменения в Firebase)
    final standardSub = FirebaseFirestore.instance
        .collectionGroup('orders')
        .snapshots()
        .listen((_) => _evaluateOrderQueue(), onError: (e) {
      // ignore: avoid_print
      print("❌ Ошибка в прослушке orders: $e");
    });

    // Слушаем индивидуальные доставки
    final deliverySub = FirebaseFirestore.instance
        .collectionGroup('delivery_orders')
        .snapshots()
        .listen((_) => _evaluateOrderQueue(), onError: (e) {
      // ignore: avoid_print
      print("❌ Ошибка в прослушке delivery_orders: $e");
    });

    _courierSubscriptions!.add(standardSub);
    _courierSubscriptions!.add(deliverySub);
  }

  // Глобальный метод оценки очереди: выбирает ВСЕ подходящие заказы, сортирует их по времени и берет СТРОГО ПЕРВЫЙ
  Future<void> _evaluateOrderQueue() async {
    if (!mounted) return;

    // Если у курьера уже открыто модальное окно заказа, не дергаем повторно
    if (_isModalShowing) return;

    try {
      // 1. Проверяем состояние текущего курьера
      final courierRef = FirebaseFirestore.instance.collection('couriers').doc(widget.courierId);
      final currentCourierDoc = await courierRef.get();

      if (!currentCourierDoc.exists) return;
      final currentCourierData = currentCourierDoc.data();

      // Универсальная проверка активности курьера (поддерживает bool, String, int)
      var rawActive = currentCourierData?['active'];
      var rawOnDuty = currentCourierData?['isOnDuty'];
      bool isActive = rawActive == true || rawActive == 'true' || rawActive == 1;
      bool isOnDuty = rawOnDuty == true || rawOnDuty == 'true' || rawOnDuty == 1;

      if (!isActive || !isOnDuty) return;

      final String? activeOrder = currentCourierData?['currentOrderId'];
      if (activeOrder != null && activeOrder.isNotEmpty) {
        bool isOrderStillActive = false;

        try {
          final query1 = await FirebaseFirestore.instance.collectionGroup('orders').get();
          final query2 = await FirebaseFirestore.instance.collectionGroup('delivery_orders').get();

          for (var doc in [...query1.docs, ...query2.docs]) {
            if (doc.id == activeOrder) {
              final status = doc.data()['status']?.toString().toLowerCase() ?? '';
              if (status != 'delivered' && status != 'completed' && status != 'cancelled') {
                isOrderStillActive = true;
              }
              break;
            }
          }
        } catch (_) {
          isOrderStillActive = true;
        }

        if (!isOrderStillActive) {
          await courierRef.update({
            'currentOrderId': FieldValue.delete(),
          });
        } else {
          return;
        }
      }

      // 2. Собираем потенциальные свободные заказы из обоих источников
      List<Map<String, dynamic>> availableOrders = [];

      final ordersQuery = await FirebaseFirestore.instance.collectionGroup('orders').where('status', whereIn: ['new', 'preparing', 'ready']).get();
      final deliveryOrdersQuery = await FirebaseFirestore.instance.collectionGroup('delivery_orders').where('status', whereIn: ['new', 'preparing', 'ready']).get();

      for (var doc in [...ordersQuery.docs, ...deliveryOrdersQuery.docs]) {
        final data = doc.data();
        final String assignedCourier = data['courierId'] ?? '';

        if (assignedCourier.isNotEmpty) continue;

        final List rejectedByList = data['rejectedBy'] ?? [];
        if (rejectedByList.contains(widget.courierId)) continue;

        availableOrders.add({
          'doc': doc,
          'data': data,
          'isDelivery': doc.reference.parent.id == 'delivery_orders',
          'createdAt': data['createdAt'] ?? data['timestamp'] ?? Timestamp.now(),
        });
      }

      if (availableOrders.isEmpty) return;

      // 3. СОРТИРОВКА: Самые старые (ранние) заказы идут первыми!
      availableOrders.sort((a, b) {
        Timestamp timeA = a['createdAt'] is Timestamp ? a['createdAt'] : Timestamp.now();
        Timestamp timeB = b['createdAt'] is Timestamp ? b['createdAt'] : Timestamp.now();
        return timeA.compareTo(timeB);
      });

      // 4. Берем СТРОГО САМЫЙ ПЕРВЫЙ (самый старый) заказ из всей очереди
      final oldestCandidate = availableOrders.first;
      final DocumentReference docRef = oldestCandidate['doc'].reference;
      final Map<String, dynamic> orderData = oldestCandidate['data'];
      final String orderId = docRef.id;
      final bool isDeliveryGroup = oldestCandidate['isDelivery'];
      final String status = orderData['status'] ?? '';

      // 📍 Считаем координаты ресторана/точки сбора
      final String orderType = orderData['type'] ?? orderData['orderType'] ?? orderData['deliveryType'] ?? (isDeliveryGroup ? 'delivery' : 'standard_order');
      double restLat = 0.0;
      double restLng = 0.0;

      if (orderType == 'delivery' || orderType == 'individual' || isDeliveryGroup) {
        final pickupMap = orderData['pickup'] is Map ? orderData['pickup'] as Map<String, dynamic> : null;
        restLat = (pickupMap?['lat'] ?? 0.0) is num ? (pickupMap?['lat'] ?? 0.0).toDouble() : double.tryParse("${pickupMap?['lat']}") ?? 0.0;
        restLng = (pickupMap?['lon'] ?? pickupMap?['lng'] ?? 0.0) is num ? (pickupMap?['lon'] ?? pickupMap?['lng'] ?? 0.0).toDouble() : double.tryParse("${pickupMap?['lon'] ?? pickupMap?['lng']}") ?? 0.0;
      } else {
        restLat = (orderData['restaurantLat'] ?? orderData['pickupLat'] ?? 0.0) is num ? (orderData['restaurantLat'] ?? orderData['pickupLat'] ?? 0.0).toDouble() : double.tryParse("${orderData['restaurantLat'] ?? orderData['pickupLat']}") ?? 0.0;
        restLng = (orderData['restaurantLng'] ?? orderData['pickupLng'] ?? 0.0) is num ? (orderData['restaurantLng'] ?? orderData['pickupLng'] ?? 0.0).toDouble() : double.tryParse("${orderData['restaurantLng'] ?? orderData['pickupLng']}") ?? 0.0;
      }

      // 5. Проверяем кандидатов-курьеров для ЭТОГО конкретного старейшего заказа
      final allCouriersSnap = await FirebaseFirestore.instance.collection('couriers').get();
      List<Map<String, dynamic>> eligibleCouriers = [];

      for (var cDoc in allCouriersSnap.docs) {
        String cId = cDoc.id;
        if (rejectedBy(orderData, cId)) continue;

        final cData = cDoc.data();
        bool isActiveC = cData['active'] == true || cData['active'] == 'true' || cData['active'] == 1;
        bool isOnDutyC = cData['isOnDuty'] == true || cData['isOnDuty'] == 'true' || cData['isOnDuty'] == 1;
        if (!isActiveC || !isOnDutyC) continue;

        String? cCurrentOrder = cData['currentOrderId'];
        if (cCurrentOrder != null && cCurrentOrder.isNotEmpty) continue;

        double cLat = (cData['latitude'] ?? 0.0) is num ? (cData['latitude'] ?? 0.0).toDouble() : 0.0;
        double cLng = (cData['longitude'] ?? 0.0) is num ? (cData['longitude'] ?? 0.0).toDouble() : 0.0;

        double dist = 0.0;
        if (restLat != 0.0 && restLng != 0.0 && cLat != 0.0 && cLng != 0.0) {
          dist = _calculateDistance(cLat, cLng, restLat, restLng);
          if (dist > 50000) continue;
        } else {
          dist = 0.0;
        }

        int priority = int.tryParse("${cData['priority'] ?? '3'}") ?? 3;
        int rating = int.tryParse("${cData['ratingScore'] ?? cData['rating'] ?? '50'}") ?? 50;

        eligibleCouriers.add({
          'id': cId,
          'priority': priority,
          'rating': rating,
          'distance': dist,
        });
      }

      eligibleCouriers.sort((a, b) {
        if (a['priority'] != b['priority']) {
          return (a['priority'] as int).compareTo(b['priority'] as int);
        }
        if (a['rating'] != b['rating']) {
          return (b['rating'] as int).compareTo(a['rating'] as int);
        }
        return (a['distance'] as double).compareTo(b['distance'] as double);
      });

      // 6. Если текущий пользователь — лучший кандидат именно для этого старейшего заказа
      if (eligibleCouriers.isNotEmpty && eligibleCouriers.first['id'] == widget.courierId) {
        final String actionKey = "${orderId}_${status}_displayed";

        if (!_globalCourierProcessedOrders.contains(actionKey)) {
          _globalCourierProcessedOrders.add(actionKey);

          // ignore: avoid_print
          print("🔔 [SMART QUEUE]: Самый старый заказ $orderId предложен курьеру ID: ${widget.courierId}");

          _triggerPush(status, orderType);

          // Показываем окно сразу, используя контекст текущего экрана без ожидания кликов
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isModalShowing) {
              _showIncomingOrderModal(orderData, docRef);
            }
          });
        }
      }
    } catch (err) {
      // ignore: avoid_print
      print("❌ Ошибка в оценке очереди заказов: $err");
    }
  }

  bool rejectedBy(Map<String, dynamic> data, String courierId) {
    final List rejected = data['rejectedBy'] ?? [];
    return rejected.contains(courierId);
  }

  void _triggerPush(String status, String orderType) {
    String title = "🔔 НОВЫЙ ЗАКАЗ!";
    String body = "Поступил новый заказ в обработку";

    if (orderType == 'delivery' || orderType == 'individual') {
      title = "📦 ИНДИВИДУАЛЬНАЯ ДОСТАВКА";
    } else if (orderType == 'standard_order') {
      title = "📋 ОБЫЧНЫЙ ЗАКАЗ";
    }

    if (status == 'preparing') {
      body = "Заведение приняло заказ в работу";
    } else if (status == 'ready') {
      body = "Заказ готов, можно забирать!";
    } else if (status == 'new') {
      body = "Новый заказ ожидает курьера";
    }

    NotificationService.showNotification(title, body);
  }

  // --- ФУНКЦИЯ ИЗМЕНЕНИЯ РЕЙТИНГА КУРЬЕРА (0 - 100 БАЛЛОВ) ---
  Future<void> _updateCourierRating(int delta) async {
    try {
      final courierRef = FirebaseFirestore.instance.collection('couriers').doc(widget.courierId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(courierRef);

        int currentScore = 100;
        if (snapshot.exists && snapshot.data() != null) {
          final data = snapshot.data() as Map<String, dynamic>;
          currentScore = int.tryParse("${data['ratingScore'] ?? data['rating'] ?? 100}") ?? 100;
        }

        int newScore = currentScore + delta;
        if (newScore > 100) newScore = 100;
        if (newScore < 0) newScore = 0;

        transaction.set(courierRef, {
          'ratingScore': newScore,
          'rating': "$newScore",
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      // ignore: avoid_print
      print("⭐ [RATING]: Баллы курьера изменены на $delta");
    } catch (e) {
      // ignore: avoid_print
      print("❌ [RATING ERROR]: Не удалось обновить рейтинг: $e");
    }
  }

  // --- ИНТЕРАКТИВНОЕ МОДАЛЬНОЕ ОКНО С ТАЙМЕРОМ НА 60 СЕКУНД И ТРАНЗАКЦИЕЙ ---
  void _showIncomingOrderModal(Map<String, dynamic> orderData, DocumentReference docRef) {
    if (!mounted || _isModalShowing) return;
    _isModalShowing = true;

    final pickupMap = orderData['pickup'] is Map ? orderData['pickup'] as Map<String, dynamic> : null;
    final dropoffMap = orderData['dropoff'] is Map ? orderData['dropoff'] as Map<String, dynamic> : null;

    final String rawType = (orderData['type'] ?? orderData['orderType'] ?? orderData['deliveryType'] ?? 'standard_order').toString().toLowerCase();

    String restaurantName = '';
    String restaurantAddress = '';

    if (rawType == 'delivery' || rawType == 'individual') {
      restaurantName = orderData['clientName'] ?? pickupMap?['name'] ?? 'Отправитель';
      restaurantAddress = pickupMap?['address'] ?? 'Адрес отправки не указан';
    } else {
      restaurantName = orderData['restaurantName'] ?? orderData['shopName'] ?? pickupMap?['name'] ?? 'Заведение';
      restaurantAddress = pickupMap?['address'] ?? orderData['restaurantAddress'] ?? orderData['pickupAddress'] ?? orderData['addressFrom'] ?? 'Адрес не указан';
    }

    final String dropoffAddress = dropoffMap?['address'] ?? orderData['deliveryAddress'] ?? orderData['addressTo'] ?? 'Адрес назначения';
    final dynamic rawDeliveryPrice = orderData['total_cost'] ?? orderData['deliveryPrice'] ?? orderData['deliveryCost'] ?? orderData['priceDelivery'] ?? 0;
    final String deliveryPriceStr = "$rawDeliveryPrice";

    String typeLabel = 'ОБЫЧНЫЙ ЗАКАЗ';
    Color badgeBgColor = const Color(0xFFDCFCE7);
    Color badgeTextColor = const Color(0xFF166534);

    if (rawType == 'delivery' || rawType == 'individual') {
      typeLabel = '📦 ИНДИВИДУАЛЬНАЯ ДОСТАВКА';
      badgeBgColor = const Color(0xFFE0E7FF);
      badgeTextColor = const Color(0xFF3730A3);
    }

    final String statusText = orderData['status'] == 'ready'
        ? 'Готово к выдаче'
        : (orderData['status'] == 'preparing' ? 'Готовится' : 'Новый');

    int secondsRemaining = 60;
    Timer? countdownTimer;
    bool isActionTaken = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
              if (secondsRemaining > 0) {
                if (mounted) {
                  setStateModal(() {
                    secondsRemaining--;
                  });
                }
              } else {
                timer.cancel();
                if (!isActionTaken && mounted) {
                  isActionTaken = true;
                  _isModalShowing = false;
                  Navigator.pop(dialogContext);

                  _updateCourierRating(-25);
                  docRef.update({
                    'rejectedBy': FieldValue.arrayUnion([widget.courierId]),
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Время вышло! Заказ передан следующему курьеру (-25 баллов)')),
                  );
                }
              }
            });

            return AlertDialog(
              backgroundColor: cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: borderColor, width: 1),
              ),
              title: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeBgColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(
                            color: badgeTextColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: secondsRemaining <= 10 ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '⏱ 0:${secondsRemaining.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: secondsRemaining <= 10 ? const Color(0xFF991B1B) : textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'НОВЫЙ ЗАКАЗ',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 16, color: primaryBlue),
                              const SizedBox(width: 6),
                              Text(
                                'Статус: $statusText',
                                style: const TextStyle(
                                  color: primaryBlue,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Divider(color: borderColor, height: 1),
                          const SizedBox(height: 10),
                          const Text(
                            'ОТКУДА ЗАБРАТЬ:',
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.location_on_rounded, size: 16, color: Colors.redAccent),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      restaurantName,
                                      style: const TextStyle(
                                        color: Color(0xFF0F172A),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      restaurantAddress,
                                      style: const TextStyle(
                                        color: textMuted,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'КУДА ДОСТАВИТЬ:',
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.flag_rounded, size: 16, color: primaryBlue),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  dropoffAddress,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Divider(color: borderColor, height: 1),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'ОПЛАТА ЗА ДОСТАВКУ:',
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  '$deliveryPriceStr руб.',
                                  style: const TextStyle(
                                    color: Color(0xFF166534),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              actions: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isActionTaken ? null : () async {
                          isActionTaken = true;
                          countdownTimer?.cancel();
                          _isModalShowing = false;
                          Navigator.pop(dialogContext);

                          try {
                            bool transactionSuccess = false;

                            await FirebaseFirestore.instance.runTransaction((transaction) async {
                              DocumentSnapshot snapshot = await transaction.get(docRef);
                              if (!snapshot.exists) {
                                throw Exception('Заказ не найден в базе данных');
                              }

                              final dataMap = snapshot.data() as Map<String, dynamic>? ?? {};
                              String existingCourier = dataMap['courierId'] ?? '';
                              if (existingCourier.isNotEmpty) {
                                throw Exception('Заказ уже занят другим курьером');
                              }

                              transaction.update(docRef, {
                                'courierId': widget.courierId,
                                'status': 'accepted',
                                'updatedAt': FieldValue.serverTimestamp(),
                              });

                              DocumentReference courierRef = FirebaseFirestore.instance.collection('couriers').doc(widget.courierId);
                              transaction.update(courierRef, {
                                'currentOrderId': docRef.id,
                                'updatedAt': FieldValue.serverTimestamp(),
                              });

                              DocumentReference historyRef = courierRef.collection('history').doc(docRef.id);
                              transaction.set(historyRef, {
                                ...dataMap,
                                'courierId': widget.courierId,
                                'status': 'accepted',
                                'acceptedAt': FieldValue.serverTimestamp(),
                                'updatedAt': FieldValue.serverTimestamp(),
                              }, SetOptions(merge: true));

                              transactionSuccess = true;
                            });

                            if (transactionSuccess && mounted) {
                              await _updateCourierRating(5);
                            }
                          } catch (ex) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Не удалось взять заказ: $ex')),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'ПРИНЯТЬ (+5 баллов)',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: isActionTaken ? null : () async {
                          isActionTaken = true;
                          countdownTimer?.cancel();
                          _isModalShowing = false;
                          Navigator.pop(dialogContext);

                          await _updateCourierRating(-25);
                          await docRef.update({
                            'rejectedBy': FieldValue.arrayUnion([widget.courierId]),
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textMuted,
                          side: const BorderSide(color: borderColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'ОТКАЗАТЬСЯ (-25 баллов)',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      countdownTimer?.cancel();
      _isModalShowing = false;
    });
  }

  // --- ЛОГИКА НАВИГАЦИИ ---
  Future<bool> _onWillPop() async {
    final navState = _navigatorKeys[_currentIndex].currentState;
    if (navState == null) return true;
    final isFirstRouteInCurrentTab = !await navState.maybePop();
    return isFirstRouteInCurrentTab;
  }

  Widget _buildTab(int index, Widget child) {
    return Offstage(
      offstage: _currentIndex != index,
      child: Navigator(
        key: _navigatorKeys[index],
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (_) => child,
            settings: settings,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final bool shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            _buildTab(0, CourierOrdersScreen(courierId: widget.courierId, courierPhone: widget.courierPhone)),
            _buildTab(1, OrderHistoryScreen(courierId: widget.courierId)),
            _buildTab(2, CourierProfileScreen(
              courierId: widget.courierId,
              courierPhone: widget.courierPhone,
            )),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            if (_currentIndex == index) {
              _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
            } else {
              setState(() {
                _currentIndex = index;
              });
            }
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.list_alt_rounded), label: 'Заказы'),
            BottomNavigationBarItem(icon: Icon(Icons.history_rounded), label: 'История'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Профиль'),
          ],
        ),
      ),
    );
  }
}