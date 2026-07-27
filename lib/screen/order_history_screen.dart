import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// Твои импорты деталей
import 'detail_screen/active_detail.dart';
import 'NO_USED_SCREEN/gorod_detail.dart';
import 'NO_USED_SCREEN/mejgorod_detail.dart';
import 'detail_screen/srok_detail.dart';

class OrderHistoryScreen extends StatelessWidget {
  final String courierId;

  const OrderHistoryScreen({super.key, required this.courierId});

  // Бейдж типа заказа
  Widget _buildTypeBadge(String type) {
    String label;
    Color color;

    switch (type) {
      case 'normal': label = 'ДОСТАВКА'; color = Colors.orange[700]!; break;
      case 'express':
      case 'delivery': label = 'СРОЧНО'; color = Colors.red[800]!; break;
      case 'city': label = 'ГОРОД'; color = Colors.blue[700]!; break;
      case 'mejCity': label = 'МЕЖГОРОД'; color = Colors.teal[700]!; break;
      default: label = 'ЗАКАЗ'; color = Colors.grey[700]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. ФИЛЬТР: Берем только те, где статус 'delivered'
    // 2. СОРТИРОВКА: Самые свежие сверху
    final historyQuery = FirebaseFirestore.instance
        .collection('couriers')
        .doc(courierId)
        .collection('history')
        .where('status', isEqualTo: 'delivered')
        .orderBy('updatedAt', descending: true);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('История заказов', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: historyQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки. Проверьте индексы в консоли.'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_outlined, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('Завершенных заказов нет', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final orders = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;

              final type = data['type'] ?? 'normal';
              final clientName = data['clientName'] ?? 'Без имени';

              // 🔹 ЛОГИКА ЦЕНЫ ДЛЯ ИСТОРИИ КУРЬЕРА:
              // Если это обычная доставка — показываем доход курьера (deliveryPrice).
              // Для остальных типов показываем общую стоимость заказа.
              final displayPrice = (type == 'normal')
                  ? (data['deliveryPrice'] ?? 0)
                  : (data['totalPrice'] ?? data['totalCost'] ?? data['total'] ?? 0);

              final updatedAt = data['updatedAt'] as Timestamp?;
              final dateStr = updatedAt != null
                  ? DateFormat('dd MMM, HH:mm').format(updatedAt.toDate())
                  : '--:--';

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4)),
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
                                  'Заказ №${doc.id.substring(0, 6)}'.toUpperCase(),
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  clientName,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                _buildTypeBadge(type),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // 🔹 ОТОБРАЖАЕМ ВЫЧИСЛЕННУЮ ЦЕНУ
                              Text('$displayPrice Руб', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.black87)),
                              const SizedBox(height: 4),
                              Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                              const SizedBox(height: 8),
                              const Icon(Icons.check_circle, color: Colors.green, size: 18),
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
      ),
    );
  }

  Widget _buildLeadingIcon(String type) {
    IconData icon;
    Color color;
    switch (type) {
      case 'city': icon = Icons.location_city; color = Colors.blue; break;
      case 'mejCity': icon = Icons.map; color = Colors.teal; break;
      case 'express':
      case 'delivery': icon = Icons.flash_on; color = Colors.red; break;
      default: icon = Icons.shopping_bag; color = Colors.orange;
    }
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 24),
    );
  }

  void _navigateToDetail(BuildContext context, String type, DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final String userId = data['userId'] ?? '';
    final String orderId = doc.id;

    String collectionName;
    switch (type) {
      case 'city': collectionName = 'cityOrders'; break;
      case 'mejCity': collectionName = 'intercityOrders'; break;
      default: collectionName = 'delivery_orders';
    }

    final orderRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection(collectionName)
        .doc(orderId);

    Widget screen;
    switch (type) {
      case 'city':
        screen = GorodOrderDetailScreen(orderRef: orderRef, courierId: courierId, courierPhone: '');
        break;
      case 'mejCity':
        screen = IntercityOrderDetailScreen(orderRef: orderRef, courierId: courierId, courierPhone: '');
        break;
      case 'express':
      case 'delivery':
        screen = SrokOrderDetailScreen(orderRef: orderRef, courierId: courierId, courierPhone: '');
        break;
      default:
        screen = CourierOrderDetailScreen(orderRef: orderRef, courierId: courierId, courierPhone: '');
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}