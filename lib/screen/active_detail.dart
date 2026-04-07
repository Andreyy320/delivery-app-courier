import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CourierOrderDetailScreen extends StatefulWidget {
  final DocumentReference orderRef;
  final String courierId;
  final String courierPhone;

  const CourierOrderDetailScreen({
    super.key,
    required this.orderRef,
    required this.courierId,
    required this.courierPhone,
  });

  @override
  State<CourierOrderDetailScreen> createState() => _CourierOrderDetailScreenState();
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

class _CourierOrderDetailScreenState extends State<CourierOrderDetailScreen> {
  bool loading = false;

  // Красивый перевод статусов для SnackBar
  String _translateStatus(String status) {
    switch (status) {
      case 'accepted': return 'Принят';
      case 'inProgress': return 'В пути';
      case 'delivered': return 'Доставлен';
      case 'cancelled': return 'Отменён';
      default: return status;
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => loading = true);
    try {
      final snap = await widget.orderRef.get();
      if (!snap.exists) throw Exception('Заказ не найден');
      final data = snap.data() as Map<String, dynamic>;
      final actionTime = FieldValue.serverTimestamp();

      Map<String, dynamic> updateData = {
        'status': newStatus,
        'courierId': widget.courierId,
        'courierPhone': widget.courierPhone,
        'updatedAt': actionTime,
      };

      if (['accepted', 'inProgress', 'delivered'].contains(newStatus) && data['acceptedAt'] == null) {
        updateData['acceptedAt'] = actionTime;
      }
      if (['inProgress', 'delivered'].contains(newStatus) && data['inProgressAt'] == null) {
        updateData['inProgressAt'] = actionTime;
      }
      if (newStatus == 'delivered' && data['deliveredAt'] == null) {
        updateData['deliveredAt'] = actionTime;
      }

      await widget.orderRef.update(updateData);

      await FirebaseFirestore.instance
          .collection('couriers')
          .doc(widget.courierId)
          .collection('history')
          .doc(widget.orderRef.id)
          .set({...data, ...updateData, 'actionAt': actionTime}, SetOptions(merge: true));

      if (data['userId'] != null) {
        final clientOrderRef = FirebaseFirestore.instance
            .collection('users')
            .doc(data['userId'])
            .collection('orders')
            .doc(widget.orderRef.id);

        Map<String, dynamic> clientUpdate = {'status': newStatus};
        if (updateData['acceptedAt'] != null) clientUpdate['acceptedAt'] = updateData['acceptedAt'];
        if (updateData['inProgressAt'] != null) clientUpdate['inProgressAt'] = updateData['inProgressAt'];
        if (updateData['deliveredAt'] != null) clientUpdate['deliveredAt'] = updateData['deliveredAt'];

        await clientOrderRef.update(clientUpdate);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Статус обновлён: ${_translateStatus(newStatus)}'),
              backgroundColor: Colors.green[700],
              behavior: SnackBarBehavior.floating,
            ));
        if (newStatus == 'accepted' || newStatus == 'inProgress') {
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
        title: const Text('Детали заказа', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: widget.orderRef.get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text('Заказ не найден'));

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'new';
          final shopLabel = getShopLabelById(data['shopId'] ?? '');

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildHeaderCard(data, shopLabel),
                      const SizedBox(height: 16),
                      _buildClientCard(data),
                      const SizedBox(height: 16),
                      _buildItemsCard(data),
                      const SizedBox(height: 16),
                      _buildTimelineCard(data),
                    ],
                  ),
                ),
              ),
              _buildBottomActionPanel(status),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> data, String shopLabel) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('№${widget.orderRef.id.substring(0, 6).toUpperCase()}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
              _statusBadge(data['status']),
            ],
          ),
          const Divider(height: 32),
          _infoRow(Icons.storefront, shopLabel, data['restaurantName'] ?? 'Неизвестно', isBold: true),
          _infoRow(Icons.access_time, 'Создан', _formatDate(data['createdAt'])),
        ],
      ),
    );
  }

  Widget _buildClientCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('КЛИЕНТ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 12),
          _infoRow(Icons.person_outline, 'Имя', data['clientName'] ?? 'Без имени'),
          _infoRow(Icons.phone_outlined, 'Телефон', data['clientPhone'] ?? '-'),
          if ((data['comment'] ?? '').isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(12)),
              child: _infoRow(Icons.comment_outlined, 'Комментарий', data['comment'], color: Colors.brown[700]),
            ),
        ],
      ),
    );
  }

  Widget _buildItemsCard(Map<String, dynamic> data) {
    final items = data['items'] as List<dynamic>? ?? [];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('СОСТАВ ЗАКАЗА', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.fastfood_outlined, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Text('${item['name']}')),
                Text('× ${item['quantity']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          )),
          const Divider(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('К оплате:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              Text('${data['total']} ₽', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ТАЙМЛАЙН', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 16),
          _timeStep('Принят', data['acceptedAt']),
          _timeStep('В пути', data['inProgressAt']),
          _timeStep('Доставлен', data['deliveredAt'], isLast: true),
        ],
      ),
    );
  }

  Widget _buildBottomActionPanel(String status) {
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
          if (status == 'new') ...[
            _actionBtn('ПРИНЯТЬ ЗАКАЗ', Colors.deepOrange, () => _updateStatus('accepted')),
            const SizedBox(height: 8),
            TextButton(onPressed: () => _updateStatus('cancelled'), child: const Text('Отклонить', style: TextStyle(color: Colors.red))),
          ] else if (status == 'accepted')
            _actionBtn('В ПУТИ', Colors.orange, () => _updateStatus('inProgress'))
          else if (status == 'inProgress')
              _actionBtn('ДОСТАВЛЕНО', Colors.green, () => _updateStatus('delivered')),
        ],
      ),
    );
  }

  Widget _actionBtn(String text, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
        child: loading ? const CircularProgressIndicator(color: Colors.white) : Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey[400]),
          const SizedBox(width: 10),
          Text('$label: ', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          Expanded(child: Text(value, style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color ?? Colors.black87))),
        ],
      ),
    );
  }

  // Обновленный бейдж на русском
  Widget _statusBadge(String status) {
    String label;
    Color color;

    switch (status) {
      case 'new': label = 'НОВЫЙ'; color = Colors.blue; break;
      case 'accepted': label = 'ПРИНЯТ'; color = Colors.orange; break;
      case 'inProgress': label = 'В ПУТИ'; color = Colors.indigo; break;
      case 'delivered': label = 'ДОСТАВЛЕН'; color = Colors.green; break;
      case 'cancelled': label = 'ОТМЕНЁН'; color = Colors.red; break;
      default: label = status.toUpperCase(); color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _timeStep(String title, Timestamp? time, {bool isLast = false}) {
    return Row(
      children: [
        Icon(time != null ? Icons.check_circle : Icons.circle_outlined, size: 16, color: time != null ? Colors.green : Colors.grey[200]),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(color: time != null ? Colors.black87 : Colors.grey[400])),
        const Spacer(),
        if (time != null) Text(DateFormat('HH:mm').format(time.toDate()), style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  String _formatDate(Timestamp? ts) => ts != null ? DateFormat('dd.MM.yyyy HH:mm').format(ts.toDate()) : '-';
}