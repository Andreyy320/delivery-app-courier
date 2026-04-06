import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class GorodOrderDetailScreen extends StatefulWidget {
  final DocumentReference orderRef;
  final String courierPhone;
  final String courierId;

  const GorodOrderDetailScreen({
    super.key,
    required this.orderRef,
    required this.courierPhone,
    required this.courierId,
  });

  @override
  State<GorodOrderDetailScreen> createState() => _GorodOrderDetailScreenState();
}

class _GorodOrderDetailScreenState extends State<GorodOrderDetailScreen> {
  bool loading = false;

  Future<void> _updateStatus(String action, Map<String, dynamic> data) async {
    setState(() => loading = true);

    try {
      // Получаем userId клиента для обновления в его папке
      final userId = data['userId'];
      if (userId == null) throw Exception('ID пользователя не найден');

      final actionTime = FieldValue.serverTimestamp();

      Map<String, dynamic> updateData = {
        'status': action,
        'courierId': widget.courierId,
        'courierPhone': widget.courierPhone,
        'updatedAt': actionTime,
      };

      // Сохраняем время для каждого статуса
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

      // --- ЗАПИСЬ В 3 МЕСТА (как в примере) ---

      // 1. Обновляем основной заказ
      await widget.orderRef.update(updateData);

      // 2. ОБНОВЛЯЕМ У КЛИЕНТА (чтобы у него в приложении всё сработало)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('delivery_orders') // Проверь, что коллекция у клиента называется так же
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
          'type': 'city',
          'actionAt': actionTime,
        }, SetOptions(merge: true));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Статус обновлён: ${_statusToRussian(action)}')),
        );

        // Закрываем экран при принятии или в пути для обновления списков
        if (action == 'accepted' || action == 'inProgress' || action == 'delivered' || action == 'cancelled') {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
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

  Widget _buildAdditionalOptions(Map<String, dynamic> data) {
    final List<Widget> widgets = [];
    if (data.containsKey('escort')) widgets.add(Text('Сопровождающий: ${data['escort']}', style: const TextStyle(fontSize: 16)));
    if (data.containsKey('loaders')) widgets.add(Text('Грузчики: ${data['loaders']}', style: const TextStyle(fontSize: 16)));
    if (data.containsKey('bodySize')) widgets.add(Text('Размер кузова: ${data['bodySize']}', style: const TextStyle(fontSize: 16)));

    if (widgets.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text('Дополнительно:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        ...widgets,
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Детали городского заказа'),
        backgroundColor: Colors.deepOrange,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: widget.orderRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки заказа'));
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text('Заказ не найден'));

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final clientName = data['clientName'] ?? '-';
          final clientPhone = data['clientPhone'] ?? '-';
          final fromAddress = data['fromAddress'] ?? '-';
          final toAddress = data['toAddress'] ?? '-';
          final status = data['status'] ?? 'new';
          final totalPrice = data['totalPrice'] ?? 0;
          final comment = data['comment'] ?? '';
          final createdAt = data['createdAt'] as Timestamp?;
          final createdTime = createdAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(createdAt.toDate()) : '';
          final scheduledTime = data['scheduledTime'] as Timestamp?;
          final scheduledTimeStr = scheduledTime != null ? DateFormat('dd.MM.yyyy HH:mm').format(scheduledTime.toDate()) : '—';

          final acceptedAt = data['acceptedAt'] as Timestamp?;
          final inProgressAt = data['inProgressAt'] as Timestamp?;
          final deliveredAt = data['deliveredAt'] as Timestamp?;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Заказ №${widget.orderRef.id.substring(0, 6)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Клиент: $clientName', style: const TextStyle(fontSize: 16)),
                  Text('Телефон: $clientPhone', style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('Откуда: $fromAddress', style: const TextStyle(fontSize: 16)),
                  Text('Куда: $toAddress', style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('Сумма: $totalPrice ₽', style: const TextStyle(fontSize: 16)),
                  Text('Статус: ${_statusToRussian(status)}', style: const TextStyle(fontSize: 16)),
                  Text('Создан: $createdTime', style: const TextStyle(fontSize: 16)),
                  Text('Запланировано: $scheduledTimeStr', style: const TextStyle(fontSize: 16)),
                  if (comment.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Комментарий:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(comment, style: const TextStyle(fontSize: 16)),
                  ],

                  _buildAdditionalOptions(data),

                  const Text('История статусов:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  if (acceptedAt != null) Text('Принят: ${DateFormat('dd.MM.yyyy HH:mm').format(acceptedAt.toDate())}', style: const TextStyle(fontSize: 16)),
                  if (inProgressAt != null) Text('В пути: ${DateFormat('dd.MM.yyyy HH:mm').format(inProgressAt.toDate())}', style: const TextStyle(fontSize: 16)),
                  if (deliveredAt != null) Text('Доставлено: ${DateFormat('dd.MM.yyyy HH:mm').format(deliveredAt.toDate())}', style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 16),

                  // Кнопки
                  if (status == 'new') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : () => _updateStatus('accepted', data),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Принять заказ'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : () => _updateStatus('cancelled', data),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Отменить заказ'),
                      ),
                    ),
                  ],
                  if (status == 'accepted')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : () => _updateStatus('inProgress', data),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: loading ? const CircularProgressIndicator(color: Colors.white) : const Text('В пути'),
                      ),
                    ),
                  if (status == 'inProgress')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : () => _updateStatus('delivered', data),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Доставлено'),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
