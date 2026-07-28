import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'detail_screen/active_detail.dart';
import 'detail_screen/srok_detail.dart';

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
  static const Color appBg = Color(0xFFF1F5F9);
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);

  // Фиксированный ключ навигатора предотвращает пересоздание дерева при обновлении стрима
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  // Кэшируем ID последнего активного заказа, чтобы избежать лишней перерисовки роутера
  String? _lastLoadedOrderId;

  @override
  Widget build(BuildContext context) {
    // Слушаем активные заказы курьера в его истории
    final activeOrderQuery = FirebaseFirestore.instance
        .collection('couriers')
        .doc(widget.courierId)
        .collection('history')
        .where('status', whereIn: ['accepted', 'inProgress'])
        .orderBy('acceptedAt', descending: true)
        .limit(1);

    return Scaffold(
      backgroundColor: appBg,
      body: StreamBuilder<QuerySnapshot>(
        stream: activeOrderQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: primaryBlue));
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Ошибка загрузки: ${snapshot.error}',
                  style: const TextStyle(color: textMuted),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            _lastLoadedOrderId = null;
            return _buildEmptyState();
          }

          final doc = docs.first;
          final data = doc.data() as Map<String, dynamic>;
          final String currentOrderId = doc.id;

          // Проверяем все возможные варианты поля типа заказа
          final String type = (data['type'] ?? data['orderType'] ?? data['deliveryType'] ?? 'normal')
              .toString()
              .toLowerCase()
              .trim();

          // Надежное определение индивидуальной/срочной доставки
          final bool isDeliveryOrder = type == 'express' ||
              type == 'delivery' ||
              type == 'individual' ||
              type == 'delivery_order' ||
              type == 'срочный' ||
              doc.reference.path.contains('delivery_orders');

          // Ссылка на сам документ в истории курьера
          final orderRef = doc.reference;

          // Если это тот же самый заказ (например, сменился статус с accepted на inProgress),
          // мы не пересоздаем весь Navigator заново, а позволяем внутреннему экрану обновиться по своему StreamBuilder.
          bool isSameOrder = _lastLoadedOrderId == currentOrderId;
          _lastLoadedOrderId = currentOrderId;

          return PopScope(
            canPop: false,
            child: Navigator(
              key: isSameOrder ? _navigatorKey : GlobalKey<NavigatorState>(),
              onGenerateRoute: (settings) {
                if (!isSameOrder) {
                  _lastLoadedOrderId = currentOrderId;
                }
                Widget page;
                if (isDeliveryOrder) {
                  page = SrokOrderDetailScreen(
                    orderRef: orderRef,
                    courierId: widget.courierId,
                    courierPhone: widget.courierPhone,
                  );
                } else {
                  page = CourierOrderDetailScreen(
                    orderRef: orderRef,
                    courierId: widget.courierId,
                    courierPhone: widget.courierPhone,
                  );
                }
                return MaterialPageRoute(builder: (context) => page);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: primaryBlue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delivery_dining_rounded, size: 64, color: primaryBlue),
            ),
            const SizedBox(height: 20),
            const Text(
              'НЕТ АКТИВНЫХ ЗАКАЗОВ',
              style: TextStyle(color: textDark, fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'У вас пока нет заказов в работе. Ожидайте новые назначения.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textMuted, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}