import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'NO_USED_SCREEN/gorod_detail.dart';
import 'NO_USED_SCREEN/mejgorod_detail.dart';
import 'detail_screen/srok_detail.dart';
import 'detail_screen/order_detail.dart';

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

class _CourierOrdersScreenState extends State<CourierOrdersScreen>
    with SingleTickerProviderStateMixin {
  final Map<String, String> _userNamesCache = {};
  int _selectedFilterIndex = 0;

  // --- ПРЕМИАЛЬНАЯ ПАЛИТРА (В СТИЛЕ ЭКРАНА ВХОДА) ---
  static const primaryGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const surfaceBackground = Color(0xFFF8FAFC);
  static const cardBackground = Color(0xFFFFFFFF);
  static const textMain = Color(0xFF0F172A);
  static const textMuted = Color(0xFF64748B);
  static const borderColor = Color(0xFFE2E8F0);

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
          const SnackBar(
            content: Text('Заказ успешно принят!'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String getShopLabelById(String shopId) {
    if (shopId.isEmpty) return 'Заведение';

    const floareShops = ['mir_svetov', 'svetok_sentr', 'buket_md'];
    const restaurantShops = ['la_vida', 'nuvo', 'georgia', 'la_tokane'];
    const aptekas = ['viva_farm', 'sto_letnik', 'e_apteka'];
    const electronics = ['hitek', 'tiraet', 'tirElKom'];
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
        .where('status', whereIn: ['ready', 'preparing', 'accepted'])
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: ordersQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки', style: TextStyle(color: textMuted)));
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('Новых заказов пока нет');
        }

        final orders = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final String? orderCourierId = data['courierId'];
          final List<dynamic> rejectedBy = data['rejectedBy'] ?? [];
          bool isNotRejected = !rejectedBy.contains(widget.courierId);
          bool isAvailable = orderCourierId == null || orderCourierId.isEmpty;
          bool isMine = orderCourierId == widget.courierId;
          return isNotRejected && (isAvailable || isMine);
        }).toList();

        if (orders.isEmpty) return _buildEmptyState('Новых заказов пока нет');

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
            final deliveryEarn = data['deliveryPrice'] ?? 0;

            return FutureBuilder<String>(
              future: _getClientName(data, userId),
              builder: (context, nameSnapshot) {
                final clientName = nameSnapshot.data ?? '...';

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cardBackground,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isMyOrder ? const Color(0xFF2563EB).withOpacity(0.4) : borderColor,
                      width: isMyOrder ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: textMain.withOpacity(0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
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
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563EB).withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    getShopLabelById(shopId).toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xFF2563EB),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                _buildStatusBadge(status, estimatedReadyTime, time),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    restaurantName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: textMain,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '$deliveryEarn Руб',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF059669),
                                      ),
                                    ),
                                    const Text('доставка', style: TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.person_outline_rounded, size: 16, color: textMuted),
                                const SizedBox(width: 6),
                                Text('Клиент: $clientName', style: const TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Divider(height: 1, color: borderColor),
                            ),
                            Row(
                              children: [
                                const Icon(Icons.payments_outlined, size: 18, color: Color(0xFF059669)),
                                const SizedBox(width: 8),
                                Text(
                                  payment,
                                  style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                const Spacer(),
                                Text(
                                  _getActionText(status, isMyOrder),
                                  style: TextStyle(
                                    color: _getStatusColor(status),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.chevron_right_rounded, color: _getStatusColor(status), size: 18),
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

  Widget _buildStatusBadge(String status, Timestamp? estimatedTime, String createTime) {
    if (status == 'preparing' && estimatedTime != null) {
      return _badge(
        color: const Color(0xFF3B82F6),
        icon: Icons.timer_outlined,
        text: 'Будет в ${DateFormat('HH:mm').format(estimatedTime.toDate())}',
      );
    } else if (status == 'ready') {
      return _badge(color: const Color(0xFF10B981), icon: Icons.check_circle_outline, text: 'ГОТОВ');
    } else if (status == 'accepted') {
      return _badge(color: const Color(0xFF2563EB), icon: Icons.assignment_turned_in_outlined, text: 'ВЫ ВЗЯЛИ');
    }
    return Row(
      children: [
        const Icon(Icons.access_time, size: 14, color: textMuted),
        const SizedBox(width: 4),
        Text(createTime, style: const TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _badge({required Color color, required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
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
    if (status == 'preparing') return const Color(0xFF3B82F6);
    if (status == 'ready') return const Color(0xFF10B981);
    return const Color(0xFF2563EB);
  }

  Widget _buildUrgentOrders() {
    final urgentQuery = FirebaseFirestore.instance
        .collectionGroup('delivery_orders')
        .where('status', isEqualTo: 'new')
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: urgentQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки', style: TextStyle(color: textMuted)));
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('Нет индивидуальных заказов');
        }

        final orders = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final doc = orders[index];
            final data = doc.data() as Map<String, dynamic>;

            final createdAt = data['createdAt'] as Timestamp?;
            final time = createdAt != null ? DateFormat('HH:mm').format(createdAt.toDate()) : '';

            // Округляем стоимость до 2 знаков
            final rawCost = data['total_cost'] ?? data['totalPrice'] ?? data['totalCost'] ?? 0;
            final totalCost = (rawCost is num) ? rawCost.toStringAsFixed(2) : rawCost.toString();

            final userId = data['userId'] ?? '';

            // Пробуем забрать телефон прямо из документа, если он там появится
            final clientPhone = data['clientPhone'] ?? data['phone'] ?? data['phone_number'] ?? 'Телефон не указан';
            return FutureBuilder<String>(
              future: _getClientName(data, userId),
              builder: (context, nameSnapshot) {
                final resolvedClientName = nameSnapshot.data ?? data['clientName'] ?? 'Клиент';

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cardBackground,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: textMain.withValues(alpha: 0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
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
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'ЗАКАЗ №${doc.id.substring(0, 6).toUpperCase()}',
                                  style: const TextStyle(
                                    color: textMuted,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        resolvedClientName,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          color: textMain,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        clientPhone,
                                        style: const TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '$totalCost Руб',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Divider(height: 1, color: borderColor),
                            ),
                            Row(
                              children: [
                                const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF3B82F6)),
                                const SizedBox(width: 6),
                                Text(
                                  'Создан в $time',
                                  style: const TextStyle(
                                    color: Color(0xFF3B82F6),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const Spacer(),
                                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: textMuted),
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


  Widget _buildEmptyState(String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: textMain.withOpacity(0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(Icons.bolt_outlined, size: 40, color: textMuted),
          ),
          const SizedBox(height: 16),
          Text(text, style: const TextStyle(color: textMuted, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: surfaceBackground,
        appBar: AppBar(
          title: const Text(
            'Заказы',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: textMain,
              letterSpacing: -0.5,
            ),
          ),
          centerTitle: true,
          backgroundColor: cardBackground,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(70),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: surfaceBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: TabBar(
                onTap: (index) => setState(() => _selectedFilterIndex = index),
                isScrollable: false,
                indicator: BoxDecoration(
                  gradient: primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                labelColor: Colors.white,
                unselectedLabelColor: textMuted,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelPadding: EdgeInsets.zero,
                tabs: const [
                  Tab(
                    child: Center(
                      child: Text(
                        'Доставка',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Tab(
                    child: Center(
                      child: Text(
                        'Индивидуальная',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: const TabBarView(
          physics: BouncingScrollPhysics(),
          children: [
            _OrdersViewWrapper(isUrgent: false),
            _OrdersViewWrapper(isUrgent: true),
          ],
        ),
      ),
    );
  }
}

class _OrdersViewWrapper extends StatelessWidget {
  final bool isUrgent;
  const _OrdersViewWrapper({required this.isUrgent});

  @override
  Widget build(BuildContext context) {
    final parentState = context.findAncestorStateOfType<_CourierOrdersScreenState>();
    if (parentState == null) return const SizedBox.shrink();
    return isUrgent ? parentState._buildUrgentOrders() : parentState._buildDeliveryOrders();
  }
}