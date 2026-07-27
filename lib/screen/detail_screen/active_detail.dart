import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

// Настройка для обхода проблем с сертификатами
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

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
  bool mapLoading = false;

  static const surfaceBackground = Color(0xFFF8FAFC);
  static const cardBackground = Color(0xFFFFFFFF);
  static const textMain = Color(0xFF0F172A);
  static const textMuted = Color(0xFF64748B);
  static const borderColor = Color(0xFFE2E8F0);
  static const primaryColor = Color(0xFF2563EB);

  @override
  void initState() {
    super.initState();
    HttpOverrides.global = MyHttpOverrides();
  }

  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) return;
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  double? _parseCoordinate(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  Future<void> _handleMapNavigation(Map<String, dynamic> data) async {
    setState(() => mapLoading = true);
    try {
      LatLng? restLocation;
      String shopId = data['shopId'] ?? '';

      // Ищем координаты заведения (откуда забрать)
      double? shopLat = _parseCoordinate(data['shopLat']) ?? _parseCoordinate(data['pickup']?['lat']);
      double? shopLng = _parseCoordinate(data['shopLng']) ?? _parseCoordinate(data['pickup']?['lon']);

      if (shopLat == null && shopId.isNotEmpty) {
        var shopSnap = await FirebaseFirestore.instance.collection('categories').doc(shopId).get();
        if (shopSnap.exists) {
          shopLat = _parseCoordinate(shopSnap.data()?['lat']);
          shopLng = _parseCoordinate(shopSnap.data()?['lng']);
        }
      }

      if (shopLat != null && shopLng != null) {
        restLocation = LatLng(shopLat, shopLng);
      }

      // Ищем координаты клиента (куда доставить)
      double? clientLat = _parseCoordinate(data['clientLat']) ?? _parseCoordinate(data['dropoff']?['lat']);
      double? clientLng = _parseCoordinate(data['clientLng']) ?? _parseCoordinate(data['dropoff']?['lon']);

      if (clientLat != null && clientLng != null) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderMapScreen(
              restaurantLocation: restLocation,
              targetLocation: LatLng(clientLat, clientLng),
              clientName: data['clientName'] ?? 'Клиент',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Координаты назначения не найдены')));
      }
    } catch (e) {
      debugPrint("Ошибка навигации: $e");
    } finally {
      if (mounted) setState(() => mapLoading = false);
    }
  }

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
      case 'pending': return 'Новый';
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

      final fullCombinedData = {...currentData, ...updateData};

      WriteBatch batch = FirebaseFirestore.instance.batch();

      // 1. Обновляем главный документ полными данными
      batch.set(widget.orderRef, fullCombinedData, SetOptions(merge: true));

      // 2. В историю курьера пишем полный объект
      batch.set(
          FirebaseFirestore.instance.collection('couriers').doc(widget.courierId).collection('history').doc(orderId),
          fullCombinedData,
          SetOptions(merge: true)
      );

      // 3. У пользователя тоже обновляем полной структурой
      if (currentData['userId'] != null) {
        batch.set(
            FirebaseFirestore.instance.collection('users').doc(currentData['userId']).collection('orders').doc(orderId),
            fullCombinedData,
            SetOptions(merge: true)
        );
      }

      // 4. В историю заведения
      if (shopId.isNotEmpty) {
        DocumentReference shopHistoryRef = FirebaseFirestore.instance.collection('categories').doc(shopId).collection('ordersHistory').doc(orderId);
        batch.set(shopHistoryRef, {...fullCombinedData, 'lastUpdateBy': 'courier'}, SetOptions(merge: true));
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Статус обновлен: ${_translateStatus(newStatus)}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: textMain,
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
      backgroundColor: surfaceBackground,
      appBar: AppBar(
        title: const Text('Детали заказа', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: textMain, letterSpacing: -0.5)),
        backgroundColor: cardBackground,
        foregroundColor: textMain,
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
        if (altSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: primaryColor));
        }
        if (!altSnapshot.hasData || !altSnapshot.data!.exists) {
          return const Center(child: Text('Заказ не найден', style: TextStyle(color: textMuted, fontWeight: FontWeight.w600)));
        }
        return _buildOrderContent(altSnapshot.data!.data() as Map<String, dynamic>);
      },
    );
  }

  Widget _buildOrderContent(Map<String, dynamic> orderData) {
    final String shopId = orderData['shopId'] ?? '';
    if (shopId.isEmpty) return _buildMainLayout(orderData, 'Индивидуальный заказ');

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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
    final String shortId = widget.orderRef.id.length > 6
        ? widget.orderRef.id.substring(widget.orderRef.id.length - 6).toUpperCase()
        : widget.orderRef.id.toUpperCase();

    return _cardWrapper(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ID ЗАКАЗА', style: TextStyle(fontSize: 10, color: textMuted, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                  const SizedBox(height: 2),
                  Text('#$shortId', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textMain, letterSpacing: 0.5)),
                ],
              ),
              _statusBadge(data['status']),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: borderColor)),
          _infoRow(
              Icons.storefront_rounded,
              shopLabel,
              data['restaurantName'] ?? data['shopName'] ?? 'Индивидуальная доставка',
              isMain: true
          ),
          const SizedBox(height: 12),
          _infoRow(Icons.access_time_rounded, 'Время создания', _formatDate(data['createdAt'])),
        ],
      ),
    );
  }

  Widget _buildClientCard(Map<String, dynamic> data) {
    final String? phone = data['clientPhone'];
    final String comment = data['comment'] ?? data['de'] ?? '';

    final String clientAddress = data['clientAddress'] ?? data['address'] ?? data['dropoff']?['address'] ?? 'Адрес не указан';
    final String pickupAddress = data['pickup']?['address'] ?? '';
    final String clientName = data['clientName'] ?? 'Без имени';

    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ИНФОРМАЦИЯ О ДОСТАВКЕ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 0.8)),
          const SizedBox(height: 16),
          _infoRow(Icons.person_rounded, 'Получатель', clientName),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _infoRow(Icons.phone_rounded, 'Контактный номер', phone ?? '-')),
              if (phone != null && phone.isNotEmpty)
                IconButton(
                  onPressed: () => _makePhoneCall(phone),
                  icon: const Icon(Icons.call_rounded, color: Color(0xFF10B981), size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981).withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),

          if (pickupAddress.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoRow(Icons.trip_origin_rounded, 'Адрес забора (Откуда)', pickupAddress, color: const Color(0xFF3B82F6)),
          ],

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _infoRow(Icons.location_on_rounded, 'КУДА (АДРЕС)', clientAddress, color: primaryColor)),
              IconButton(
                onPressed: mapLoading ? null : () => _handleMapNavigation(data),
                icon: mapLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor))
                    : const Icon(Icons.map_outlined, color: primaryColor, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: primaryColor.withOpacity(0.1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),

          if (comment.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: borderColor)),
            _infoRow(Icons.comment_outlined, 'Комментарий к заказу', comment, color: const Color(0xFFF59E0B)),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsCard(Map<String, dynamic> data) {
    final items = data['items'] as List<dynamic>? ?? [];

    final double itemsPrice = double.tryParse(data['itemsPrice']?.toString() ?? '') ?? 0.0;
    final double deliveryPrice = double.tryParse(data['deliveryPrice']?.toString() ?? '') ?? 0.0;
    final double total = double.tryParse(data['total']?.toString() ?? data['total_cost']?.toString() ?? '') ?? 0.0;

    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('СОСТАВ ЗАКАЗА', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 0.8)),
          const SizedBox(height: 16),

          if (items.isNotEmpty) ...[
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
                      decoration: BoxDecoration(color: primaryColor.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                      child: Center(child: Text('${quantity}x', style: const TextStyle(fontWeight: FontWeight.w900, color: primaryColor, fontSize: 12))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textMain))),
                    Text('${(price * quantity).toStringAsFixed(0)} Руб', style: const TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }),
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: borderColor)),
          ] else ...[
            const Text('Индивидуальная заявка (без списка товаров)', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: borderColor)),
          ],

          if (itemsPrice > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Стоимость товаров', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${itemsPrice.toStringAsFixed(0)} Руб', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textMain)),
              ],
            ),
            const SizedBox(height: 8),
          ],

          if (deliveryPrice > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Доставка', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${deliveryPrice.toStringAsFixed(0)} Руб', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textMain)),
              ],
            ),
            const SizedBox(height: 8),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ИТОГО', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: textMain)),
              Text(
                  '${total.toStringAsFixed(2)} Руб',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF059669))
              ),
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
      return _actionButton('ПРИНЯТЬ ЗАКАЗ', const Color(0xFF059669), 'accepted', currentData);
    }

    if (assignedCourierId == widget.courierId) {
      if (status == 'inProgress') {
        return _actionButton('ПОДТВЕРДИТЬ ДОСТАВКУ', primaryColor, 'delivered', currentData);
      } else {
        return _actionButton('НАЧАТЬ ДОСТАВКУ', const Color(0xFF3B82F6), 'inProgress', currentData);
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      child: const Center(
          child: Text('Заказ уже взят другим курьером', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w800, fontSize: 13))
      ),
    );
  }

  Widget _actionButton(String text, Color color, String nextStatus, Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 35),
      decoration: BoxDecoration(
        color: cardBackground,
        boxShadow: [
          BoxShadow(
            color: textMain.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: loading ? null : () => _updateStatus(nextStatus, data),
          child: loading
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5)),
        ),
      ),
    );
  }

  Widget _cardWrapper({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: textMain.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {bool isMain = false, Color? color}) {
    final activeColor = color ?? textMuted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: activeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)
          ),
          child: Icon(icon, size: 18, color: activeColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Text(
                  value,
                  style: TextStyle(
                    fontSize: isMain ? 16 : 13,
                    fontWeight: isMain ? FontWeight.w900 : FontWeight.w700,
                    color: textMain,
                  )
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String? status) {
    Color color;
    String text = _translateStatus(status ?? 'new');
    switch (status) {
      case 'accepted': color = const Color(0xFF059669); break;
      case 'preparing': color = const Color(0xFF3B82F6); break;
      case 'ready': color = const Color(0xFF10B981); break;
      case 'inProgress': color = const Color(0xFF3B82F6); break;
      case 'delivered': color = primaryColor; break;
      case 'pending': color = const Color(0xFFF59E0B); break;
      default: color = textMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Text(text.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
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
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: isDone ? primaryColor : cardBackground,
                  border: Border.all(color: isDone ? primaryColor : borderColor, width: 2),
                  shape: BoxShape.circle,
                ),
                child: isDone ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
              ),
              if (!isLast) Expanded(child: VerticalDivider(color: isDone ? primaryColor : borderColor, thickness: 2, width: 2)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: TextStyle(fontWeight: isDone ? FontWeight.w700 : FontWeight.w600, color: isDone ? textMain : textMuted, fontSize: 13)),
                  if (isDone) Text(DateFormat('HH:mm').format(time.toDate()), style: const TextStyle(color: primaryColor, fontWeight: FontWeight.w800, fontSize: 12)),
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

// ЭКРАН КАРТЫ С ВАШИМ OPENSTREETMAP И МАРШРУТОМ
class OrderMapScreen extends StatefulWidget {
  final LatLng? restaurantLocation;
  final LatLng targetLocation;
  final String clientName;

  const OrderMapScreen({super.key, this.restaurantLocation, required this.targetLocation, required this.clientName});

  @override
  State<OrderMapScreen> createState() => _OrderMapScreenState();
}

class _OrderMapScreenState extends State<OrderMapScreen> {
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
    if (widget.restaurantLocation == null) return false;
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

  Future<void> _getRouteFromOSRM() async {
    if (widget.restaurantLocation == null) return;
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
      }
    } catch (e) { debugPrint('$e'); }
  }

  void _fitMarkers() {
    List<LatLng> points = routePoints.isNotEmpty
        ? routePoints
        : [widget.targetLocation, if (widget.restaurantLocation != null) widget.restaurantLocation!];
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
        title: Text('Маршрут: ${widget.clientName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
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
          Positioned(
            bottom: 30, right: 20,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              onPressed: _fitMarkers,
              child: const Icon(Icons.center_focus_strong, color: Color(0xFF0F172A)),
            ),
          )
        ],
      ),
    );
  }
}