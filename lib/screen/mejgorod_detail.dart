import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

class IntercityOrderDetailScreen extends StatefulWidget {
  final DocumentReference orderRef;
  final String courierPhone;
  final String courierId;

  const IntercityOrderDetailScreen({
    super.key,
    required this.orderRef,
    required this.courierPhone,
    required this.courierId,
  });

  @override
  State<IntercityOrderDetailScreen> createState() => _IntercityOrderDetailScreenState();
}

class _IntercityOrderDetailScreenState extends State<IntercityOrderDetailScreen> {
  bool loading = false;
  bool mapLoading = false;

  @override
  void initState() {
    super.initState();
    HttpOverrides.global = MyHttpOverrides();
  }

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

  // --- ЛОГИКА ОБНОВЛЕНИЯ СТАТУСОВ (СИНХРОННО В 3 МЕСТАХ) ---
  Future<void> _takeAction(String action, Map<String, dynamic> data) async {
    setState(() => loading = true);
    try {
      final userId = data['userId'];
      if (userId == null) throw Exception('ID пользователя не найден');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot freshSnap = await transaction.get(widget.orderRef);
        if (!freshSnap.exists) throw Exception('Заказ не найден');

        final freshData = freshSnap.data() as Map<String, dynamic>;

        if (action == 'accepted' && freshData['status'] != 'new') {
          throw Exception('Этот заказ уже взял другой курьер!');
        }

        final actionTime = FieldValue.serverTimestamp();

        Map<String, dynamic> updateData = {
          'status': action,
          'courierId': widget.courierId,
          'courierPhone': widget.courierPhone,
          'updatedAt': actionTime,
        };

        if (action == 'accepted' && freshData['acceptedAt'] == null) updateData['acceptedAt'] = actionTime;
        if (action == 'inProgress' && freshData['inProgressAt'] == null) updateData['inProgressAt'] = actionTime;
        if (action == 'delivered') {
          if (freshData['acceptedAt'] == null) updateData['acceptedAt'] = actionTime;
          if (freshData['inProgressAt'] == null) updateData['inProgressAt'] = actionTime;
          updateData['deliveredAt'] = actionTime;
        }

        transaction.update(widget.orderRef, updateData);

        DocumentReference clientOrderRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('mejCityOrders')
            .doc(widget.orderRef.id);

        transaction.set(clientOrderRef, updateData, SetOptions(merge: true));

        if (['accepted', 'inProgress', 'delivered'].contains(action)) {
          DocumentReference historyRef = FirebaseFirestore.instance
              .collection('couriers')
              .doc(widget.courierId)
              .collection('history')
              .doc(widget.orderRef.id);

          transaction.set(historyRef, {
            ...freshData,
            ...updateData,
            'type': 'mejCity',
            'actionAt': actionTime,
          }, SetOptions(merge: true));
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Статус обновлён: ${_statusToRussian(action)}'),
            backgroundColor: Colors.indigo[900],
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString().contains('уже взял другой')
            ? 'Этот заказ уже взял другой курьер!'
            : 'Ошибка: $e';

        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage), backgroundColor: Colors.red)
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

  // --- ИСПРАВЛЕННЫЙ МЕТОД: ЗАЩИТА ОТ КРАША ТИПА GEOPOINT И MAP ---
  Future<void> _handleMapNavigation(Map<String, dynamic> orderData) async {
    setState(() => mapLoading = true);
    try {
      double? startLat;
      double? startLng;
      double? endLat;
      double? endLng;

      // 1. Извлекаем pickup (обрабатываем и GeoPoint, и Map)
      final pickupData = orderData['pickup'];
      if (pickupData != null) {
        if (pickupData is GeoPoint) {
          startLat = pickupData.latitude;
          startLng = pickupData.longitude;
        } else if (pickupData is Map) {
          startLat = (pickupData['lat'] as num?)?.toDouble();
          startLng = (pickupData['lng'] as num?)?.toDouble();
        }
      }

      // 2. Извлекаем dropoff (обрабатываем и GeoPoint, и Map)
      final dropoffData = orderData['dropoff'];
      if (dropoffData != null) {
        if (dropoffData is GeoPoint) {
          endLat = dropoffData.latitude;
          endLng = dropoffData.longitude;
        } else if (dropoffData is Map) {
          endLat = (dropoffData['lat'] as num?)?.toDouble();
          endLng = (dropoffData['lng'] as num?)?.toDouble();
        }
      }

      // 3. Запасной вариант: проверяем плоские поля в корне документа
      startLat ??= (orderData['startLat'] as num?)?.toDouble() ?? (orderData['pickupLat'] as num?)?.toDouble();
      startLng ??= (orderData['startLng'] as num?)?.toDouble() ?? (orderData['pickupLng'] as num?)?.toDouble();
      endLat ??= (orderData['endLat'] as num?)?.toDouble() ?? (orderData['dropoffLat'] as num?)?.toDouble();
      endLng ??= (orderData['endLng'] as num?)?.toDouble() ?? (orderData['dropoffLng'] as num?)?.toDouble();

      // Строим маршрут только если нашли обе точки
      if (startLat != null && startLng != null && endLat != null && endLng != null) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IntercityMapScreen(
              startLocation: LatLng(startLat!, startLng!),
              targetLocation: LatLng(endLat!, endLng!),
              clientName: orderData['clientName'] ?? 'Клиент',
            ),
          ),
        );
      } else {
        throw Exception('Координаты маршрута "Откуда/Куда" не найдены в заказе.');
      }
    } catch (e) {
      debugPrint("Ошибка навигации: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка открытия карты: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => mapLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('МЕЖГОРОДСКОЙ ЗАКАЗ', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 14)),
        centerTitle: true,
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: widget.orderRef.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator());

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'new';

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Column(
                    children: [
                      _buildMainCard(data),
                      const SizedBox(height: 16),
                      _buildClientInfoCard(data, status),
                      const SizedBox(height: 16),
                      _buildRouteTimeline(data),
                      const SizedBox(height: 16),
                      _buildTimelineCard(data),
                    ],
                  ),
                ),
              ),
              _buildBottomActionPanel(status, data),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMainCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Межгород', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.indigo[50], borderRadius: BorderRadius.circular(12)),
                child: Text('${data['totalPrice'] ?? 0} Руб',
                    style: TextStyle(color: Colors.indigo[900], fontWeight: FontWeight.w900, fontSize: 18)),
              )
            ],
          ),
          const Divider(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: mapLoading ? null : () => _handleMapNavigation(data),
              icon: mapLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.map_outlined),
              label: const Text('ОТКРЫТЬ НАВИГАТОР', style: TextStyle(fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo[800],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientInfoCard(Map<String, dynamic> data, String status) {
    final String? phone = data['clientPhone'];
    final bool isAccepted = status != 'new' && status != 'cancelled';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoTile(Icons.person_outline, 'ОТПРАВИТЕЛЬ', data['clientName'] ?? '-'),
          const SizedBox(height: 12),
          _infoTile(Icons.phone_outlined, 'ТЕЛЕФОН', phone ?? '-'),

          if (isAccepted && phone != null && phone.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _makePhoneCall(phone),
                icon: const Icon(Icons.call, size: 20),
                label: const Text('ПОЗВОНИТЬ КЛИЕНТУ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.indigo[800],
                  side: BorderSide(color: Colors.indigo[800]!, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
          ],

          if (data['comment']?.isNotEmpty == true) ...[
            const Divider(height: 24),
            _infoTile(Icons.chat_bubble_outline, 'КОММЕНТАРИЙ', data['comment']),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (data['bodySize'] != null) _tagChip('Транспорт: ${data['bodySize']}'),
              if (data['loaders'] != null) _tagChip('Грузчики: ${data['loaders']}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.indigo[700]),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        )
      ],
    );
  }

  Widget _tagChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.indigo[50], borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: Colors.indigo[900], fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildRouteTimeline(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        children: [
          _routePoint(Icons.circle, Colors.indigo, 'ОТКУДА', data['fromAddress'] ?? 'По координатам'),
          Container(margin: const EdgeInsets.only(left: 10), height: 25, width: 2, color: Colors.grey[100]),
          _routePoint(Icons.location_on, Colors.red, 'КУДА', data['toAddress'] ?? 'По координатам'),
        ],
      ),
    );
  }

  Widget _routePoint(IconData icon, Color color, String title, String sub) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: Colors.grey)),
              Text(sub, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildTimelineCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        children: [
          _statusStep('Принят', data['acceptedAt']),
          _statusStep('В пути', data['inProgressAt']),
          _statusStep('Доставлен', data['deliveredAt'], isLast: true),
        ],
      ),
    );
  }

  Widget _statusStep(String title, dynamic time, {bool isLast = false}) {
    bool done = time != null;
    return Row(
      children: [
        Column(
          children: [
            Icon(done ? Icons.check_circle : Icons.radio_button_off, size: 18, color: done ? Colors.green : Colors.grey[200]),
            if (!isLast) Container(width: 2, height: 20, color: Colors.grey[100]),
          ],
        ),
        const SizedBox(width: 16),
        Text(title, style: TextStyle(color: done ? Colors.black : Colors.grey, fontWeight: done ? FontWeight.bold : FontWeight.normal)),
        const Spacer(),
        if (done) Text(DateFormat('HH:mm').format((time as Timestamp).toDate()), style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildBottomActionPanel(String status, Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(35))),
      child: _buildActionButton(status, data),
    );
  }

  Widget _buildActionButton(String status, Map<String, dynamic> data) {
    if (status == 'delivered') {
      return Container(
        height: 60, width: double.infinity,
        decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(18)),
        child: const Center(child: Text('✅ ВЫПОЛНЕНО', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900))),
      );
    }

    String text = ''; Color color = Colors.indigo[700]!; String nextStatus = '';
    if (status == 'new') { text = 'ПРИНЯТЬ ЗАКАЗ'; nextStatus = 'accepted'; }
    else if (status == 'accepted') { text = 'В ПУТИ'; color = Colors.blue; nextStatus = 'inProgress'; }
    else if (status == 'inProgress') { text = 'ЗАВЕРШИТЬ / ДОСТАВЛЕНО'; color = Colors.green[700]!; nextStatus = 'delivered'; }

    return SizedBox(
      width: double.infinity, height: 65,
      child: ElevatedButton(
        onPressed: loading ? null : () => _takeAction(nextStatus, data),
        style: ElevatedButton.styleFrom(backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0),
        child: loading ? const CircularProgressIndicator(color: Colors.white) : Text(text, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
      ),
    );
  }
}

