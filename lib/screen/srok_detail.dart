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
  bool mapLoading = false;

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
      debugPrint('Ошибка при звонке: $e');
    }
  }

  Future<void> _takeAction(String action) async {
    setState(() => loading = true);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot freshSnap = await transaction.get(widget.orderRef);
        if (!freshSnap.exists) throw Exception('Заказ не найден');

        final freshData = freshSnap.data() as Map<String, dynamic>;
        final userId = freshData['userId'];
        if (userId == null) throw Exception('ID пользователя не найден');

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
            .collection('delivery_orders')
            .doc(widget.orderRef.id);

        transaction.update(clientOrderRef, updateData);

        if (['accepted', 'inProgress', 'delivered'].contains(action)) {
          DocumentReference historyRef = FirebaseFirestore.instance
              .collection('couriers')
              .doc(widget.courierId)
              .collection('history')
              .doc(widget.orderRef.id);

          transaction.set(historyRef, {
            ...freshData,
            ...updateData,
            'type': 'delivery',
            'actionAt': actionTime,
          }, SetOptions(merge: true));
        }
      });

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
        String errorText = e.toString().contains('уже взял другой')
            ? 'Этот заказ уже занят!'
            : 'Ошибка: $e';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorText), backgroundColor: Colors.red)
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

  Future<void> _handleMapNavigation(Map<String, dynamic> orderData) async {
    setState(() => mapLoading = true);
    try {
      final pickup = orderData['pickup'] as Map<String, dynamic>?;
      final dropoff = orderData['dropoff'] as Map<String, dynamic>?;

      if (dropoff != null && pickup != null) {
        double startLat = (pickup['lat'] as num).toDouble();
        double startLng = (pickup['lng'] as num).toDouble();
        double endLat = (dropoff['lat'] as num).toDouble();
        double endLng = (dropoff['lng'] as num).toDouble();

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DeliveryMapScreen(
              targetLocation: LatLng(endLat, endLng),
              clientName: orderData['clientName'] ?? 'Клиент',
              restaurantLocation: LatLng(startLat, startLng),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Ошибка навигации: $e");
    } finally {
      if (mounted) setState(() => mapLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text('ДЕТАЛИ ЗАКАЗА', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 14)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
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
                      _buildMainStatusCard(data),
                      const SizedBox(height: 16),
                      _buildInfoSection(data, status),
                      const SizedBox(height: 16),
                      _buildAddressTimeline(data),
                      const SizedBox(height: 16),
                      _buildTimelineCard(data),
                      const SizedBox(height: 30),
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

  Widget _buildMainStatusCard(Map<String, dynamic> data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20), // Уменьшили общий паддинг для компактности
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded( // Текст теперь не выталкивает цену
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ЗАКАЗ #${widget.orderRef.id.substring(0, 6).toUpperCase()}',
                      style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Срочная доставка',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container( // Компактная рамочка для цены
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${data['totalCost'] ?? 0} Руб',
                  style: TextStyle(color: Colors.red[900], fontWeight: FontWeight.w900, fontSize: 16),
                ),
              )
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider()),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: mapLoading ? null : () => _handleMapNavigation(data),
              icon: mapLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.directions_outlined, size: 20),
              label: const Text('ОТКРЫТЬ НАВИГАТОР', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
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

  Widget _buildInfoSection(Map<String, dynamic> data, String status) {
    final String? phone = data['clientPhone'];
    final bool canCall = status != 'new' && status != 'cancelled';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        children: [
          _modernInfoRow(Icons.person_outline, 'КЛИЕНТ', data['clientName'] ?? 'Не указан'),
          const SizedBox(height: 16),
          _modernInfoRow(Icons.phone_outlined, 'КОНТАКТ', phone ?? 'Нет номера'),

          if (canCall && phone != null && phone.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _makePhoneCall(phone),
                icon: const Icon(Icons.call, size: 20),
                label: const Text('ПОЗВОНИТЬ КЛИЕНТУ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[900],
                  side: BorderSide(color: Colors.red[900]!, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modernInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: Colors.black87),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildAddressTimeline(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        children: [
          _addressItem(Icons.circle, Colors.green, 'ТОЧКА ЗАБОРА', 'Забрать посылку по координатам'),
          Container(
            margin: const EdgeInsets.only(left: 11),
            height: 30,
            width: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.green, Colors.red[900]!]),
            ),
          ),
          _addressItem(Icons.location_on, Colors.red[900]!, 'ТОЧКА ДОСТАВКИ', 'Доставить клиенту'),
        ],
      ),
    );
  }

  Widget _addressItem(IconData icon, Color color, String title, String sub) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
              Text(sub, style: TextStyle(color: Colors.grey[500], fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('СТАТУС ВЫПОЛНЕНИЯ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1, color: Colors.grey)),
          const SizedBox(height: 20),
          _modernStatusStep('Заказ принят', data['acceptedAt']),
          _modernStatusStep('Курьер в пути', data['inProgressAt']),
          _modernStatusStep('Доставлено клиенту', data['deliveredAt'], isLast: true),
        ],
      ),
    );
  }

  Widget _modernStatusStep(String title, dynamic time, {bool isLast = false}) {
    bool isDone = time != null;
    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              Icon(isDone ? Icons.check_circle : Icons.radio_button_off, size: 18, color: isDone ? Colors.green : Colors.grey[200]),
              if (!isLast) Expanded(child: Container(width: 2, color: isDone ? Colors.green : Colors.grey[100])),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: isDone ? FontWeight.bold : FontWeight.normal, color: isDone ? Colors.black : Colors.grey)),
                  if (isDone) Text(DateFormat('HH:mm').format((time as Timestamp).toDate()), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBottomPanel(String status, Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: _buildActionButton(status),
    );
  }

  Widget _buildActionButton(String status) {
    if (status == 'delivered') {
      return Container(
        height: 60,
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(18)),
        child: const Center(child: Text('✅ ДОСТАВЛЕНО', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900))),
      );
    }

    String text = '';
    Color color = Colors.black;
    String nextStatus = '';

    if (status == 'new') { text = 'ПРИНЯТЬ ЗАКАЗ'; color = Colors.red[900]!; nextStatus = 'accepted'; }
    else if (status == 'accepted') { text = 'НАЧАТЬ ПУТЬ'; color = Colors.orange[800]!; nextStatus = 'inProgress'; }
    else if (status == 'inProgress') { text = 'ПОДТВЕРДИТЬ ДОСТАВКУ'; color = Colors.green[700]!; nextStatus = 'delivered'; }

    return SizedBox(
      width: double.infinity,
      height: 65,
      child: ElevatedButton(
        onPressed: loading ? null : () => _takeAction(nextStatus),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),
      ),
    );
  }
}

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
                    Marker(point: widget.restaurantLocation!, child: const Icon(Icons.location_on, color: Colors.indigo, size: 35)),
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
