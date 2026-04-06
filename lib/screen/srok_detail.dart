import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SrokOrderDetailScreen extends StatefulWidget {
  final DocumentReference orderRef;
  final String courierPhone;
  final String courierId;

  const SrokOrderDetailScreen({
    super.key,
    required this.orderRef,
    required this.courierPhone,
    required this.courierId,
  });

  @override
  State<SrokOrderDetailScreen> createState() => _SrokOrderDetailScreenState();
}

class _SrokOrderDetailScreenState extends State<SrokOrderDetailScreen> {
  bool loading = false;

  // 🔹 Универсальная функция действия (как в твоем примере с едой)
  Future<void> _takeAction(String action) async {
    setState(() => loading = true);
    try {
      final snap = await widget.orderRef.get();
      if (!snap.exists) throw Exception('Заказ не найден');
      final data = snap.data() as Map<String, dynamic>;

      // Получаем userId клиента, чтобы знать, какой путь к папке пользователя
      final userId = data['userId'];
      if (userId == null) throw Exception('ID пользователя не найден в заказе');

      final actionTime = FieldValue.serverTimestamp();

      Map<String, dynamic> updateData = {
        'status': action,
        'courierId': widget.courierId,
        'courierPhone': widget.courierPhone,
        'updatedAt': actionTime,
      };

      // Проставляем метки времени для прогресс-бара
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

      // 1. Обновляем основной заказ (тот, что курьер нашел через collectionGroup)
      await widget.orderRef.update(updateData);

      // 2. ОБНОВЛЯЕМ У КЛИЕНТА (чтобы у него в приложении всё сработало)
      // Путь: users / {userId} / delivery_orders / {orderId}
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('delivery_orders')
          .doc(widget.orderRef.id)
          .update(updateData); // Используем update, так как заказ там точно есть

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
          'type': 'delivery',
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
        title: const Text('Детали срочного заказа'),
        backgroundColor: Colors.deepOrange,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: widget.orderRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки'));
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text('Заказ не найден'));

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final status = data['status'] ?? 'new';
          final createdAt = data['createdAt'] as Timestamp?;
          final createdTime = createdAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(createdAt.toDate()) : '';

          // Времена из БД
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
                  _infoRow('Телефон', data['clientPhone'] ?? '-'),
                  _infoRow('Откуда', data['fromAddress'] ?? '-'),
                  _infoRow('Куда', data['toAddress'] ?? '-'),
                  _infoRow('Сумма', '${data['totalCost'] ?? 0} ₽'),
                  _infoRow('Создан', createdTime),

                  if (data['comment'] != null && data['comment'].toString().isNotEmpty)
                    _infoRow('Комментарий', data['comment']),

                  const SizedBox(height: 16),
                  const Text('История статусов:', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (acceptedAt != null) Text('✅ Принят: ${DateFormat('HH:mm').format(acceptedAt.toDate())}'),
                  if (inProgressAt != null) Text('🚚 В пути: ${DateFormat('HH:mm').format(inProgressAt.toDate())}'),
                  if (deliveredAt != null) Text('🏁 Доставлен: ${DateFormat('HH:mm').format(deliveredAt.toDate())}'),

                  const SizedBox(height: 24),

                  // 🔹 КНОПКИ ДЕЙСТВИЙ (по логике как в еде)
                  if (status == 'new') ...[
                    _actionButton('Принять заказ', Colors.deepOrange, () => _takeAction('accepted')),
                    const SizedBox(height: 8),
                    _actionButton('Отменить', Colors.red, () => _takeAction('cancelled')),
                  ],
                  if (status == 'accepted')
                    _actionButton('Начать путь (В пути)', Colors.orange, () => _takeAction('inProgress')),
                  if (status == 'inProgress')
                    _actionButton('Доставлено', Colors.green, () => _takeAction('delivered')),
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
