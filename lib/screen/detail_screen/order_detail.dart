import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

// Фикс для SSL
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

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

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool loading = false;
  bool mapLoading = false;

  // — ПРЕМИАЛЬНАЯ СВЕТЛАЯ ПАЛИТРА —
  static const primaryBlue = Color(0xFF2563EB);
  static const surfaceBackground = Color(0xFFF8FAFC);
  static const cardBackground = Color(0xFFFFFFFF);
  static const textMain = Color(0xFF0F172A);
  static const textMuted = Color(0xFF64748B);
  static const borderColor = Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    HttpOverrides.global = MyHttpOverrides();
  }

  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) return;
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      }
    } catch (e) {
      debugPrint('Ошибка при попытке позвонить: $e');
    }
  }

  final Map<String, String> _statusTranslations = {
    'ready': 'Готов к выдаче',
    'preparing': 'Готовится',
    'accepted': 'Принят',
    'inProgress': 'В пути',
    'delivered': 'Доставлен',
    'cancelled': 'Скрыт для вас',
  };

  Future<void> _takeAction(String action) async {
    setState(() => loading = true);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot freshSnap = await transaction.get(widget.orderRef);
        if (!freshSnap.exists) throw Exception('Заказ не найден');

        final freshData = freshSnap.data() as Map<String, dynamic>;
        final String shopId = freshData['shopId'] ?? '';
        final String existingCourierId = freshData['courierId'] ?? '';

        if (action == 'cancelled') {
          transaction.update(widget.orderRef, {
            'rejectedBy': FieldValue.arrayUnion([widget.courierId])
          });
          return;
        }

        if (existingCourierId.isNotEmpty && existingCourierId != widget.courierId) {
          throw Exception('Этот заказ уже взял другой курьер!');
        }

        if (action == 'accepted') {
          if (existingCourierId.isNotEmpty) throw Exception('Вы уже приняли этот заказ');
          if (!['new', 'preparing', 'ready'].contains(freshData['status'])) {
            throw Exception('Заказ более недоступен для принятия');
          }
        }

        final actionTime = FieldValue.serverTimestamp();
        Map<String, dynamic> updateData = {
          'status': action,
          'courierId': widget.courierId,
          'courierPhone': widget.courierPhone,
          'updatedAt': actionTime,
          'statusUpdatedAt': actionTime,
        };

        if (action == 'accepted') updateData['acceptedAt'] = actionTime;
        if (action == 'inProgress') updateData['inProgressAt'] = actionTime;
        if (action == 'delivered') updateData['deliveredAt'] = actionTime;

        transaction.update(widget.orderRef, updateData);

        if (['accepted', 'inProgress', 'delivered'].contains(action)) {
          DocumentReference courierHistoryRef = FirebaseFirestore.instance
              .collection('couriers')
              .doc(widget.courierId)
              .collection('history')
              .doc(widget.orderRef.id);

          transaction.set(courierHistoryRef, {...freshData, ...updateData}, SetOptions(merge: true));

          if (shopId.isNotEmpty) {
            DocumentReference shopHistoryRef = FirebaseFirestore.instance
                .collection('categories')
                .doc(shopId)
                .collection('ordersHistory')
                .doc(widget.orderRef.id);

            transaction.set(shopHistoryRef, {
              ...freshData,
              ...updateData,
              'lastActionBy': 'courier',
            }, SetOptions(merge: true));
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Статус обновлен: ${_statusTranslations[action] ?? action}'),
            backgroundColor: textMain,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        if (action == 'delivered') Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка: ${e.toString().replaceAll('Exception: ', '')}'),
              backgroundColor: Colors.red[700],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            )
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  double? _parseCoordinate(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  Future<void> _handleMapNavigation(Map<String, dynamic> orderData) async {
    setState(() => mapLoading = true);
    try {
      LatLng? restLocation;
      String shopId = orderData['shopId'] ?? '';

      double? shopLat = _parseCoordinate(orderData['shopLat']) ?? _parseCoordinate(orderData['pickup']?['lat']);
      double? shopLng = _parseCoordinate(orderData['shopLng']) ?? _parseCoordinate(orderData['pickup']?['lon']);

      if (shopLat == null && shopId.isNotEmpty) {
        final shopSnap = await FirebaseFirestore.instance.collection('categories').doc(shopId).get();
        if (shopSnap.exists) {
          final sData = shopSnap.data()!;
          shopLat = _parseCoordinate(sData['lat']) ?? _parseCoordinate(sData['lng']);
          shopLng = _parseCoordinate(sData['lng']) ?? _parseCoordinate(sData['lon']);
        }
      }

      if (shopLat != null && shopLng != null) {
        restLocation = LatLng(shopLat, shopLng);
      }

      double? clientLat = _parseCoordinate(orderData['clientLat']) ?? _parseCoordinate(orderData['dropoff']?['lat']);
      double? clientLng = _parseCoordinate(orderData['clientLng']) ?? _parseCoordinate(orderData['dropoff']?['lon']);

      if (clientLat != null && clientLng != null) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DeliveryMapScreen(
              targetLocation: LatLng(clientLat, clientLng),
              clientName: orderData['clientName'] ?? 'Клиент',
              restaurantLocation: restLocation,
            ),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Координаты назначения не найдены')),
        );
      }
    } finally {
      if (mounted) setState(() => mapLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceBackground,
      appBar: AppBar(
        title: const Text(
          'ДЕТАЛИ ДОСТАВКИ',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 13, color: textMain),
        ),
        centerTitle: true,
        backgroundColor: cardBackground,
        foregroundColor: textMain,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: widget.orderRef.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: primaryBlue));
          if (!snapshot.data!.exists) return const Center(child: Text('Заказ не найден'));

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final String currentStatus = data['status'] ?? 'new';
          final Timestamp? estimatedReadyTime = data['estimatedReadyTime'] as Timestamp?;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    children: [
                      _buildMainCard(data),
                      if (currentStatus == 'preparing' && estimatedReadyTime != null) ...[
                        const SizedBox(height: 16),
                        _buildReadyInCard(estimatedReadyTime),
                      ],
                      const SizedBox(height: 16),
                      _buildClientInfoCard(data),
                      const SizedBox(height: 16),
                      _buildItemsCard(data),
                      const SizedBox(height: 16),
                      _buildStatusHistoryCard(data),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
              _buildActionPanel(currentStatus, data),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReadyInCard(Timestamp time) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Заказ готовится. Время готовности: ${DateFormat('HH:mm').format(time.toDate())}',
              style: const TextStyle(color: Color(0xFF78350F), fontWeight: FontWeight.w700, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainCard(Map<String, dynamic> data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: textMain.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.restaurant_rounded, color: primaryBlue, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ОТКУДА ЗАБРАТЬ',
                      style: TextStyle(
                        fontSize: 10,
                        color: textMuted,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data['restaurantName'] ?? data['shopName'] ?? 'Заведение',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textMain),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(height: 1, color: borderColor),
          ),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: mapLoading ? null : () => _handleMapNavigation(data),
              icon: mapLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.directions_outlined, size: 20),
              label: Text(
                mapLoading ? 'ЗАГРУЗКА...' : 'ПОСТРОИТЬ МАРШРУТ',
                style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: textMain,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientInfoCard(Map<String, dynamic> data) {
    final String? clientPhone = data['clientPhone'];
    final String clientAddress = data['clientAddress'] ?? data['address'] ?? data['dropoff']?['address'] ?? 'Адрес не указан';
    final String comment = data['comment'] ?? data['de'] ?? '';
    final String type = data['type'] ?? 'normal';

    final displayPrice = (type == 'normal')
        ? (data['deliveryPrice'] ?? 0)
        : (data['total'] ?? data['totalPrice'] ?? 0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: textMain.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _infoRow(Icons.person_outline_rounded, 'КЛИЕНТ', data['clientName'] ?? 'Не указано'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Divider(height: 1, color: borderColor),
          ),
          _infoRow(Icons.location_on_outlined, 'КУДА', clientAddress),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Divider(height: 1, color: borderColor),
          ),
          Row(
            children: [
              Expanded(child: _infoRow(Icons.phone_outlined, 'ТЕЛЕФОН', clientPhone ?? 'Нет номера')),
              if (clientPhone != null && clientPhone.isNotEmpty)
                IconButton(
                  onPressed: () => _makePhoneCall(clientPhone),
                  icon: const Icon(Icons.call_rounded, color: primaryBlue, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: primaryBlue.withOpacity(0.08),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Divider(height: 1, color: borderColor),
            ),
            _infoRow(Icons.comment_outlined, 'КОММЕНТАРИЙ', comment),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Divider(height: 1, color: borderColor),
          ),
          _infoRow(Icons.payment_outlined, type == 'normal' ? 'ВАШ ДОХОД' : 'СУММА', '$displayPrice Руб', isPrice: true),
        ],
      ),
    );
  }

  Widget _buildItemsCard(Map<String, dynamic> data) {
    final items = data['items'] as List<dynamic>? ?? [];
    if (items.isEmpty) return const SizedBox.shrink();

    final double itemsPrice = double.tryParse(data['itemsPrice']?.toString() ?? '') ?? 0.0;
    final double deliveryPrice = double.tryParse(data['deliveryPrice']?.toString() ?? '') ?? 0.0;
    final double total = double.tryParse(data['total']?.toString() ?? data['total_cost']?.toString() ?? '') ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: textMain.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'СОСТАВ ЗАКАЗА',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 1,
              color: textMuted,
            ),
          ),
          const SizedBox(height: 16),
          ...items.map((item) {
            final itemMap = item as Map<dynamic, dynamic>? ?? {};
            final int quantity = int.tryParse(itemMap['quantity']?.toString() ?? '1') ?? 1;
            final double price = double.tryParse(itemMap['price']?.toString() ?? '0') ?? 0.0;
            final String name = itemMap['name']?.toString() ?? 'Товар';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: primaryBlue.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text('${quantity}x', style: const TextStyle(fontWeight: FontWeight.w900, color: primaryBlue, fontSize: 12))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textMain))),
                  Text('${(price * quantity).toStringAsFixed(0)} Руб', style: const TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }),
          if (itemsPrice > 0 || deliveryPrice > 0 || total > 0) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: borderColor)),
            if (itemsPrice > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Товары', style: TextStyle(color: textMuted, fontSize: 13)),
                    Text('${itemsPrice.toStringAsFixed(0)} Руб', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              ),
            if (deliveryPrice > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Доставка', style: TextStyle(color: textMuted, fontSize: 13)),
                    Text('${deliveryPrice.toStringAsFixed(0)} Руб', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              ),
            if (total > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Итого к оплате', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: textMain)),
                  Text('${total.toStringAsFixed(2)} Руб', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: primaryBlue)),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusHistoryCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: textMain.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ХРОНОЛОГИЯ',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 1,
              color: textMuted,
            ),
          ),
          const SizedBox(height: 20),
          _statusStep('Принят', data['acceptedAt']),
          _statusStep('В пути', data['inProgressAt']),
          _statusStep('Доставлен', data['deliveredAt'], isLast: true),
        ],
      ),
    );
  }

  Widget _buildActionPanel(String status, Map<String, dynamic> data) {
    final String assignedCourierId = data['courierId'] ?? '';

    if (status == 'delivered') {
      return Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 34),
        decoration: BoxDecoration(
          color: cardBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border(top: BorderSide(color: borderColor, width: 1.5)),
        ),
        child: Container(
          height: 60,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: const Center(
            child: Text(
              '✅ ЗАКАЗ ВЫПОЛНЕН',
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 34),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: borderColor, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: textMain.withOpacity(0.05),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (assignedCourierId.isEmpty && (status == 'ready' || status == 'preparing' || status == 'new')) ...[
            _actionBtn('ПРИНЯТЬ ЗАКАЗ', primaryBlue, () => _takeAction('accepted')),
            const SizedBox(height: 12),
            TextButton(
              onPressed: loading ? null : () => _takeAction('cancelled'),
              child: const Text('Скрыть заказ', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ],
          if (assignedCourierId == widget.courierId) ...[
            if (status != 'inProgress')
              _actionBtn('НАЧАТЬ ДОСТАВКУ', const Color(0xFFD97706), () => _takeAction('inProgress'))
            else
              _actionBtn('ЗАВЕРШИТЬ ДОСТАВКУ', Colors.green[700]!, () => _takeAction('delivered')),
          ],
          if (assignedCourierId.isNotEmpty && assignedCourierId != widget.courierId)
            const Text('Заказ взят другим курьером', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _actionBtn(String title, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0
        ),
        child: loading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.white)),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {bool isPrice = false}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: surfaceBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Icon(icon, size: 20, color: textMain),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: isPrice ? primaryBlue : textMain,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusStep(String title, dynamic time, {bool isLast = false}) {
    bool isDone = time != null;
    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              Icon(
                isDone ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                size: 20,
                color: isDone ? Colors.green : borderColor,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isDone ? Colors.green : borderColor,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isDone ? FontWeight.w800 : FontWeight.w600,
                      color: isDone ? textMain : textMuted,
                    ),
                  ),
                  if (isDone && time is Timestamp)
                    Text(
                      DateFormat('HH:mm').format(time.toDate()),
                      style: const TextStyle(fontSize: 12, color: textMuted, fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

// ЭКРАН КАРТЫ
class DeliveryMapScreen extends StatefulWidget {
  final LatLng targetLocation;
  final String clientName;
  final LatLng? restaurantLocation;

  const DeliveryMapScreen({super.key, required this.targetLocation, required this.clientName, this.restaurantLocation});

  @override
  State<DeliveryMapScreen> createState() => _DeliveryMapScreenState();
}

class _DeliveryMapScreenState extends State<DeliveryMapScreen> {
  final MapController _mapController = MapController();
  List<LatLng> routePoints = [];
  bool isLoadingRoute = false;
  final String orsKey = '5b3ce3597851110001cf6248bf7b24ca801246a5913cae76ef354218';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _buildRouteWorkflow());
  }

  Future<void> _buildRouteWorkflow() async {
    if (widget.restaurantLocation == null) {
      _fitMarkers();
      return;
    }
    setState(() => isLoadingRoute = true);
    bool success = await _getRouteFromORS();
    if (!success) await _getRouteFromOSRM();
    if (mounted) {
      setState(() => isLoadingRoute = false);
      _fitMarkers();
    }
  }

  Future<bool> _getRouteFromORS() async {
    final url = 'https://api.openrouteservice.org/v2/directions/driving-car'
        '?api_key=$orsKey'
        '&start=${widget.restaurantLocation!.longitude},${widget.restaurantLocation!.latitude}'
        '&end=${widget.targetLocation.longitude},${widget.targetLocation.latitude}';
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final coords = data['features'][0]['geometry']['coordinates'] as List;
        setState(() {
          routePoints = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
        });
        return true;
      }
      return false;
    } catch (e) { return false; }
  }

  Future<bool> _getRouteFromOSRM() async {
    if (widget.restaurantLocation == null) return false;
    final url = 'https://router.project-osrm.org/route/v1/driving/'
        '${widget.restaurantLocation!.longitude},${widget.restaurantLocation!.latitude};'
        '${widget.targetLocation.longitude},${widget.targetLocation.latitude}'
        '?overview=full&geometries=geojson';
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final coords = data['routes'][0]['geometry']['coordinates'] as List;
        setState(() {
          routePoints = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
        });
        return true;
      }
      return false;
    } catch (e) { return false; }
  }

  void _fitMarkers() {
    List<LatLng> points = routePoints.isNotEmpty ? routePoints : [widget.targetLocation, if(widget.restaurantLocation != null) widget.restaurantLocation!];
    try {
      _mapController.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(80)));
    } catch (e) {
      debugPrint('Ошибка центрирования: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clientName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF0F172A))),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: widget.targetLocation, initialZoom: 14),
            children: [
              TileLayer(
                urlTemplate: 'https://map.99993.ru:1443/styles/openstreetmap/{z}/{x}/{y}.png',
              ),
              if (routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(points: routePoints, color: Colors.white, strokeWidth: 8.0),
                    Polyline(points: routePoints, color: const Color(0xFF2563EB), strokeWidth: 5.0),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (widget.restaurantLocation != null)
                    Marker(point: widget.restaurantLocation!, child: const Icon(Icons.location_on_rounded, color: Color(0xFF2563EB), size: 35)),
                  Marker(point: widget.targetLocation, child: const Icon(Icons.flag_circle_rounded, color: Colors.redAccent, size: 40)),
                ],
              ),
            ],
          ),
          if (isLoadingRoute)
            Container(
              color: Colors.black.withOpacity(0.15),
              child: const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB))),
            ),
        ],
      ),
    );
  }
}