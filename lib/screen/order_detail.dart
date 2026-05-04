import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
// Добавляем пакет для звонков
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

  @override
  void initState() {
    super.initState();
    HttpOverrides.global = MyHttpOverrides();
  }

  // Функция для совершения звонка
  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) return;
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
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

  // --- ИСПРАВЛЕННАЯ ЛОГИКА ТРАНЗАКЦИИ (БЕЗ ИЗМЕНЕНИЙ) ---
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
          if (existingCourierId.isNotEmpty) {
            throw Exception('Вы уже приняли этот заказ');
          }
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

          transaction.set(courierHistoryRef, {
            ...freshData,
            ...updateData,
          }, SetOptions(merge: true));

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
          SnackBar(content: Text('Статус обновлен: ${_statusTranslations[action] ?? action}'), backgroundColor: Colors.deepOrange),
        );
        if (action == 'delivered') Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: ${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red)
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
      if (shopId.isNotEmpty) {
        final shopSnap = await FirebaseFirestore.instance.collection('categories').doc(shopId).get();
        if (shopSnap.exists) {
          final sData = shopSnap.data()!;
          double? lat = _parseCoordinate(sData['lat']);
          double? lng = _parseCoordinate(sData['lng']);
          if (lat != null && lng != null) restLocation = LatLng(lat, lng);
        }
      }
      double? clientLat = _parseCoordinate(orderData['clientLat']);
      double? clientLng = _parseCoordinate(orderData['clientLng']);

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
      }
    } finally {
      if (mounted) setState(() => mapLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Детали доставки', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: widget.orderRef.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (!snapshot.data!.exists) return const Center(child: Text('Заказ не найден'));

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final String currentStatus = data['status'] ?? 'new';
          final Timestamp? estimatedReadyTime = data['estimatedReadyTime'] as Timestamp?;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
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
                      _buildStatusHistoryCard(data),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Заказ готовится. Ориентировочное время готовности: ${DateFormat('HH:mm').format(time.toDate())}',
              style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.deepOrange.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.restaurant, color: Colors.deepOrange),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ОТКУДА ЗАБРАТЬ', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                    Text(data['restaurantName'] ?? 'Заведение', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 30),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: mapLoading ? null : () => _handleMapNavigation(data),
              icon: mapLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.map_outlined, color: Colors.white),
              label: Text(mapLoading ? 'ЗАГРУЗКА...' : 'ПОСТРОИТЬ МАРШРУТ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          _infoRow(Icons.person_pin_circle_outlined, 'КЛИЕНТ', data['clientName'] ?? 'Не указано'),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(child: _infoRow(Icons.phone_iphone_outlined, 'ТЕЛЕФОН', clientPhone ?? 'Нет номера')),
              if (clientPhone != null && clientPhone.isNotEmpty)
                IconButton(
                  onPressed: () => _makePhoneCall(clientPhone),
                  icon: const Icon(Icons.call, color: Colors.green),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.green.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
          const Divider(height: 20),
          _infoRow(Icons.payment_outlined, 'СУММА', '${data['total'] ?? 0} Руб', isPrice: true),
        ],
      ),
    );
  }

  Widget _buildStatusHistoryCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ХРОНОЛОГИЯ', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
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
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 35),
        child: const Center(child: Text('✅ ЗАКАЗ ВЫПОЛНЕН', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 18))),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 35),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (assignedCourierId.isEmpty && (status == 'ready' || status == 'preparing' || status == 'new')) ...[
            _actionBtn('ПРИНЯТЬ ЗАКАЗ', Colors.deepOrange, () => _takeAction('accepted')),
            const SizedBox(height: 8),
            TextButton(
                onPressed: loading ? null : () => _takeAction('cancelled'),
                child: const Text('Скрыть заказ', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
            ),
          ],

          if (assignedCourierId == widget.courierId) ...[
            if (status != 'inProgress')
              _actionBtn('НАЧАТЬ ДОСТАВКУ', Colors.orange, () => _takeAction('inProgress'))
            else
              _actionBtn('ЗАВЕРШИТЬ ДОСТАВКУ', Colors.green, () => _takeAction('delivered')),
          ],

          if (assignedCourierId.isNotEmpty && assignedCourierId != widget.courierId)
            const Text('Заказ взят другим курьером', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: 0
        ),
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {bool isPrice = false}) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueGrey[300], size: 22),
        const SizedBox(width: 15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isPrice ? Colors.deepOrange : Colors.black)),
          ],
        ),
      ],
    );
  }

  Widget _statusStep(String title, dynamic time, {bool isLast = false}) {
    bool isDone = time != null;
    return Row(
      children: [
        Column(
          children: [
            Icon(isDone ? Icons.check_circle : Icons.radio_button_unchecked, color: isDone ? Colors.deepOrange : Colors.grey[300], size: 20),
            if (!isLast) Container(width: 2, height: 20, color: isDone ? Colors.deepOrange : Colors.grey[200]),
          ],
        ),
        const SizedBox(width: 15),
        Text(title, style: TextStyle(color: isDone ? Colors.black : Colors.grey, fontWeight: isDone ? FontWeight.bold : FontWeight.normal)),
        const Spacer(),
        if (isDone) Text(DateFormat('HH:mm').format((time as Timestamp).toDate()), style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

// ЭКРАН КАРТЫ (БЕЗ ИЗМЕНЕНИЙ)
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

  Future<void> _getRouteFromOSRM() async {
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
    List<LatLng> points = routePoints.isNotEmpty ? routePoints : [widget.targetLocation, if(widget.restaurantLocation != null) widget.restaurantLocation!];
    _mapController.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(80)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.clientName), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: widget.targetLocation, initialZoom: 14),
            children: [
              TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd']
              ),
              if (routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(points: routePoints, color: Colors.white, strokeWidth: 8.0),
                    Polyline(points: routePoints, color: Colors.indigoAccent, strokeWidth: 5.0),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (widget.restaurantLocation != null)
                    Marker(point: widget.restaurantLocation!, child: const Icon(Icons.restaurant, color: Colors.indigo, size: 35)),
                  Marker(point: widget.targetLocation, child: const Icon(Icons.flag_circle, color: Colors.redAccent, size: 40)),
                ],
              ),
            ],
          ),
          if (isLoadingRoute) const Center(child: CircularProgressIndicator(color: Colors.indigoAccent)),
        ],
      ),
    );
  }
}