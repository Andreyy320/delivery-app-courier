import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
// Импортируем для звонков и навигации
import 'package:url_launcher/url_launcher.dart';

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

class _CourierOrderDetailScreenState extends State<CourierOrderDetailScreen> {
  bool loading = false;
  bool mapLoading = false; // Состояние загрузки карты

  final Color primaryColor = const Color(0xFF2D31FA);
  final Color backgroundColor = const Color(0xFFF8FAFF);
  final Color cardColor = Colors.white;

  // --- ФУНКЦИИ ВЗАИМОДЕЙСТВИЯ ---

  // Звонок клиенту
  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) return;
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  // Переход к навигации (Google Maps / Apple Maps)
  double? _parseCoordinate(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  Future<void> _openMapNavigation(Map<String, dynamic> data) async {
    setState(() => mapLoading = true);
    try {
      double? lat = _parseCoordinate(data['clientLat']);
      double? lng = _parseCoordinate(data['clientLng']);

      if (lat != null && lng != null) {
        final Uri googleMapsUri = Uri.parse("google.navigation:q=$lat,$lng&mode=d");
        final Uri appleMapsUri = Uri.parse("http://maps.apple.com/?daddr=$lat,$lng");

        if (await canLaunchUrl(googleMapsUri)) {
          await launchUrl(googleMapsUri);
        } else if (await canLaunchUrl(appleMapsUri)) {
          await launchUrl(appleMapsUri);
        } else {
          throw 'Could not launch maps';
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Координаты адреса не найдены')),
        );
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      setState(() => mapLoading = false);
    }
  }

  // --- ЛОГИКА СТАТУСОВ ---

  String _mapCategoryToLabel(String? category) {
    switch (category?.toLowerCase().trim()) {
      case 'restaurant': return 'Ресторан';
      case 'product': return 'Продукты';
      case 'electronika': return 'Электроника';
      case 'svetok': return 'Цветы';
      case 'apteka': return 'Аптека';
      default: return 'Заведение';
    }
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'accepted': return 'Принят';
      case 'preparing': return 'Готовится';
      case 'ready': return 'Готов к выдаче';
      case 'inProgress': return 'В пути';
      case 'delivered': return 'Доставлен';
      case 'cancelled': return 'Отменён';
      default: return 'Новый';
    }
  }

  Future<void> _updateStatus(String newStatus, Map<String, dynamic> currentData) async {
    setState(() => loading = true);
    try {
      final actionTime = FieldValue.serverTimestamp();
      final orderId = widget.orderRef.id;
      final String shopId = currentData['shopId'] ?? '';

      final courierSnap = await FirebaseFirestore.instance.collection('couriers').doc(widget.courierId).get();
      final courierName = courierSnap.data()?['name'] ?? 'Курьер';

      Map<String, dynamic> updateData = {
        'status': newStatus,
        'courierId': widget.courierId,
        'courierPhone': widget.courierPhone,
        'courierName': courierName,
        'statusUpdatedAt': actionTime,
        'updatedAt': actionTime,
      };

      if (newStatus == 'accepted') updateData['acceptedAt'] = actionTime;
      if (newStatus == 'inProgress') updateData['inProgressAt'] = actionTime;
      if (newStatus == 'delivered') updateData['deliveredAt'] = actionTime;

      WriteBatch batch = FirebaseFirestore.instance.batch();
      batch.set(FirebaseFirestore.instance.collection('orders').doc(orderId), updateData, SetOptions(merge: true));
      batch.set(FirebaseFirestore.instance.collection('couriers').doc(widget.courierId).collection('history').doc(orderId), updateData, SetOptions(merge: true));

      if (currentData['userId'] != null) {
        batch.set(FirebaseFirestore.instance.collection('users').doc(currentData['userId']).collection('orders').doc(orderId), updateData, SetOptions(merge: true));
      }

      if (shopId.isNotEmpty) {
        DocumentReference shopHistoryRef = FirebaseFirestore.instance.collection('categories').doc(shopId).collection('ordersHistory').doc(orderId);
        batch.set(shopHistoryRef, {...currentData, ...updateData, 'lastUpdateBy': 'courier'}, SetOptions(merge: true));
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Статус обновлен: ${_translateStatus(newStatus)}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
        ));
        if (newStatus == 'delivered') Navigator.pop(context);
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
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Детали заказа', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: widget.orderRef.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _buildAlternativeStream();
          }
          return _buildOrderContent(snapshot.data!.data() as Map<String, dynamic>);
        },
      ),
    );
  }

  Widget _buildAlternativeStream() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('couriers')
          .doc(widget.courierId)
          .collection('history')
          .doc(widget.orderRef.id)
          .snapshots(),
      builder: (context, altSnapshot) {
        if (altSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!altSnapshot.hasData || !altSnapshot.data!.exists) {
          return const Center(child: Text('Заказ не найден'));
        }
        return _buildOrderContent(altSnapshot.data!.data() as Map<String, dynamic>);
      },
    );
  }

  Widget _buildOrderContent(Map<String, dynamic> orderData) {
    final String shopId = orderData['shopId'] ?? '';
    if (shopId.isEmpty) return _buildMainLayout(orderData, 'Заведение');

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('categories').doc(shopId).snapshots(),
      builder: (context, catSnapshot) {
        String shopLabel = 'Заведение';
        if (catSnapshot.hasData && catSnapshot.data!.exists) {
          final catData = catSnapshot.data!.data() as Map<String, dynamic>;
          shopLabel = _mapCategoryToLabel(catData['category']);
        }
        return _buildMainLayout(orderData, shopLabel);
      },
    );
  }

  Widget _buildMainLayout(Map<String, dynamic> orderData, String shopLabel) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              _buildHeaderCard(orderData, shopLabel),
              const SizedBox(height: 16),
              _buildClientCard(orderData),
              const SizedBox(height: 16),
              _buildItemsCard(orderData),
              const SizedBox(height: 16),
              _buildTimelineCard(orderData),
            ],
          ),
        ),
        _buildBottomActionPanel(orderData['status'] ?? 'new', orderData),
      ],
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> data, String shopLabel) {
    return _cardWrapper(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ID ЗАКАЗА', style: TextStyle(fontSize: 10, color: Colors.grey[400], fontWeight: FontWeight.bold)),
                  Text('#${widget.orderRef.id.length > 6 ? widget.orderRef.id.substring(widget.orderRef.id.length - 6).toUpperCase() : widget.orderRef.id}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ],
              ),
              _statusBadge(data['status']),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider()),
          _infoRow(Icons.storefront_rounded, shopLabel, data['restaurantName'] ?? data['shopName'] ?? 'Не указано', isMain: true),
          const SizedBox(height: 12),
          _infoRow(Icons.access_time_rounded, 'Время создания', _formatDate(data['createdAt'])),
        ],
      ),
    );
  }

  Widget _buildClientCard(Map<String, dynamic> data) {
    final String? phone = data['clientPhone'];

    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ИНФОРМАЦИЯ О ДОСТАВКЕ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 16),
          _infoRow(Icons.person_rounded, 'Получатель', data['clientName'] ?? 'Без имени'),
          const SizedBox(height: 12),
          // Ряд с телефоном и кнопкой вызова
          Row(
            children: [
              Expanded(child: _infoRow(Icons.phone_rounded, 'Контактный номер', phone ?? '-')),
              if (phone != null && phone.isNotEmpty)
                IconButton(
                  onPressed: () => _makePhoneCall(phone),
                  icon: const Icon(Icons.call, color: Colors.green),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.green.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Ряд с адресом и кнопкой навигации
          Row(
            children: [
              Expanded(child: _infoRow(Icons.location_on_rounded, 'Адрес назначения', data['address'] ?? 'Указан на карте', color: primaryColor)),
              IconButton(
                onPressed: mapLoading ? null : () => _openMapNavigation(data),
                icon: mapLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.navigation_rounded, color: Color(0xFF2D31FA)),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF2D31FA).withOpacity(0.1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsCard(Map<String, dynamic> data) {
    final items = data['items'] as List<dynamic>? ?? [];
    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('СОСТАВ ЗАКАЗА', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 16),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text('${item['quantity']}x', style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor, fontSize: 12))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('${item['name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                Text('${(item['price'] ?? 0) * (item['quantity'] ?? 1)} MDL', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          )).toList(),
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ИТОГО', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text('${data['total'] ?? 0} MDL', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: primaryColor)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard(Map<String, dynamic> data) {
    return _cardWrapper(
      child: Column(
        children: [
          _timeStep('Заказ принят курьером', data['acceptedAt']),
          _timeStep('Курьер в пути', data['inProgressAt']),
          _timeStep('Заказ доставлен', data['deliveredAt'], isLast: true),
        ],
      ),
    );
  }

  Widget _buildBottomActionPanel(String status, Map<String, dynamic> currentData) {
    if (status == 'delivered' || status == 'cancelled') return const SizedBox.shrink();
    final String assignedCourierId = currentData['courierId'] ?? '';

    if (assignedCourierId.isEmpty) {
      return _actionButton('ПРИНЯТЬ ЗАКАЗ', const Color(0xFF00C853), 'accepted', currentData);
    }

    if (assignedCourierId == widget.courierId) {
      if (status == 'inProgress') {
        return _actionButton('ПОДТВЕРДИТЬ ДОСТАВКУ', primaryColor, 'delivered', currentData);
      } else {
        return _actionButton('НАЧАТЬ ДОСТАВКУ', const Color(0xFFFFAB00), 'inProgress', currentData);
      }
    }

    return Container(
        padding: const EdgeInsets.only(bottom: 30),
        child: const Center(child: Text('Заказ уже взят другим курьером', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))
    );
  }

  Widget _actionButton(String text, Color color, String nextStatus, Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 35),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          onPressed: loading ? null : () => _updateStatus(nextStatus, data),
          child: loading
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _cardWrapper({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: const Color(0xFFE0E5EC).withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: child,
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {bool isMain = false, Color? color}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: (color ?? Colors.grey[400]!).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 20, color: color ?? Colors.grey[600]),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 11, fontWeight: FontWeight.bold)),
              Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: isMain ? 16 : 14, fontWeight: isMain ? FontWeight.w800 : FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String? status) {
    Color color;
    switch (status) {
      case 'accepted': color = const Color(0xFF00C853); break;
      case 'preparing': color = Colors.orange; break;
      case 'ready': color = Colors.teal; break;
      case 'inProgress': color = const Color(0xFFFFAB00); break;
      case 'delivered': color = primaryColor; break;
      default: color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
      child: Text(_translateStatus(status ?? 'new').toUpperCase(), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }

  Widget _timeStep(String title, Timestamp? time, {bool isLast = false}) {
    bool isDone = time != null;
    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: isDone ? primaryColor : Colors.white,
                  border: Border.all(color: isDone ? primaryColor : Colors.grey[300]!, width: 2),
                  shape: BoxShape.circle,
                ),
                child: isDone ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
              ),
              if (!isLast) Expanded(child: VerticalDivider(color: isDone ? primaryColor : Colors.grey[300], thickness: 2)),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: TextStyle(fontWeight: isDone ? FontWeight.w700 : FontWeight.w500, color: isDone ? Colors.black87 : Colors.grey[400])),
                  if (isDone) Text(DateFormat('HH:mm').format(time.toDate()), style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(Timestamp? ts) => ts != null ? DateFormat('dd.MM HH:mm').format(ts.toDate()) : '-';
}
