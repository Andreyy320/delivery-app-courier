import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class IntercityOrderDetailScreen extends StatefulWidget {
  final DocumentReference orderRef;
  final String courierPhone;
  final String courierId;

  const IntercityOrderDetailScreen({
    super.key,
    required this.orderRef,
    required this.courierPhone,
    required this.courierId,
  });

  @override
  State<IntercityOrderDetailScreen> createState() => _IntercityOrderDetailScreenState();
}

class _IntercityOrderDetailScreenState extends State<IntercityOrderDetailScreen> {
  bool loading = false;

  // 🔹 Логика без изменений
  Future<void> _takeAction(String action) async {
    setState(() => loading = true);
    try {
      final snap = await widget.orderRef.get();
      if (!snap.exists) throw Exception('Заказ не найден');
      final data = snap.data() as Map<String, dynamic>;

      final userId = data['userId'];
      if (userId == null) throw Exception('ID пользователя не найден в заказе');

      final actionTime = FieldValue.serverTimestamp();

      Map<String, dynamic> updateData = {
        'status': action,
        'courierId': widget.courierId,
        'courierPhone': widget.courierPhone,
        'updatedAt': actionTime,
      };

      if (action == 'accepted' && data['acceptedAt'] == null) {
        updateData['acceptedAt'] = actionTime;
      }
      if (action == 'inProgress' && data['inProgressAt'] == null) {
        updateData['inProgressAt'] = actionTime;
      }
      if (action == 'delivered') {
        if (data['acceptedAt'] == null) updateData['acceptedAt'] = actionTime;
        if (data['inProgressAt'] == null) updateData['inProgressAt'] = actionTime;
        updateData['deliveredAt'] = actionTime;
      }

      await widget.orderRef.update(updateData);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('mejCityOrders')
          .doc(widget.orderRef.id)
          .update(updateData);

      if (['accepted', 'inProgress', 'delivered'].contains(action)) {
        await FirebaseFirestore.instance
            .collection('couriers')
            .doc(widget.courierId)
            .collection('history')
            .doc(widget.orderRef.id)
            .set({
          ...data,
          ...updateData,
          'type': 'mejCity', // 🔹 Исправили с 'intercity' на 'mejCity' для совместимости
          'total': data['totalPrice'], // 🔹 Дублируем цену в поле 'total', чтобы везде отображалось
          'actionAt': actionTime,
        }, SetOptions(merge: true));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Статус обновлён: ${_statusToRussian(action)}'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _statusToRussian(String status) {
    switch (status) {
      case 'new': return 'Новый';
      case 'accepted': return 'Принят';
      case 'inProgress': return 'В пути';
      case 'delivered': return 'Доставлено';
      case 'cancelled': return 'Отменён';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Детали заказа', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.indigo, // Стиль межгорода
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: widget.orderRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки'));
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text('Заказ не найден'));

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'new';

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // 1. КАРТОЧКА МАРШРУТА
                      _buildRouteCard(data),
                      const SizedBox(height: 16),

                      // 2. ИНФОРМАЦИЯ О КЛИЕНТЕ И ОПЛАТЕ
                      _buildInfoCard(data),
                      const SizedBox(height: 16),

                      // 3. ШКАЛА СТАТУСОВ
                      _buildStatusTimeline(data),
                    ],
                  ),
                ),
              ),

              // 4. ПАНЕЛЬ ДЕЙСТВИЙ (КНОПКИ)
              _buildActionPanel(status),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRouteCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.indigo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ОТКУДА', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                    Text(data['fromAddress'] ?? '-', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 11),
            child: Container(height: 30, width: 2, color: Colors.indigo.withOpacity(0.2)),
          ),
          Row(
            children: [
              const Icon(Icons.navigation, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('КУДА', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                    Text(data['toAddress'] ?? '-', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          _infoTile(Icons.person_outline, 'Клиент', data['clientName'] ?? '-'),
          const Divider(height: 24),
          _infoTile(Icons.payments_outlined, 'К оплате', '${data['totalPrice'] ?? 0} ₽', isPrice: true),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value, {bool isPrice = false}) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey[400], size: 22),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            Text(value, style: TextStyle(
                fontSize: 16,
                fontWeight: isPrice ? FontWeight.bold : FontWeight.w600,
                color: isPrice ? Colors.indigo : Colors.black87
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusTimeline(Map<String, dynamic> data) {
    final acceptedAt = data['acceptedAt'] as Timestamp?;
    final inProgressAt = data['inProgressAt'] as Timestamp?;
    final deliveredAt = data['deliveredAt'] as Timestamp?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ХРОНОЛОГИЯ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 16),
          _timelineStep('Заказ принят', acceptedAt, true),
          _timelineStep('Выехал в путь', inProgressAt, acceptedAt != null),
          _timelineStep('Доставлено', deliveredAt, inProgressAt != null, isLast: true),
        ],
      ),
    );
  }

  Widget _timelineStep(String title, Timestamp? time, bool isActive, {bool isLast = false}) {
    return Row(
      children: [
        Column(
          children: [
            Icon(time != null ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20, color: time != null ? Colors.green : Colors.grey[300]),
            if (!isLast) Container(width: 2, height: 20, color: Colors.grey[200]),
          ],
        ),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(color: time != null ? Colors.black87 : Colors.grey)),
        const Spacer(),
        if (time != null) Text(DateFormat('HH:mm').format(time.toDate()), style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ],
    );
  }

  Widget _buildActionPanel(String status) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'new') ...[
            _actionButton('ПРИНЯТЬ ЗАКАЗ', Colors.indigo, () => _takeAction('accepted')),
            TextButton(
              onPressed: loading ? null : () => _takeAction('cancelled'),
              child: const Text('Отказаться от заказа', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
          if (status == 'accepted')
            _actionButton('ВЫЕХАТЬ К КЛИЕНТУ', Colors.orange, () => _takeAction('inProgress')),
          if (status == 'inProgress')
            _actionButton('ПОДТВЕРДИТЬ ДОСТАВКУ', Colors.green, () => _takeAction('delivered')),
          if (status == 'delivered')
            const Text('✅ Заказ успешно завершен', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
        ],
      ),
    );
  }

  Widget _actionButton(String text, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
