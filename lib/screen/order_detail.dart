import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class OrderDetailScreen extends StatefulWidget {
  final DocumentReference orderRef;
  final String courierPhone;
  final String courierId;

  const OrderDetailScreen({
    super.key,
    required this.orderRef,
    required this.courierPhone,
    required this.courierId,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
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

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool loading = false;

  Future<void> _takeAction(String action) async {
    setState(() => loading = true);
    try {
      final snap = await widget.orderRef.get();
      if (!snap.exists) throw Exception('Заказ не найден');
      final data = snap.data() as Map<String, dynamic>;
      final actionTime = FieldValue.serverTimestamp();

      Map<String, dynamic> updateData = {
        'status': action,
        'courierId': widget.courierId,
        'courierPhone': widget.courierPhone,
        'updatedAt': actionTime,
      };

      if (action == 'accepted' && data['acceptedAt'] == null) updateData['acceptedAt'] = actionTime;
      if (action == 'inProgress' && data['inProgressAt'] == null) updateData['inProgressAt'] = actionTime;
      if (action == 'delivered') {
        if (data['acceptedAt'] == null) updateData['acceptedAt'] = actionTime;
        if (data['inProgressAt'] == null) updateData['inProgressAt'] = actionTime;
        updateData['deliveredAt'] = actionTime;
      }

      await widget.orderRef.update(updateData);

      if (['accepted', 'inProgress', 'delivered'].contains(action)) {
        await FirebaseFirestore.instance
            .collection('couriers')
            .doc(widget.courierId)
            .collection('history')
            .doc(widget.orderRef.id)
            .set({...data, ...updateData, 'actionAt': actionTime}, SetOptions(merge: true));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Заказ обновлён: $action'), backgroundColor: Colors.deepOrange),
        );
        if (action == 'accepted' || action == 'inProgress' || action == 'delivered') {
          Navigator.pop(context, true);
        } else {
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Детали доставки', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: widget.orderRef.get(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки'));
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text('Заказ не найден'));

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'new';
          final items = data['items'] as List<dynamic>? ?? [];

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildMainCard(data),
                      const SizedBox(height: 16),
                      _buildItemsCard(items, data['total'] ?? 0.0),
                      const SizedBox(height: 16),
                      _buildHistoryCard(data),
                    ],
                  ),
                ),
              ),
              _buildBottomPanel(status, data),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMainCard(Map<String, dynamic> data) {
    final shopLabel = getShopLabelById(data['shopId'] ?? '');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Заказ №${widget.orderRef.id.substring(0, 6)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
              _statusBadge(data['status']),
            ],
          ),
          const Divider(height: 30),
          _infoRow(Icons.storefront, shopLabel, data['restaurantName'] ?? 'Неизвестно', isBold: true),
          _infoRow(Icons.person_outline, 'Клиент', data['clientName'] ?? 'Без имени'),
          _infoRow(Icons.phone_outlined, 'Телефон', data['clientPhone'] ?? '-'),
          _infoRow(Icons.payment, 'Оплата', data['paymentMethod'] ?? '-'),
          if (data['comment']?.isNotEmpty == true)
            _infoRow(Icons.comment_outlined, 'Комментарий', data['comment'], color: Colors.blueGrey),
        ],
      ),
    );
  }

  Widget _buildItemsCard(List<dynamic> items, dynamic total) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('СОСТАВ ЗАКАЗА', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 12),
          ...items.map((item) {
            final itemMap = item as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.fastfood_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${itemMap['name'] ?? 'Товар'}')),
                  Text('×${itemMap['quantity'] ?? 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }).toList(),
          const Divider(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Итого к оплате:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              Text('$total ₽', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> data) {
    final acceptedAt = data['acceptedAt'] as Timestamp?;
    final inProgressAt = data['inProgressAt'] as Timestamp?;
    final deliveredAt = data['deliveredAt'] as Timestamp?;
    if (acceptedAt == null && inProgressAt == null && deliveredAt == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ИСТОРИЯ СТАТУСОВ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 16),
          _timeStep('Принят', acceptedAt),
          _timeStep('В пути', inProgressAt),
          _timeStep('Доставлен', deliveredAt, isLast: true),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[400]),
          const SizedBox(width: 10),
          Text('$label: ', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          Expanded(child: Text(value, style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color ?? Colors.black87
          ))),
        ],
      ),
    );
  }

  Widget _statusBadge(String? status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.deepOrange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(status?.toUpperCase() ?? 'NEW',
          style: const TextStyle(color: Colors.deepOrange, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _timeStep(String title, Timestamp? time, {bool isLast = false}) {
    return Row(
      children: [
        Icon(time != null ? Icons.check_circle : Icons.circle_outlined,
            size: 16, color: time != null ? Colors.green : Colors.grey[200]),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(color: time != null ? Colors.black87 : Colors.grey[400])),
        const Spacer(),
        if (time != null) Text(DateFormat('HH:mm').format(time.toDate()), style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _buildBottomPanel(String status, Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'ready') ...[
            _btn('ПРИНЯТЬ ЗАКАЗ', Colors.deepOrange, () => _takeAction('accepted')),
            const SizedBox(height: 8),
            TextButton(onPressed: () => _takeAction('cancelled'), child: const Text('Отменить', style: TextStyle(color: Colors.red))),
          ],
          if (status == 'accepted') _btn('В ПУТИ', Colors.orange, () => _takeAction('inProgress')),
          if (status == 'inProgress') _btn('ДОСТАВЛЕНО', Colors.green, () => _takeAction('delivered')),
        ],
      ),
    );
  }

  Widget _btn(String text, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
        child: loading ? const CircularProgressIndicator(color: Colors.white) : Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }
}