import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Твои импорты экранов деталей
import 'active_detail.dart'; // Предположим, тут CourierOrderDetailScreen
import 'gorod_detail.dart';
import 'mejgorod_detail.dart';
import 'srok_detail.dart';

class OrdersStatusScreen extends StatefulWidget {
  final String courierId;
  final String courierPhone;

  const OrdersStatusScreen({
    super.key,
    required this.courierId,
    required this.courierPhone,
  });

  @override
  State<OrdersStatusScreen> createState() => _OrdersStatusScreenState();
}

class _OrdersStatusScreenState extends State<OrdersStatusScreen> {
  @override
  Widget build(BuildContext context) {
    // Сортировка по времени принятия (нужен индекс в Firestore)
    final ordersQuery = FirebaseFirestore.instance
        .collection('couriers')
        .doc(widget.courierId)
        .collection('history')
        .where('status', whereIn: ['accepted', 'inProgress'])
        .orderBy('acceptedAt', descending: true);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Активные заказы',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Color(0xFF1E293B)),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: ordersQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Ошибка: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.indigo));
          }

          final orders = snapshot.data!.docs;

          if (orders.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;

              // Определяем данные для карточки
              final type = (data['type'] ?? 'orders').toString();
              final status = data['status'] ?? '';
              final price = data['totalPrice'] ?? data['totalCost'] ?? data['total'] ?? 0;
              final clientName = data['clientName'] ?? 'Без имени';

              return _buildOrderCard(context, doc, type, status, price, clientName);
            },
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, DocumentSnapshot doc, String type, String status, dynamic price, String clientName) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: const Color(0xFF1E293B).withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _navigateToDetail(context, type, doc),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildLeadingIcon(type),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '№${doc.id.substring(0, 6).toUpperCase()}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        clientName,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 8),
                      _statusBadge(status),
                    ],
                  ),
                ),
                Text(
                  '$price Руб',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToDetail(BuildContext context, String type, DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final String userId = data['userId'] ?? '';
    final String orderId = data['orderId'] ?? doc.id;

    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка: Не найден ID пользователя'))
      );
      return;
    }

    String collectionName;
    final String t = type.toLowerCase().trim();

    // ВАЖНО: Названия коллекций должны ТОЧНО совпадать с теми, что в Firebase (регистр!)
    if (t == 'city') {
      collectionName = 'cityOrders';
    } else if (t == 'mejcity') {
      collectionName = 'mejCityOrders';
    } else if (t == 'express' || t == 'delivery') {
      collectionName = 'delivery_orders';
    } else {
      collectionName = 'orders';
    }

    // Ссылка на оригинал заказа в ветке пользователя
    final orderRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection(collectionName)
        .doc(orderId);

    debugPrint("DEBUG: Путь к заказу: users/$userId/$collectionName/$orderId");

    Widget screen;
    // Используем collectionName для выбора нужного экрана
    switch (collectionName) {
      case 'cityOrders':
        screen = GorodOrderDetailScreen(
            orderRef: orderRef, courierId: widget.courierId, courierPhone: widget.courierPhone);
        break;
      case 'mejCityOrders':
        screen = IntercityOrderDetailScreen(
            orderRef: orderRef, courierId: widget.courierId, courierPhone: widget.courierPhone);
        break;
      case 'delivery_orders':
        screen = SrokOrderDetailScreen(
            orderRef: orderRef, courierId: widget.courierId, courierPhone: widget.courierPhone);
        break;
      default:
        screen = CourierOrderDetailScreen(
            orderRef: orderRef, courierId: widget.courierId, courierPhone: widget.courierPhone);
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.layers_clear_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'У вас нет активных заказов',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildLeadingIcon(String type) {
    IconData icon;
    Color color;
    switch (type.toLowerCase()) {
      case 'city':
        icon = Icons.location_city_rounded;
        color = Colors.blue;
        break;
      case 'mejcity':
        icon = Icons.local_shipping_rounded;
        color = Colors.teal;
        break;
      case 'express':
      case 'delivery_orders':
        icon = Icons.bolt_rounded;
        color = Colors.orange;
        break;
      default:
        icon = Icons.shopping_bag_rounded;
        color = Colors.deepPurple;
    }
    return Container(
      width: 52, height: 52,
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
      child: Icon(icon, color: color, size: 28),
    );
  }

  Widget _statusBadge(String status) {
    bool inProgress = status == 'inProgress';
    final Color color = inProgress ? const Color(0xFF3B82F6) : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(
        inProgress ? 'В ПУТИ' : 'ПРИНЯТ',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}