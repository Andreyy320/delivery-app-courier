  import 'package:flutter/material.dart';
  import 'package:cloud_firestore/cloud_firestore.dart';
  import 'package:intl/intl.dart';
  import 'gorod_detail.dart';
  import 'mejgorod_detail.dart';
  import 'srok_detail.dart';
  import 'order_detail.dart';

  class CourierOrdersScreen extends StatefulWidget {
    final String courierId;
    final String courierPhone;

    const CourierOrdersScreen({
      super.key,
      required this.courierId,
      required this.courierPhone,
    });

    @override
    State<CourierOrdersScreen> createState() => _CourierOrdersScreenState();
  }

  class _CourierOrdersScreenState extends State<CourierOrdersScreen> {
    final Map<String, String> _userNamesCache = {};
    int _selectedFilterIndex = 0; // 0 - Доставка, 1 - Срочная доставка, 2 - Город, 3 - Межгород



    Future<String> _getClientName(Map<String, dynamic> orderData, String userId) async {
      if (orderData['clientName'] != null && orderData['clientName'].toString().isNotEmpty) {
        return orderData['clientName'];
      }

      if (userId.isEmpty) return 'Без имени';
      if (_userNamesCache.containsKey(userId)) return _userNamesCache[userId]!;

      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        final name = userDoc.data()?['name'] ?? 'Без имени';
        _userNamesCache[userId] = name;
        return name;
      } catch (e) {
        return 'Без имени';
      }
    }

    Future<void> _takeOrder(DocumentReference orderRef) async {
      try {
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          DocumentSnapshot snap = await transaction.get(orderRef);
          if (!snap.exists) throw Exception('Заказ не найден');

          final data = snap.data() as Map<String, dynamic>;
          final status = data['status'] ?? '';

          // Разрешаем брать только если статус 'new' или 'ready'
          if (status != 'new' && status != 'ready') {
            throw Exception('Этот заказ уже взял другой курьер');
          }

          transaction.update(orderRef, {
            'status': 'accepted',
            'courierId': widget.courierId,
            'courierPhone': widget.courierPhone,
            'acceptedAt': FieldValue.serverTimestamp(),
          });
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Заказ принят!'), backgroundColor: Colors.green),
          );
          // Возвращаемся на список после принятия
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
          );
        }
      }
    }


    String getShopLabelById(String shopId) {
      if (shopId.isEmpty) return 'Заведение';

      // Цветочные магазины
      const floareShops = ['mir_svetov', 'svetok_sentr', 'buket_md'];

      // Рестораны
      const restaurantShops = ['la_vida', 'nuvo', 'georgia', 'la_tokane'];

      // Аптеки
      const aptekas = ['viva_farm', 'sto_letnik', 'e_apteka'];

      // Магазины электроники
      const electronics = ['hitek', 'tiraet', 'tirElKom'];

      // Продуктовые магазины
      const groceryShops = ['garant', 'aquatir', 'xleb'];

      if (floareShops.contains(shopId)) return 'Цветочный магазин';
      if (restaurantShops.contains(shopId)) return 'Ресторан';
      if (aptekas.contains(shopId)) return 'Аптека';
      if (electronics.contains(shopId)) return 'Магазин электроники';
      if (groceryShops.contains(shopId)) return 'Продуктовый магазин';

      return 'Заведение';
    }


    // ===================== Доставка =====================
    // ===================== Доставка (Обновлено с таймером готовности) =====================
    Widget _buildDeliveryOrders() {
      // 1. Формируем запрос: тянем заказы, которые готовятся, готовы или уже ПРИНЯТЫ.
      // ВАЖНО: Если до этого accepted не было в whereIn, Firebase может попросить создать индекс (ссылка будет в логах).
      final ordersQuery = FirebaseFirestore.instance
          .collectionGroup('orders')
          .where('status', whereIn: ['ready', 'preparing', 'accepted'])
          .orderBy('createdAt', descending: true);

      return StreamBuilder<QuerySnapshot>(
        stream: ordersQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки'));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState('Новых заказов пока нет');
          }

          // 2. ФИЛЬТРАЦИЯ (Invisible Personalization):
          // Мы убираем чужие заказы прямо в коде, чтобы курьеры не видели работу друг друга.
          final orders = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final String? orderCourierId = data['courierId'];
            final List<dynamic> rejectedBy = data['rejectedBy'] ?? [];

            // Проверка 1: Ты не нажимал "Скрыть" на этот заказ
            bool isNotRejected = !rejectedBy.contains(widget.courierId);

            // Проверка 2: У заказа нет владельца (пусто или null)
            bool isAvailable = orderCourierId == null || orderCourierId.isEmpty;

            // Проверка 3: Владелец заказа — ТЫ
            bool isMine = orderCourierId == widget.courierId;

            // Показываем если (не скрыт) И (свободен ИЛИ мой)
            return isNotRejected && (isAvailable || isMine);
          }).toList();

          if (orders.isEmpty) return _buildEmptyState('Новых заказов пока нет');

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;

              final String status = data['status'] ?? 'ready';
              final String? orderCourierId = data['courierId'];
              final bool isMyOrder = orderCourierId == widget.courierId;

              final payment = data['paymentMethod'] ?? '-';
              final createdAt = data['createdAt'] as Timestamp?;
              final time = createdAt != null ? DateFormat('HH:mm').format(createdAt.toDate()) : '';
              final estimatedReadyTime = data['estimatedReadyTime'] as Timestamp?;

              final userId = data['userId'] ?? '';
              final shopId = data['shopId'] ?? '';
              final restaurantName = data['restaurantName'] ?? 'Заведение';

              return FutureBuilder<String>(
                future: _getClientName(data, userId),
                builder: (context, nameSnapshot) {
                  final clientName = nameSnapshot.data ?? '...';

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      // Если заказ мой — добавим легкую рамку для удобства
                      border: isMyOrder ? Border.all(color: Colors.deepOrange.withOpacity(0.5), width: 1.5) : null,
                      boxShadow: [
                        BoxShadow(
                          color: isMyOrder ? Colors.deepOrange.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OrderDetailScreen(
                                orderRef: doc.reference,
                                courierId: widget.courierId,
                                courierPhone: widget.courierPhone,
                              ),
                            ),
                          ).then((_) => setState(() {}));
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      getShopLabelById(shopId).toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  // Динамический статус
                                  _buildStatusBadge(status, estimatedReadyTime, time),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      restaurantName,
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                                    ),
                                  ),
                                  if (isMyOrder)
                                    const Icon(Icons.stars, color: Colors.deepOrange, size: 20),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.person_pin_circle_outlined, size: 16, color: Colors.grey[600]),
                                  const SizedBox(width: 6),
                                  Text('Клиент: $clientName', style: TextStyle(color: Colors.grey[700], fontSize: 14)),
                                ],
                              ),
                              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                              Row(
                                children: [
                                  Icon(Icons.payments_outlined, size: 18, color: Colors.green[600]),
                                  const SizedBox(width: 8),
                                  Text(
                                    payment,
                                    style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _getActionText(status, isMyOrder),
                                    style: TextStyle(
                                      color: _getStatusColor(status),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Icon(
                                      Icons.chevron_right_rounded,
                                      color: _getStatusColor(status),
                                      size: 20
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      );
    }

// Вспомогательный виджет для статусов
    Widget _buildStatusBadge(String status, Timestamp? estimatedTime, String createTime) {
      if (status == 'preparing' && estimatedTime != null) {
        return _badge(
          color: Colors.blue,
          icon: Icons.timer_outlined,
          text: 'Будет в ${DateFormat('HH:mm').format(estimatedTime.toDate())}',
        );
      } else if (status == 'ready') {
        return _badge(color: Colors.green, icon: Icons.check_circle_outline, text: 'ГОТОВ');
      } else if (status == 'accepted') {
        return _badge(color: Colors.deepOrange, icon: Icons.assignment_turned_in_outlined, text: 'ВЫ ВЗЯЛИ');
      }
      return Row(
        children: [
          Icon(Icons.access_time, size: 14, color: Colors.grey[400]),
          const SizedBox(width: 4),
          Text(createTime, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      );
    }

    Widget _badge({required Color color, required IconData icon, required String text}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    String _getActionText(String status, bool isMine) {
      if (isMine) {
        if (status == 'preparing') return 'Ждите готовности';
        if (status == 'ready') return 'Можно забирать';
        return 'В работе';
      }
      if (status == 'preparing') return 'Готовится';
      if (status == 'ready') return 'Забрать';
      return 'Детали';
    }

    Color _getStatusColor(String status) {
      if (status == 'preparing') return Colors.blue;
      if (status == 'ready') return Colors.green;
      return Colors.deepOrange;
    }

    Widget _buildUrgentOrders() {
      final UrgentQuery = FirebaseFirestore.instance
          .collectionGroup('delivery_orders')
          .where('status', isEqualTo: 'new')
          .orderBy('createdAt', descending: true);

      return StreamBuilder<QuerySnapshot>(
        stream: UrgentQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки'));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState('Нет срочных заказов');
          }

          final orders = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;

              final createdAt = data['createdAt'] as Timestamp?;
              final time = createdAt != null ? DateFormat('HH:mm').format(createdAt.toDate()) : '';

              final totalCost = data['totalPrice'] ?? data['totalCost'] ?? '-';
              final userId = data['userId'] ?? '';
              final clientPhone = data['clientPhone'] ?? '-';

              return FutureBuilder<String>(
                future: _getClientName(data, userId),
                builder: (context, nameSnapshot) {
                  final clientName = nameSnapshot.data ?? '...';

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SrokOrderDetailScreen(
                                orderRef: doc.reference,
                                courierId: widget.courierId,
                                courierPhone: widget.courierPhone,
                              ),
                            ),
                          ).then((_) => setState(() {}));
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Шапка карточки: Номер и Метка
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'ЗАКАЗ №${doc.id.substring(0, 6).toUpperCase()}',
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  _buildUrgentBadge(), // Синяя метка
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Основная информация: Клиент и Цена
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          clientName,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          clientPhone,
                                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '$totalCost ₽',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.deepOrange,
                                    ),
                                  ),
                                ],
                              ),

                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 1),
                              ),

                              // Нижняя часть: Время
                              Row(
                                children: [
                                  Icon(Icons.access_time_rounded, size: 16, color: Colors.blue[700]),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Создан в $time',
                                    style: TextStyle(
                                      color: Colors.blue[700],
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      );
    }

// Вспомогательный виджет для красивой синей метки
    Widget _buildUrgentBadge() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withOpacity(0.3)),
        ),
        child: const Text(
          'СРОЧНО',
          style: TextStyle(
            color: Colors.blue,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

// Заглушка, если заказов нет
    Widget _buildEmptyState(String text) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bolt_outlined, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(text, style: TextStyle(color: Colors.grey[400], fontSize: 16)),
          ],
        ),
      );
    }

    // ===================== Город =====================
    Widget _buildCityOrders() {
      final CityQuery = FirebaseFirestore.instance
          .collectionGroup('cityOrders')
          .where('status', isEqualTo: 'new')
          .orderBy('createdAt', descending: true);

      return StreamBuilder<QuerySnapshot>(
        stream: CityQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки'));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState('Городских заказов пока нет');
          }

          final orders = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;

              final createdAt = data['createdAt'] as Timestamp?;
              final time = createdAt != null ? DateFormat('HH:mm').format(createdAt.toDate()) : '';

              final scheduledTime = data['scheduledTime'] as Timestamp?;
              final scheduledTimeStr = scheduledTime != null
                  ? DateFormat('HH:mm, dd.MM').format(scheduledTime.toDate())
                  : '—';

              final totalCost = data['totalPrice'] ?? data['totalCost'] ?? '-';
              final userId = data['userId'] ?? '';
              final clientPhone = data['clientPhone'] ?? '-';

              return FutureBuilder<String>(
                future: _getClientName(data, userId),
                builder: (context, nameSnapshot) {
                  final clientName = nameSnapshot.data ?? '...';

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GorodOrderDetailScreen(
                                orderRef: doc.reference,
                                courierId: widget.courierId,
                                courierPhone: widget.courierPhone,
                              ),
                            ),
                          ).then((_) => setState(() {}));
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Шапка: Номер и Метка "Город"
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'ЗАКАЗ №${doc.id.substring(0, 6).toUpperCase()}',
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                    ),
                                    child: const Text(
                                      'ГОРОД',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Инфо: Клиент и Стоимость
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          clientName,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          clientPhone,
                                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '$totalCost ₽',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        'Оплата',
                                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 1),
                              ),

                              // Нижняя строка: Плановое время и Время создания
                              Row(
                                children: [
                                  Icon(Icons.event_available_rounded, size: 16, color: Colors.blue[600]),
                                  const SizedBox(width: 6),
                                  Text(
                                    'На время: $scheduledTimeStr',
                                    style: TextStyle(
                                      color: Colors.blue[800],
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'в $time',
                                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                                  ),
                                  const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      );
    }




    // ===================== Межгород =====================
    Widget _buildMejCityOrders() {
      // Используем collectionGroup только для НОВЫХ заказов (которые еще никто не взял)
      final mejCityQuery = FirebaseFirestore.instance
          .collectionGroup('mejCityOrders')
          .where('status', isEqualTo: 'new')
          .orderBy('createdAt', descending: true);

      return StreamBuilder<QuerySnapshot>(
        stream: mejCityQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint("Ошибка MejCity: ${snapshot.error}");
            return const Center(child: Text('Ошибка загрузки'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState('Межгородских заказов пока нет');
          }

          final orders = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;

              // Вытаскиваем данные с проверкой на null
              final createdAt = data['createdAt'] as Timestamp?;
              final time = createdAt != null ? DateFormat('HH:mm').format(createdAt.toDate()) : '--:--';

              final scheduledTime = data['scheduledTime'] as Timestamp?;
              final scheduledTimeStr = scheduledTime != null
                  ? DateFormat('dd MMM, HH:mm').format(scheduledTime.toDate())
                  : 'Не указано';

              // Исправляем путаницу с ценой (MDL/₽)
              final price = data['totalPrice'] ?? data['totalCost'] ?? data['total'] ?? '0';
              final userId = data['userId'] ?? '';
              final clientPhone = data['clientPhone'] ?? 'Нет телефона';

              return FutureBuilder<String>(
                future: _getClientName(data, userId),
                builder: (context, nameSnapshot) {
                  final clientName = nameSnapshot.data ?? 'Загрузка...';

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          // ВАЖНО: передаем именно doc.reference, полученный из collectionGroup
                          debugPrint("Переход в заказ: ${doc.reference.path}");

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => IntercityOrderDetailScreen(
                                orderRef: doc.reference,
                                courierId: widget.courierId,
                                courierPhone: widget.courierPhone,
                              ),
                            ),
                          ).then((_) => setState(() {}));
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'ЗАКАЗ №${doc.id.substring(0, 6).toUpperCase()}',
                                    style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                  _typeLabel('МЕЖГОРОД', Colors.indigo),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(clientName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                        Text(clientPhone, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  Text('$price MDL', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.indigo)),
                                ],
                              ),
                              const Divider(height: 24),
                              Row(
                                children: [
                                  const Icon(Icons.departure_board_rounded, size: 18, color: Colors.indigo),
                                  const SizedBox(width: 8),
                                  Text('Выезд: $scheduledTimeStr', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      );
    }

// Маленький хелпер для красоты
    Widget _typeLabel(String label, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      );
    }


    @override
    Widget build(BuildContext context) {
      return DefaultTabController(
        length: 4, // Количество вкладок (Доставка, Срочная, Город, Межгород)
        child: Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text(
              'Заказы',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            centerTitle: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0.5,
            // Настраиваем саму панель переключения
            bottom: TabBar(
              onTap: (index) => setState(() => _selectedFilterIndex = index),
              isScrollable: true, // Позволяет скроллить вкладки, если экран узкий
              indicatorColor: Colors.deepOrange,
              indicatorWeight: 3,
              labelColor: Colors.deepOrange,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [
                Tab(text: 'Доставка'),
                Tab(text: 'Срочная'),
                Tab(text: 'Город'),
                Tab(text: 'Межгород'),
              ],
            ),
          ),
          body: Container(
            // Добавляем небольшой градиент сверху, чтобы отделить список
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.grey[100]!],
                stops: const [0.0, 0.1],
              ),
            ),
            child: TabBarView(
              // Чтобы не вылетало и работало плавно
              physics: const BouncingScrollPhysics(),
              children: [
                _buildDeliveryOrders(),
                _buildUrgentOrders(),
                _buildCityOrders(),
                _buildMejCityOrders(),
              ],
            ),
          ),
        ),
      );
    }}
