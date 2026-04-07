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

  // 🔹 Логика без изменений
  Future<void> _takeAction(String action) async {
    setState(() => loading = true);
    try {
      final snap = await widget.orderRef.get();
      if (!snap.exists) throw Exception('Заказ не найден');
      final data = snap.data() as Map<String, dynamic>;

      final userId = data['userId'];
      if (userId == null) throw Exception('ID пользователя не найден');

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

      // 1. Основной заказ
      await widget.orderRef.update(updateData);

      // 2. У КЛИЕНТА
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('delivery_orders')
          .doc(widget.orderRef.id)
          .update(updateData);

      // 3. История курьера
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
          SnackBar(
            content: Text('Статус обновлён: ${_statusToRussian(action)}'),
            backgroundColor: Colors.red[900],
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
        title: const Text('Срочная доставка', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.red[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: _urgencyBadge()),
          ),
        ],
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
                      _buildHeaderCard(data),
                      const SizedBox(height: 16),
                      _buildAddressCard(data),
                      const SizedBox(height: 16),
                      _buildTimelineCard(data),
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

  Widget _urgencyBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> data) {
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
              Text('Заказ №${widget.orderRef.id.substring(0, 6)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('${data['totalCost'] ?? 0} ₽',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.red[900])),
            ],
          ),
          const Divider(height: 32),
          _infoRow(Icons.person_pin_outlined, 'Клиент', data['clientName'] ?? '-'),
          _infoRow(Icons.phone_android_outlined, 'Телефон', data['clientPhone'] ?? '-'),
          if (data['comment']?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(12)),
              child: _infoRow(Icons.comment_outlined, 'Инфо', data['comment'], color: Colors.brown[700]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddressCard(Map<String, dynamic> data) {
    // Извлекаем данные из твоих полей pickup и dropoff
    final pickup = data['pickup'] as Map<String, dynamic>?;
    final dropoff = data['dropoff'] as Map<String, dynamic>?;

    // Формируем строку с координатами для отображения
    final fromStr = pickup != null
        ? '${pickup['lat'].toStringAsFixed(6)}, ${pickup['lng'].toStringAsFixed(6)}'
        : 'Координаты не указаны';

    final toStr = dropoff != null
        ? '${dropoff['lat'].toStringAsFixed(6)}, ${dropoff['lng'].toStringAsFixed(6)}'
        : 'Координаты не указаны';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Column(
        children: [
          _addressRow(
              Icons.location_on_outlined,
              Colors.red[900]!,
              'ТОЧКА ОТПРАВКИ (PICKUP)',
              fromStr,
              pickup // передаем мапу для кнопки навигации
          ),
          Padding(
            padding: const EdgeInsets.only(left: 11),
            child: Container(height: 25, width: 2, color: Colors.grey[100]),
          ),
          _addressRow(
              Icons.flag_outlined,
              Colors.black,
              'ТОЧКА ДОСТАВКИ (DROPOFF)',
              toStr,
              dropoff
          ),
        ],
      ),
    );
  }

  // Обновленный ряд с кнопкой навигатора
  Widget _addressRow(IconData icon, Color color, String label, String address, Map<String, dynamic>? coords) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
              Text(address, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        if (coords != null)
          IconButton(
            icon: const Icon(Icons.map_outlined, color: Colors.blue),
            onPressed: () {
              // Здесь в будущем добавишь launchUrl для открытия карт
              // MapsLauncher.launchCoordinates(coords['lat'], coords['lng']);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Открываем навигатор...'))
              );
            },
          ),
      ],
    );
  }

  Widget _buildTimelineCard(Map<String, dynamic> data) {
    final acceptedAt = data['acceptedAt'] as Timestamp?;
    final inProgressAt = data['inProgressAt'] as Timestamp?;
    final deliveredAt = data['deliveredAt'] as Timestamp?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('СТАТУС ВЫПОЛНЕНИЯ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 16),
          _statusStep('Заказ принят', acceptedAt),
          _statusStep('Курьер в пути', inProgressAt),
          _statusStep('Доставлено', deliveredAt, isLast: true),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey[400]),
          const SizedBox(width: 10),
          Text('$label: ', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          Expanded(child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color ?? Colors.black87))),
        ],
      ),
    );
  }



  Widget _statusStep(String title, Timestamp? time, {bool isLast = false}) {
    return Row(
      children: [
        Icon(time != null ? Icons.check_circle : Icons.circle_outlined,
            size: 16, color: time != null ? Colors.green : Colors.grey[200]),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(color: time != null ? Colors.black87 : Colors.grey, fontSize: 13)),
        const Spacer(),
        if (time != null) Text(DateFormat('HH:mm').format(time.toDate()), style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
          if (status == 'new') ...[
            _btn('ПРИНЯТЬ СРОЧНЫЙ ЗАКАЗ', Colors.red[900]!, () => _takeAction('accepted')),
            const SizedBox(height: 8),
            TextButton(onPressed: () => _takeAction('cancelled'), child: const Text('Отклонить', style: TextStyle(color: Colors.grey))),
          ],
          if (status == 'accepted') _btn('НАЧАТЬ ПУТЬ', Colors.orange[800]!, () => _takeAction('inProgress')),
          if (status == 'inProgress') _btn('ПОДТВЕРДИТЬ ДОСТАВКУ', Colors.green[700]!, () => _takeAction('delivered')),
        ],
      ),
    );
  }

  Widget _btn(String text, Color color, VoidCallback onTap) {
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
}