import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Твои импорты без изменений
import 'active_detail.dart';
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

class _OrdersStatusScreenState extends State<OrdersStatusScreen> {

  // Вынесенный и улучшенный виджет бейджа
  Widget _buildTypeBadge(String type) {
    String label;
    Color color;

    switch (type) {
      case 'normal': label = 'ДОСТАВКА'; color = Colors.orange[800]!; break;
      case 'express':
      case 'delivery': label = 'СРОЧНО'; color = Colors.red[800]!; break;
      case 'city': label = 'ГОРОД'; color = Colors.blue[800]!; break;
      case 'mejCity': label = 'МЕЖГОРОД'; color = Colors.green[800]!; break;
      default: label = 'ЗАКАЗ'; color = Colors.grey[700]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordersQuery = FirebaseFirestore.instance
        .collection('couriers')
        .doc(widget.courierId)
        .collection('history')
        .where('status', whereIn: ['accepted', 'inProgress'])
        .orderBy('actionAt', descending: true);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Текущие заказы', style: TextStyle(fontWeight: FontWeight.bold)),
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
        stream: ordersQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки заказов'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.deepOrange));
          }

          final orders = snapshot.data!.docs;
          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('Активных заказов нет', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;

              final type = data['type'] ?? (data.containsKey('fromAddress') ? 'mejCity' : 'normal');
              final price = data['totalPrice'] ?? data['totalCost'] ?? data['total'] ?? 0;
              final status = data['status'] ?? '';

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => _navigateToDetail(context, type, doc),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // ВЕРХ: ID и Статус
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('ЗАКАЗ №${doc.id.substring(0, 6).toUpperCase()}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                              _buildStatusIndicator(status),
                            ],
                          ),
                          const Divider(height: 24),

                          // СЕРЕДИНА: Клиент и Магазин
                          Row(
                            children: [
                              _buildLeadingIcon(type),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(data['clientName'] ?? 'Без имени',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    if (type == 'normal')
                                      Text('${getShopLabelById(data['shopId'] ?? '')}: ${data['restaurantName'] ?? ''}',
                                          style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                    const SizedBox(height: 8),
                                    _buildTypeBadge(type),
                                  ],
                                ),
                              ),
                              // Цена
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('$price ₽', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                                  const Text('к оплате', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
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
      ),
    );
  }

  Widget _buildStatusIndicator(String status) {
    bool isInProgress = status == 'inProgress';
    return Row(
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: isInProgress ? Colors.blue : Colors.orange,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          isInProgress ? 'В ПУТИ' : 'ПРИНЯТ',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isInProgress ? Colors.blue[800] : Colors.orange[800]
          ),
        ),
      ],
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
      width: 44, height: 44,
      decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 22),
    );
  }

  void _navigateToDetail(BuildContext context, String type, DocumentSnapshot doc) {
    Widget screen;
    switch (type) {
      case 'normal':
        screen = CourierOrderDetailScreen(orderRef: doc.reference, courierId: widget.courierId, courierPhone: widget.courierPhone);
        break;
      case 'city':
        screen = GorodOrderDetailScreen(orderRef: doc.reference, courierId: widget.courierId, courierPhone: widget.courierPhone);
        break;
      case 'delivery':
      case 'express':
        screen = SrokOrderDetailScreen(orderRef: doc.reference, courierId: widget.courierId, courierPhone: widget.courierPhone);
        break;
      case 'mejCity':
        screen = IntercityOrderDetailScreen(orderRef: doc.reference, courierId: widget.courierId, courierPhone: widget.courierPhone);
        break;
      default:
        screen = CourierOrderDetailScreen(orderRef: doc.reference, courierId: widget.courierId, courierPhone: widget.courierPhone);
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}