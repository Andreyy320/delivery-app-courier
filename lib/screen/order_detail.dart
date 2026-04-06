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

// 🔹 Функция для определения типа заведения по shopId
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

      // 🔹 Общее время действия
      final actionTime = FieldValue.serverTimestamp();

      // 🔹 Данные для обновления основного заказа
      Map<String, dynamic> updateData = {
        'status': action,
        'courierId': widget.courierId,
        'courierPhone': widget.courierPhone,
        'updatedAt': actionTime,
      };

      // 🔹 Метки времени для статусов
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

      // 🔹 Обновляем заказ
      await widget.orderRef.update(updateData);

      // 🔹 Добавляем/обновляем запись в истории курьера
      if (action == 'accepted' || action == 'inProgress' || action == 'delivered') {
        await FirebaseFirestore.instance
            .collection('couriers')
            .doc(widget.courierId)
            .collection('history')
            .doc(widget.orderRef.id)
            .set({
          ...data,
          ...updateData,
          'actionAt': actionTime, // для сортировки и фильтрации на экране OrdersStatusScreen
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Заказ обновлён: $action')),
      );

      // 🔹 Закрываем экран при принятии или начале пути
      if (action == 'accepted' || action == 'inProgress') {
        Navigator.pop(context, true); // обновление списка родителя
      } else {
        setState(() {}); // иначе просто обновляем UI
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      setState(() => loading = false);
    }
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
          if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки заказа'));
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text('Заказ не найден'));

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final clientName = data['clientName'] ?? 'Без имени';
          final clientPhone = data['clientPhone'] ?? '-';
          final payment = data['paymentMethod'] ?? '-';
          final comment = data['comment'] ?? '';
          final status = data['status'] ?? 'new';
          final total = data['total'] ?? 0.0;
          final createdAt = data['createdAt'] as Timestamp?;
          final createdTime = createdAt != null
              ? DateFormat('dd.MM.yyyy HH:mm').format(createdAt.toDate())
              : '';
          final items = data['items'] as List<dynamic>? ?? [];
          final deliveryLocation = data['deliveryLocation'] as Map<String, dynamic>?;
          final restaurantName = data['restaurantName'] ?? 'Неизвестно';
          final shopId = data['shopId'] ?? '';
          final shopLabel = getShopLabelById(shopId);

          // Времена статусов
          final acceptedAt = data['acceptedAt'] as Timestamp?;
          final inProgressAt = data['inProgressAt'] as Timestamp?;
          final deliveredAt = data['deliveredAt'] as Timestamp?;

          final acceptedTime = acceptedAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(acceptedAt.toDate()) : '';
          final inProgressTime = inProgressAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(inProgressAt.toDate()) : '';
          final deliveredTime = deliveredAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(deliveredAt.toDate()) : '';

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
                  Text('$shopLabel: $restaurantName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Оплата: $payment', style: const TextStyle(fontSize: 16)),
                  Text('Статус: $status', style: const TextStyle(fontSize: 16)),
                  Text('Создан: $createdTime', style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),

                  if (comment.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Комментарий:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(comment, style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 8),
                      ],
                    ),

                  const Text('Товары:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ...items.map((item) {
                    final itemMap = item as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('${itemMap['name'] ?? 'Без названия'} × ${itemMap['quantity'] ?? 1}', style: const TextStyle(fontSize: 16)),
                    );
                  }).toList(),

                  if (deliveryLocation != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        const Text('Адрес / координаты:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('lat: ${deliveryLocation['lat'] ?? '-'}, lng: ${deliveryLocation['lng'] ?? '-'}', style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 8),
                      ],
                    ),

                  Text('Итого: $total ₽', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // История статусов
                  if (acceptedTime.isNotEmpty || inProgressTime.isNotEmpty || deliveredTime.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('История статусов:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        if (acceptedTime.isNotEmpty) Text('Принят: $acceptedTime', style: const TextStyle(fontSize: 16)),
                        if (inProgressTime.isNotEmpty) Text('В пути: $inProgressTime', style: const TextStyle(fontSize: 16)),
                        if (deliveredTime.isNotEmpty) Text('Доставлено: $deliveredTime', style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 16),
                      ],
                    ),

                  // Кнопки действий
                  if (status == 'ready')
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: loading ? null : () => _takeAction('accepted'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, padding: const EdgeInsets.symmetric(vertical: 14)),
                            child: loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Принять заказ'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: loading ? null : () => _takeAction('cancelled'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 14)),
                            child: loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Отменить заказ'),
                          ),
                        ),
                      ],
                    ),
                  if (status == 'accepted')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : () => _takeAction('inProgress'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        child: loading ? const CircularProgressIndicator(color: Colors.white) : const Text('В пути'),
                      ),
                    ),
                  if (status == 'inProgress')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : () => _takeAction('delivered'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
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
