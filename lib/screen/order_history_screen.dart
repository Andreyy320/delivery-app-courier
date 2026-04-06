import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'active_detail.dart';      // обычные заказы
import 'gorod_detail.dart';       // городские заказы
import 'mejgorod_detail.dart';    // межгород
import 'srok_detail.dart';        // срочные/express заказы

class OrderHistoryScreen extends StatelessWidget {
  final String courierId;

  const OrderHistoryScreen({super.key, required this.courierId});

  // Бейдж с типом доставки
  Widget _buildTypeBadge(String type) {
    String label;
    Color color;

    switch (type) {
      case 'normal':
        label = 'Доставка';
        color = Colors.orange;
        break;
      case 'express':
      case 'delivery':
        label = 'Срочная доставка';
        color = Colors.red;
        break;
      case 'city':
        label = 'Город';
        color = Colors.blue;
        break;
      case 'mejCity':
        label = 'Межгород';
        color = Colors.green;
        break;
      default:
        label = 'Доставка';
        color = Colors.orange;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
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
      appBar: AppBar(
        title: const Text('История заказов'),
        backgroundColor: Colors.deepOrange,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: historyQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки истории'));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Нет завершённых заказов'));

          final orders = snapshot.data!.docs;

          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;

              final type = data['type'] ?? 'normal';
              final clientName = data['clientName'] ?? 'Без имени';
              final clientPhone = data['clientPhone'] ?? '-';
              final price = data['totalPrice'] ?? data['totalCost'] ?? data['total'] ?? 0;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text('Заказ №${doc.id.substring(0, 6)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('Клиент: $clientName'),
                      Text('Телефон: $clientPhone'),
                      Text('Сумма: $price ₽'),
                      _buildTypeBadge(type), // бейдж с типом доставки
                    ],
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Widget screen;
                    switch (type) {
                      case 'normal':
                        screen = CourierOrderDetailScreen(
                          orderRef: doc.reference,
                          courierId: courierId,
                          courierPhone: '',
                        );
                        break;
                      case 'city':
                        screen = GorodOrderDetailScreen(
                          orderRef: doc.reference,
                          courierId: courierId,
                          courierPhone: '',
                        );
                        break;
                      case 'express':
                      case 'delivery':
                        screen = SrokOrderDetailScreen(
                          orderRef: doc.reference,
                          courierId: courierId,
                          courierPhone: '',
                        );
                        break;
                      case 'mejCity':
                        screen = IntercityOrderDetailScreen(
                          orderRef: doc.reference,
                          courierId: courierId,
                          courierPhone: '',
                        );
                        break;
                      default:
                        screen = CourierOrderDetailScreen(
                          orderRef: doc.reference,
                          courierId: courierId,
                          courierPhone: '',
                        );
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => screen),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
