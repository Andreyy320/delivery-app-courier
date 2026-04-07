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
        final snap = await orderRef.get();
        if (!snap.exists) throw Exception('Заказ не найден');
        final data = snap.data() as Map<String, dynamic>;

        if (data['status'] != 'new') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Этот заказ уже взят другим курьером')),
          );
          return;
        }

        await orderRef.update({
          'status': 'accepted',
          'courierId': widget.courierId,
          'courierPhone': widget.courierPhone,
          'acceptedAt': FieldValue.serverTimestamp(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Заказ принят')),
        );

        setState(() {}); // обновляем экран
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
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
    Widget _buildDeliveryOrders() {
      final ordersQuery = FirebaseFirestore.instance
          .collectionGroup('orders')
          .where('status', isEqualTo: 'ready') // Показываем только готовые к выдаче
          .orderBy('createdAt', descending: true);

      return StreamBuilder<QuerySnapshot>(
        stream: ordersQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки'));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState('Новых заказов из заведений пока нет');
          }

          final orders = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;
              final payment = data['paymentMethod'] ?? '-';
              final createdAt = data['createdAt'] as Timestamp?;
              final time = createdAt != null ? DateFormat('HH:mm').format(createdAt.toDate()) : '';

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
                              // Верхняя строка: Тип заведения и время
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
                                  Row(
                                    children: [
                                      Icon(Icons.access_time, size: 14, color: Colors.grey[400]),
                                      const SizedBox(width: 4),
                                      Text(
                                        time,
                                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Название ресторана/магазина
                              Text(
                                restaurantName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),

                              // Информация о клиенте
                              Row(
                                children: [
                                  Icon(Icons.person_pin_circle_outlined, size: 16, color: Colors.grey[600]),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Клиент: $clientName',
                                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                                  ),
                                ],
                              ),

                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 1),
                              ),

                              // Нижняя строка: Оплата и кнопка перехода
                              Row(
                                children: [
                                  Icon(Icons.payments_outlined, size: 18, color: Colors.green[600]),
                                  const SizedBox(width: 8),
                                  Text(
                                    payment,
                                    style: TextStyle(
                                      color: Colors.green[700],
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Text(
                                    'Детали',
                                    style: TextStyle(
                                      color: Colors.deepOrange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded, color: Colors.deepOrange, size: 20),
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
      final mejCityQuery = FirebaseFirestore.instance
          .collectionGroup('mejCityOrders')
          .where('status', isEqualTo: 'new')
          .orderBy('createdAt', descending: true);

      return StreamBuilder<QuerySnapshot>(
        stream: mejCityQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки'));
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

              final createdAt = data['createdAt'] as Timestamp?;
              final time = createdAt != null ? DateFormat('HH:mm').format(createdAt.toDate()) : '';

              final scheduledTime = data['scheduledTime'] as Timestamp?;
              final scheduledTimeStr = scheduledTime != null
                  ? DateFormat('dd MMM, HH:mm').format(scheduledTime.toDate())
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
                              // Шапка: Номер и Метка "Межгород"
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'ЗАКАЗ №${doc.id.substring(0, 6).toUpperCase()}',
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.indigo.withOpacity(0.3)),
                                    ),
                                    child: const Text(
                                      'МЕЖГОРОД',
                                      style: TextStyle(
                                        color: Colors.indigo,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Основная инфа: Клиент и Большая Цена
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.end,
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
                                        Row(
                                          children: [
                                            const Icon(Icons.phone_iphone, size: 14, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(
                                              clientPhone,
                                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                            ),
                                          ],
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
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                      const Text(
                                        'тариф',
                                        style: TextStyle(color: Colors.grey, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 1),
                              ),

                              // Нижняя строка: Планируемое время
                              Row(
                                children: [
                                  const Icon(Icons.departure_board_rounded, size: 18, color: Colors.indigo),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Выезд запланирован:',
                                        style: TextStyle(color: Colors.grey, fontSize: 11),
                                      ),
                                      Text(
                                        scheduledTimeStr,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
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
