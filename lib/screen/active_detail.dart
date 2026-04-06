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
  State<CourierOrderDetailScreen> createState() =>
      _CourierOrderDetailScreenState();
}

// Функция для определения типа заведения
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

  Future<void> _updateStatus(String newStatus) async {
    setState(() => loading = true);
    try {
      final snap = await widget.orderRef.get();
      if (!snap.exists) throw Exception('Заказ не найден');
      final data = snap.data() as Map<String, dynamic>;

      final actionTime = FieldValue.serverTimestamp();

      // 🔹 Данные для курьера
      Map<String, dynamic> updateData = {
        'status': newStatus,
        'courierId': widget.courierId,
        'courierPhone': widget.courierPhone,
        'updatedAt': actionTime,
      };

      // Метки времени
      if ((newStatus == 'accepted' || newStatus == 'inProgress' || newStatus == 'delivered') && data['acceptedAt'] == null) {
        updateData['acceptedAt'] = actionTime;
      }
      if ((newStatus == 'inProgress' || newStatus == 'delivered') && data['inProgressAt'] == null) {
        updateData['inProgressAt'] = actionTime;
      }
      if (newStatus == 'delivered' && data['deliveredAt'] == null) {
        updateData['deliveredAt'] = actionTime;
      }

      // 🔹 Обновляем заказ курьера
      await widget.orderRef.update(updateData);

      // 🔹 Обновляем историю курьера
      await FirebaseFirestore.instance
          .collection('couriers')
          .doc(widget.courierId)
          .collection('history')
          .doc(widget.orderRef.id)
          .set({
        ...data,
        ...updateData,
        'actionAt': actionTime,
      });

      // 🔹 Обновляем заказ пользователя
      if (data['userId'] != null) {
        final clientOrderRef = FirebaseFirestore.instance
            .collection('users')
            .doc(data['userId'])
            .collection('orders')
            .doc(widget.orderRef.id);

        Map<String, dynamic> clientUpdate = {
          'status': newStatus,
        };
        if (updateData['acceptedAt'] != null) clientUpdate['acceptedAt'] = updateData['acceptedAt'];
        if (updateData['inProgressAt'] != null) clientUpdate['inProgressAt'] = updateData['inProgressAt'];
        if (updateData['deliveredAt'] != null) clientUpdate['deliveredAt'] = updateData['deliveredAt'];

        await clientOrderRef.update(clientUpdate);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Статус обновлён: $newStatus')),
      );

      if (newStatus == 'accepted' || newStatus == 'inProgress') {
        Navigator.pop(context, true);
      } else {
        setState(() {});
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      setState(() => loading = false);
    }
  }


  String formatTime(Timestamp? ts) {
    if (ts == null) return '-';
    return DateFormat('dd.MM.yyyy HH:mm').format(ts.toDate());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Детали заказа'),
        backgroundColor: Colors.deepOrange,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: widget.orderRef.get(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Ошибка'));
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Заказ не найден'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final clientName = data['clientName'] ?? 'Без имени';
          final clientPhone = data['clientPhone'] ?? '-';
          final status = data['status'] ?? 'new';
          final createdAt = data['createdAt'] as Timestamp?;
          final items = data['items'] as List<dynamic>? ?? [];
          final total = data['total'] ?? 0.0;

          final restaurantName = data['restaurantName'] ?? 'Неизвестно';
          final shopId = data['shopId'] ?? '';
          final shopLabel = getShopLabelById(shopId);

          final acceptedAt = data['acceptedAt'] as Timestamp?;
          final inProgressAt = data['inProgressAt'] as Timestamp?;
          final deliveredAt = data['deliveredAt'] as Timestamp?;

          final createdTime = createdAt != null
              ? DateFormat('dd.MM.yyyy HH:mm').format(createdAt.toDate())
              : '';

          return Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Заказ №${widget.orderRef.id.substring(0, 6)}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Клиент: $clientName', style: const TextStyle(fontSize: 16)),
                  Text('Телефон: $clientPhone', style: const TextStyle(fontSize: 16)),
                  Text('Статус: $status', style: const TextStyle(fontSize: 16)),
                  Text('Создан: $createdTime', style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('$shopLabel: $restaurantName',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if ((data['comment'] ?? '').isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Комментарий:',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(data['comment'], style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 8),
                      ],
                    ),
                  const Text('Товары:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ...items.map((item) {
                    final i = item as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('${i['name']} × ${i['quantity']}',
                          style: const TextStyle(fontSize: 16)),
                    );
                  }).toList(),
                  const SizedBox(height: 8),
                  Text('Итого: $total ₽',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // 🔹 Строки с временем статусов
                  if (acceptedAt != null) Text('Принят во: ${formatTime(acceptedAt)}'),
                  if (inProgressAt != null) Text('В пути во: ${formatTime(inProgressAt)}'),
                  if (deliveredAt != null) Text('Доставлено во: ${formatTime(deliveredAt)}'),
                  const SizedBox(height: 16),

                  // Кнопки действий курьера
                  if (status == 'new')
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: loading ? null : () => _updateStatus('accepted'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepOrange,
                                padding: const EdgeInsets.symmetric(vertical: 14)),
                            child: loading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('Принять заказ'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: loading ? null : () => _updateStatus('cancelled'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(vertical: 14)),
                            child: loading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('Отменить заказ'),
                          ),
                        ),
                      ],
                    ),
                  if (status == 'accepted')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : () => _updateStatus('inProgress'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        child: loading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('В пути'),
                      ),
                    ),
                  if (status == 'inProgress')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : () => _updateStatus('delivered'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        child: loading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Доставлено'),
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
