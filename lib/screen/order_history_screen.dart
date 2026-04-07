import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
// Твои импорты без изменений
import 'active_detail.dart';
import 'gorod_detail.dart';
import 'mejgorod_detail.dart';
import 'srok_detail.dart';

class OrderHistoryScreen extends StatelessWidget {
  final String courierId;

  const OrderHistoryScreen({super.key, required this.courierId});

  // Улучшенный бейдж с типом доставки
  Widget _buildTypeBadge(String type) {
    String label;
    Color color;

    switch (type) {
      case 'normal':
        label = 'ДОСТАВКА';
        color = Colors.orange[700]!;
        break;
      case 'express':
      case 'delivery':
        label = 'СРОЧНО';
        color = Colors.red[800]!;
        break;
      case 'city':
        label = 'ГОРОД';
        color = Colors.blue[700]!;
        break;
      case 'mejCity':
        label = 'МЕЖГОРОД';
        color = Colors.teal[700]!;
        break;
      default:
        label = 'ЗАКАЗ';
        color = Colors.grey[700]!;
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
    final historyQuery = FirebaseFirestore.instance
        .collection('couriers')
        .doc(courierId)
        .collection('history')
        .orderBy('updatedAt', descending: true);

    return Scaffold(
      backgroundColor: Colors.grey[100], // Светлый фон для контраста карточек
      appBar: AppBar(
        title: const Text('История заказов', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey[200], height: 1),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: historyQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки'));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_outlined, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('История пока пуста', style: TextStyle(color: Colors.grey)),
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
              final price = data['totalPrice'] ?? data['totalCost'] ?? data['total'] ?? 0;

              // Форматируем дату обновления (завершения)
              final updatedAt = data['updatedAt'] as Timestamp?;
              final dateStr = updatedAt != null
                  ? DateFormat('dd MMM, HH:mm').format(updatedAt.toDate())
                  : '--:--';

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _navigateToDetail(context, type, doc, courierId),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          // Иконка в зависимости от типа
                          _buildLeadingIcon(type),
                          const SizedBox(width: 16),

                          // Основная инфо
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
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                _buildTypeBadge(type),
                              ],
                            ),
                          ),

                          // Правая часть: Цена и Дата
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$price ₽',
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.black87),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dateStr,
                                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                              ),
                              const SizedBox(height: 8),
                              Icon(Icons.chevron_right, color: Colors.grey[300], size: 20),
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
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  void _navigateToDetail(BuildContext context, String type, DocumentSnapshot doc, String courierId) {
    Widget screen;
    switch (type) {
      case 'normal':
        screen = CourierOrderDetailScreen(orderRef: doc.reference, courierId: courierId, courierPhone: '');
        break;
      case 'city':
        screen = GorodOrderDetailScreen(orderRef: doc.reference, courierId: courierId, courierPhone: '');
        break;
      case 'express':
      case 'delivery':
        screen = SrokOrderDetailScreen(orderRef: doc.reference, courierId: courierId, courierPhone: '');
        break;
      case 'mejCity':
        screen = IntercityOrderDetailScreen(orderRef: doc.reference, courierId: courierId, courierPhone: '');
        break;
      default:
        screen = CourierOrderDetailScreen(orderRef: doc.reference, courierId: courierId, courierPhone: '');
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}