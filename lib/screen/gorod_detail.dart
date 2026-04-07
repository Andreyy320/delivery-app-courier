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

  // 🔹 Логика без изменений (обновление в 3 местах)
  Future<void> _updateStatus(String action, Map<String, dynamic> data) async {
    setState(() => loading = true);

    try {
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

      // 1. Обновляем основной заказ
      await widget.orderRef.update(updateData);

      // 2. ОБНОВЛЯЕМ У КЛИЕНТА (используем set с merge: true для стабильности)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('cityOrders')
          .doc(widget.orderRef.id)
          .set(updateData, SetOptions(merge: true));

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
          SnackBar(
            content: Text('Статус обновлён: ${_statusToRussian(action)}'),
            backgroundColor: Colors.orange[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
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
        title: const Text('Городской заказ', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.orange[700],
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

                      // 2. КАРТОЧКА ДЕТАЛЕЙ КЛИЕНТА
                      _buildClientCard(data),
                      const SizedBox(height: 16),

                      // 3. ШКАЛА СТАТУСОВ
                      _buildStatusTimeline(data),
                    ],
                  ),
                ),
              ),
              // ПАНЕЛЬ ДЕЙСТВИЙ (КНОПКИ)
              _buildActionPanel(status, data),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
      ),
      child: Column(
        children: [
          _routeRow(Icons.circle_outlined, Colors.orange, 'ОТКУДА', data['fromAddress']),
          Padding(
            padding: const EdgeInsets.only(left: 11),
            child: Container(height: 25, width: 1.5, color: Colors.grey[200]),
          ),
          _routeRow(Icons.location_on, Colors.redAccent, 'КУДА', data['toAddress']),
        ],
      ),
    );
  }

  Widget _routeRow(IconData icon, Color color, String label, String? address) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
              Text(address ?? '-', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClientCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          _infoTile(Icons.person_outline, 'Клиент', data['clientName'] ?? '-'),
          _infoTile(Icons.phone_iphone_outlined, 'Телефон', data['clientPhone'] ?? '-'),
          _infoTile(Icons.payments_outlined, 'К оплате', '${data['totalPrice'] ?? 0} ₽', isPrice: true),
          if (data['comment']?.isNotEmpty == true) ...[
            const Divider(height: 24),
            _infoTile(Icons.chat_bubble_outline, 'Комментарий', data['comment']),
          ],
          _buildAdditionalChips(data),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value, {bool isPrice = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[400]),
          const SizedBox(width: 10),
          Text('$label:', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(value, style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isPrice ? Colors.orange[800] : Colors.black87
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalChips(Map<String, dynamic> data) {
    List<Widget> chips = [];
    if (data.containsKey('escort')) chips.add(_tagChip('Сопровождение: ${data['escort']}'));
    if (data.containsKey('loaders')) chips.add(_tagChip('Грузчики: ${data['loaders']}'));
    if (data.containsKey('bodySize')) chips.add(_tagChip('Кузов: ${data['bodySize']}'));

    if (chips.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  Widget _tagChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
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
          const Text('ХРОНОЛОГИЯ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 16),
          _timelineStep('Принят', acceptedAt),
          _timelineStep('В пути', inProgressAt),
          _timelineStep('Доставлен', deliveredAt, isLast: true),
        ],
      ),
    );
  }

  Widget _timelineStep(String title, Timestamp? time, {bool isLast = false}) {
    return Row(
      children: [
        Column(
          children: [
            Icon(time != null ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18, color: time != null ? Colors.green : Colors.grey[300]),
            if (!isLast) Container(width: 1.5, height: 20, color: Colors.grey[100]),
          ],
        ),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(color: time != null ? Colors.black87 : Colors.grey, fontSize: 13)),
        const Spacer(),
        if (time != null) Text(DateFormat('HH:mm').format(time.toDate()), style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildActionPanel(String status, Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'new') ...[
            _actionButton('ПРИНЯТЬ ЗАКАЗ', Colors.orange[700]!, () => _updateStatus('accepted', data)),
            TextButton(
              onPressed: loading ? null : () => _updateStatus('cancelled', data),
              child: const Text('Отменить заказ', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
          if (status == 'accepted')
            _actionButton('В ПУТИ К КЛИЕНТУ', Colors.amber[800]!, () => _updateStatus('inProgress', data)),
          if (status == 'inProgress')
            _actionButton('ЗАВЕРШИТЬ ДОСТАВКУ', Colors.green[600]!, () => _updateStatus('delivered', data)),
          if (status == 'delivered')
            const Text('✅ Заказ выполнен', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
        ],
      ),
    );
  }

  Widget _actionButton(String text, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}