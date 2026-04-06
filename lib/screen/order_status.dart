import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'active_detail.dart';      // обычные заказы
import 'gorod_detail.dart';       // городские заказы
import 'mejgorod_detail.dart';    // межгород
import 'srok_detail.dart';        // срочные/express заказы

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

String getShopLabelById(String shopId) {
  if (shopId.isEmpty) return 'Заведение';

  const floareShops = ['mir_svetov', 'svetok_sentr', 'buket_md'];
  const restaurantShops = ['la_vida', 'nuvo', 'georgia', 'la_tokane'];
  const aptekas = ['viva_farm', 'sto_letnik', 'e_apteka'];
  const electronics = ['hitek', 'tiraet', 'tirElKom'];
  const groceryShops = ['garant', 'akvatir', 'hlebokombinat'];

  if (floareShops.contains(shopId)) return 'Цветочный магазин';
  if (restaurantShops.contains(shopId)) return 'Ресторан';
  if (aptekas.contains(shopId)) return 'Аптека';
  if (electronics.contains(shopId)) return 'Магазин электроники';
  if (groceryShops.contains(shopId)) return 'Продуктовый магазин';

  return 'Заведение';
}

Widget buildTypeBadge(String type) {
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
    margin: const EdgeInsets.only(top: 6),
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

class _OrdersStatusScreenState extends State<OrdersStatusScreen> {
  @override
  Widget build(BuildContext context) {
    final ordersQuery = FirebaseFirestore.instance
        .collection('couriers')
        .doc(widget.courierId)
        .collection('history')
        .where('status', whereIn: ['accepted', 'inProgress'])
        .orderBy('actionAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои текущие заказы'),
        backgroundColor: Colors.deepOrange,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: ordersQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки заказов'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data!.docs;
          if (orders.isEmpty) return const Center(child: Text('Нет текущих заказов'));

          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;
              final orderRef = doc.reference;
              final orderId = doc.id;

              // Тип заказа
              final type = data['type'] ?? (data.containsKey('fromAddress') ? 'mejCity' : 'normal');

              // Цена: берём все возможные поля
              final price = data['totalPrice'] ?? data['totalCost'] ?? data['total'] ?? 0;

              // Клиент
              final clientName = data['clientName'] ?? 'Без имени';
              final clientPhone = data['clientPhone'] ?? '-';

              // Заведение показываем только для обычных заказов
              String shopText = '';
              if (type == 'normal') {
                final restaurantName = data['restaurantName'] ?? '';
                final shopId = data['shopId'] ?? '';
                final shopLabel = getShopLabelById(shopId);
                shopText = '$shopLabel: $restaurantName';
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(
                    'Заказ №${orderId.substring(0, 6)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('Клиент: $clientName'),
                      Text('Телефон: $clientPhone'),
                      if (shopText.isNotEmpty) Text(shopText),
                      Text('Сумма: $price ₽'), // теперь всегда корректно
                      buildTypeBadge(type),
                    ],
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Widget screen;
                    switch (type) {
                      case 'normal':
                        screen = CourierOrderDetailScreen(
                          orderRef: orderRef,
                          courierId: widget.courierId,
                          courierPhone: widget.courierPhone,
                        );
                        break;
                      case 'city':
                        screen = GorodOrderDetailScreen(
                          orderRef: orderRef,
                          courierId: widget.courierId,
                          courierPhone: widget.courierPhone,
                        );
                        break;
                      case 'delivery':
                      case 'express':
                        screen = SrokOrderDetailScreen(
                          orderRef: orderRef,
                          courierId: widget.courierId,
                          courierPhone: widget.courierPhone,
                        );
                        break;
                      case 'mejCity':
                        screen = IntercityOrderDetailScreen(
                          orderRef: orderRef,
                          courierId: widget.courierId,
                          courierPhone: widget.courierPhone,
                        );
                        break;
                      default:
                        screen = CourierOrderDetailScreen(
                          orderRef: orderRef,
                          courierId: widget.courierId,
                          courierPhone: widget.courierPhone,
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
