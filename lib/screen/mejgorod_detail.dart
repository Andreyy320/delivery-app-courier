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

  // 🔹 Универсальная функция действия (синхронизация в 3 места)
  Future<void> _takeAction(String action) async {
    setState(() => loading = true);
    try {
      final snap = await widget.orderRef.get();
      if (!snap.exists) throw Exception('Заказ не найден');
      final data = snap.data() as Map<String, dynamic>;

      // 1. Получаем userId клиента (критично для обновления шкалы у пользователя)
      final userId = data['userId'];
      if (userId == null) throw Exception('ID пользователя не найден в заказе');

      final actionTime = FieldValue.serverTimestamp();

      Map<String, dynamic> updateData = {
        'status': action,
        'courierId': widget.courierId,
        'courierPhone': widget.courierPhone,
        'updatedAt': actionTime,
      };

      // Проставляем метки времени для шкалы прогресса
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

      // --- ВЫПОЛНЯЕМ ЗАПИСЬ В 3 МЕСТА ---

      // 1. Обновляем основной заказ в общей базе
      await widget.orderRef.update(updateData);

      // 2. ОБНОВЛЯЕМ У КЛИЕНТА (чтобы у него в приложении сработала анимация шкалы)
      // Путь: users / {userId} / delivery_orders / {orderId}
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('delivery_orders')
          .doc(widget.orderRef.id)
          .update(updateData);

      // 3. Записываем в историю курьера
      if (['accepted', 'inProgress', 'delivered'].contains(action)) {
        await FirebaseFirestore.instance
            .collection('couriers')
            .doc(widget.courierId)
            .collection('history')
            .doc(widget.orderRef.id)
            .set({
          ...data,
          ...updateData,
          'type': 'intercity',
          'actionAt': actionTime,
        }, SetOptions(merge: true));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Статус обновлён: ${_statusToRussian(action)}')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления: $e')),
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
      appBar: AppBar(
        title: const Text('Детали межгородского заказа'),
        backgroundColor: Colors.deepOrange,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: widget.orderRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки'));
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text('Заказ не найден'));

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'new';

          final acceptedAt = data['acceptedAt'] as Timestamp?;
          final inProgressAt = data['inProgressAt'] as Timestamp?;
          final deliveredAt = data['deliveredAt'] as Timestamp?;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Заказ №${widget.orderRef.id.substring(0, 6)}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Divider(),
                  _infoRow('Клиент', data['clientName'] ?? '-'),
                  _infoRow('Откуда', data['fromAddress'] ?? '-'),
                  _infoRow('Куда', data['toAddress'] ?? '-'),
                  _infoRow('Сумма', '${data['totalPrice'] ?? 0} ₽'),

                  const SizedBox(height: 16),
                  const Text('История статусов:', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (acceptedAt != null) Text('✅ Принят: ${DateFormat('HH:mm').format(acceptedAt.toDate())}'),
                  if (inProgressAt != null) Text('🚚 В пути: ${DateFormat('HH:mm').format(inProgressAt.toDate())}'),
                  if (deliveredAt != null) Text('🏁 Доставлен: ${DateFormat('HH:mm').format(deliveredAt.toDate())}'),

                  const SizedBox(height: 24),

                  // Кнопки управления
                  if (status == 'new') ...[
                    _actionButton('Принять заказ', Colors.deepOrange, () => _takeAction('accepted')),
                    const SizedBox(height: 8),
                    _actionButton('Отменить', Colors.red, () => _takeAction('cancelled')),
                  ],
                  if (status == 'accepted')
                    _actionButton('Выехал к клиенту', Colors.orange, () => _takeAction('inProgress')),
                  if (status == 'inProgress')
                    _actionButton('Груз доставлен', Colors.green, () => _takeAction('delivered')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text('$label: $value', style: const TextStyle(fontSize: 16)),
    );
  }

  Widget _actionButton(String text, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
        ),
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
    );
  }
}