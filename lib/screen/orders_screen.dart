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
          .where('status', isEqualTo: 'ready')
          .orderBy('createdAt', descending: true);

      return StreamBuilder<QuerySnapshot>(
        stream: ordersQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки'));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Нет новых заказов'));
          }

          final orders = snapshot.data!.docs;

          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;
              final payment = data['paymentMethod'] ?? '-';
              final createdAt = data['createdAt'] as Timestamp?;
              final time = createdAt != null
                  ? DateFormat('dd.MM.yyyy HH:mm').format(createdAt.toDate())
                  : '';

              final userId = data['userId'] ?? '';
              final shopId = data['shopId'] ?? '';
              final restaurantName = data['restaurantName'] ?? '';

              return FutureBuilder<String>(
                future: _getClientName(data, userId),
                builder: (context, nameSnapshot) {
                  final clientName = nameSnapshot.data ?? 'Загрузка...';

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 3,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(
                        'Заказ №${doc.id.substring(0, 6)}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          Text('Клиент: $clientName'),
                          Text('Оплата: $payment'),
                          Text('Создан: $time'),
                          Text('${getShopLabelById(shopId)}: $restaurantName'),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Новый',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
            return const Center(child: Text('Нет срочных заказов'));
          }

          final orders = snapshot.data!.docs;

          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;

              final createdAt = data['createdAt'] as Timestamp?;
              final time = createdAt != null
                  ? DateFormat('dd.MM.yyyy HH:mm').format(createdAt.toDate())
                  : '';

              final scheduledTime = data['scheduledTime'] as Timestamp?;
              final scheduledTimeStr = scheduledTime != null
                  ? DateFormat('dd.MM.yyyy HH:mm').format(scheduledTime.toDate())
                  : '—';

              final totalCost = data['totalPrice'] ?? data['totalCost'] ?? '-';
              final userId = data['userId'] ?? '';
              final clientPhone = data['clientPhone'] ?? '-';

              return FutureBuilder<String>(
                future: _getClientName(data, userId),
                builder: (context, nameSnapshot) {
                  final clientName = nameSnapshot.data ?? 'Загрузка...';

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 3,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(
                        'Заказ №${doc.id.substring(0, 6)}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          Text('Клиент: $clientName'),
                          Text('Телефон: $clientPhone'),
                          Text('Сумма: $totalCost ₽'),
                          Text('Создан: $time'),
                          Text('Запланировано: $scheduledTimeStr'),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Срочная доставка',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
                    ),
                  );
                },
              );
            },
          );
        },
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
            return const Center(child: Text('Нет городских заказов'));
          }

          final orders = snapshot.data!.docs;

          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;

              final createdAt = data['createdAt'] as Timestamp?;
              final time = createdAt != null
                  ? DateFormat('dd.MM.yyyy HH:mm').format(createdAt.toDate())
                  : '';

              final scheduledTime = data['scheduledTime'] as Timestamp?;
              final scheduledTimeStr = scheduledTime != null
                  ? DateFormat('dd.MM.yyyy HH:mm').format(scheduledTime.toDate())
                  : '—';

              final totalCost = data['totalPrice'] ?? data['totalCost'] ?? '-';
              final userId = data['userId'] ?? '';
              final clientPhone = data['clientPhone'] ?? '-';

              return FutureBuilder<String>(
                future: _getClientName(data, userId),
                builder: (context, nameSnapshot) {
                  final clientName = nameSnapshot.data ?? 'Загрузка...';

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 3,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(
                        'Заказ №${doc.id.substring(0, 6)}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          Text('Клиент: $clientName'),
                          Text('Телефон: $clientPhone'),
                          Text('Сумма: $totalCost ₽'),
                          Text('Создан: $time'),
                          Text('Запланировано: $scheduledTimeStr'),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Город',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
            return const Center(child: Text('Нет межгородских заказов'));
          }

          final orders = snapshot.data!.docs;

          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;

              final createdAt = data['createdAt'] as Timestamp?;
              final time = createdAt != null
                  ? DateFormat('dd.MM.yyyy HH:mm').format(createdAt.toDate())
                  : '';

              final scheduledTime = data['scheduledTime'] as Timestamp?;
              final scheduledTimeStr = scheduledTime != null
                  ? DateFormat('dd.MM.yyyy HH:mm').format(scheduledTime.toDate())
                  : '—';

              final totalCost = data['totalPrice'] ?? data['totalCost'] ?? '-';
              final userId = data['userId'] ?? '';
              final clientPhone = data['clientPhone'] ?? '-';

              return FutureBuilder<String>(
                future: _getClientName(data, userId),
                builder: (context, nameSnapshot) {
                  final clientName = nameSnapshot.data ?? 'Загрузка...';

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 3,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(
                        'Заказ №${doc.id.substring(0, 6)}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          Text('Клиент: $clientName'),
                          Text('Телефон: $clientPhone'),
                          Text('Сумма: $totalCost ₽'),
                          Text('Создан: $time'),
                          Text('Запланировано: $scheduledTimeStr'),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Межгород',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
                    ),
                  );
                },
              );
            },
          );
        },
      );
    }





    Widget _buildPlaceholder(String text) => Center(child: Text(text, style: const TextStyle(fontSize: 16)));

    @override
    Widget build(BuildContext context) {
      final filters = ['Доставка','Срочная доставка','Город', 'Межгород'];

      return Scaffold(
        appBar: AppBar(
          title: const Text('Доступные заказы'),
          backgroundColor: Colors.deepOrange,
        ),
        body: Column(
          children: [
            // Горизонтальные кнопки фильтров
            SizedBox(
              height: 50,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final isSelected = _selectedFilterIndex == index;
                  return ElevatedButton(
                    onPressed: () => setState(() => _selectedFilterIndex = index),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? Colors.deepOrange : Colors.grey[300],
                    ),
                    child: Text(
                      filters[index],
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            // Контент
            Expanded(
              child: _selectedFilterIndex == 0
                  ? _buildDeliveryOrders()
                  : _selectedFilterIndex == 1
                  ? _buildUrgentOrders()
                  : _selectedFilterIndex == 2
                  ? _buildCityOrders()
                  : _selectedFilterIndex == 3
                  ? _buildMejCityOrders()
                  : _buildPlaceholder('Пусто'),
            ),
          ],
        ),
      );
    }
  }