// --- КЛАСС КАРТЫ С ОБНОВЛЕННЫМ ДИНАМИЧЕСКИМ ИМЕНЕМ ПАРАМЕТРА (startLocation ОБЯЗАТЕЛЕН) ---
class IntercityMapScreen extends StatefulWidget {
  final LatLng targetLocation;
  final String clientName;
  final LatLng startLocation;

  const IntercityMapScreen({
    super.key,
    required this.targetLocation,
    required this.clientName,
    required this.startLocation,
  });

  @override
  State<IntercityMapScreen> createState() => _IntercityMapScreenState();
}

class _IntercityMapScreenState extends State<IntercityMapScreen> {
  final MapController _mapController = MapController();
  List<LatLng> routePoints = [];
  bool isLoadingRoute = false;
  final String orsKey = '5b3ce3597851110001cf6248bf7b24ca801246a5913cae76ef354218';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _buildRoute());
  }

  Future<void> _buildRoute() async {
    setState(() => isLoadingRoute = true);
    bool success = await _fetchORS();
    if (!success) await _fetchOSRM();
    if (mounted) {
      setState(() => isLoadingRoute = false);
      _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([widget.startLocation, widget.targetLocation]),
          padding: const EdgeInsets.all(80)
      ));
    }
  }

  Future<bool> _fetchORS() async {
    final url = 'https://api.openrouteservice.org/v2/directions/driving-car?api_key=$orsKey&start=${widget.startLocation.longitude},${widget.startLocation.latitude}&end=${widget.targetLocation.longitude},${widget.targetLocation.latitude}';
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final coords = json.decode(r.body)['features'][0]['geometry']['coordinates'] as List;
        setState(() => routePoints = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList());
        return true;
      }
      return false;
    } catch (e) { return false; }
  }

  Future<void> _fetchOSRM() async {
    final url = 'https://router.project-osrm.org/route/v1/driving/${widget.startLocation.longitude},${widget.startLocation.latitude};${widget.targetLocation.longitude},${widget.targetLocation.latitude}?overview=full&geometries=geojson';
    try {
      final r = await http.get(Uri.parse(url));
      if (r.statusCode == 200) {
        final coords = json.decode(r.body)['routes'][0]['geometry']['coordinates'] as List;
        setState(() => routePoints = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList());
      }
    } catch (e) { debugPrint('$e'); }
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
              TileLayer(urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', subdomains: const ['a', 'b', 'c', 'd']),
              if (routePoints.isNotEmpty)
                PolylineLayer(
                    polylines: [
                      Polyline(points: routePoints, color: Colors.indigo, strokeWidth: 5.0)
                    ]
                ),
              MarkerLayer(markers: [
                Marker(point: widget.startLocation, child: const Icon(Icons.location_on, color: Colors.indigo, size: 35)),
                Marker(point: widget.targetLocation, child: const Icon(Icons.flag_circle, color: Colors.red, size: 40)),
              ]),
            ],
          ),
          if (isLoadingRoute) const Center(child: CircularProgressIndicator(color: Colors.indigo)),
        ],
      ),
    );
  }
}