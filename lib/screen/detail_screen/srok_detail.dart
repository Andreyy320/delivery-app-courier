import 'dart:ui';
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
            backgroundColor: textMain,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            SnackBar(
              content: Text(errorText),
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

      // Безопасное извлечение координат с поддержкой разных типов (num / String)
      double? parseCoord(dynamic val) {
        if (val == null) return null;
        if (val is num) return val.toDouble();
        if (val is String) return double.tryParse(val);
        return null;
      }

      LatLng? dropoffPoint;
      if (dropoff != null) {
        double? lat = parseCoord(dropoff['lat']);
        double? lng = parseCoord(dropoff['lon']);
        if (lat != null && lng != null) {
          dropoffPoint = LatLng(lat, lng);
        }
      }

      LatLng? pickupPoint;
      if (pickup != null) {
        double? lat = parseCoord(pickup['lat']);
        double? lng = parseCoord(pickup['lon']);
        if (lat != null && lng != null) {
          pickupPoint = LatLng(lat, lng);
        }
      }

      // Если dropoff нет, но есть в корне заказа старые поля lat/lon
      if (dropoffPoint == null) {
        double? lat = parseCoord(orderData['lat'] ?? orderData['latitude']);
        double? lng = parseCoord(orderData['lon'] ?? orderData['longitude']);
        if (lat != null && lng != null) {
          dropoffPoint = LatLng(lat, lng);
        }
      }

      if (dropoffPoint != null) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DeliveryMapScreen(
              targetLocation: dropoffPoint!,
              clientName: orderData['clientName'] ?? orderData['name'] ?? 'Клиент',
              restaurantLocation: pickupPoint,
            ),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Координаты точки доставки не найдены в заказе')),
          );
        }
      }
    } catch (e) {
      debugPrint("Ошибка навигации: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть карту: $e')),
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
          'ДЕТАЛИ ЗАКАЗА',
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
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator(color: primaryBlue));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'new';

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    children: [
                      _buildMainStatusCard(data),
                      const SizedBox(height: 16),
                      if (data['comment'] != null && data['comment'].toString().trim().isNotEmpty) ...[
                        _buildCommentCard(data['comment'].toString()),
                        const SizedBox(height: 16),
                      ],
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
    final rawCost = data['total_cost'] ?? data['totalPrice'] ?? data['totalCost'] ?? 0;
    final totalCost = (rawCost is num) ? rawCost.toStringAsFixed(2) : rawCost.toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: textMain.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ЗАКАЗ #${widget.orderRef.id.substring(0, 6).toUpperCase()}',
                      style: const TextStyle(
                        color: textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Срочная доставка',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: textMain),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: primaryBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '$totalCost Руб',
                  style: const TextStyle(
                    color: primaryBlue,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              )
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
              label: const Text(
                'ОТКРЫТЬ НАВИГАТОР',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8, fontSize: 13),
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

  Widget _buildCommentCard(String comment) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFFD97706), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ЧТО ЗАБРАТЬ?',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  comment,
                  style: const TextStyle(
                    color: Color(0xFF78350F),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(Map<String, dynamic> data, String status) {
    final String? phone = data['clientPhone'] ?? data['phone'] ?? data['phone_number'];
    final String clientName = data['clientName'] ?? data['name'] ?? 'Клиент';
    final bool canCall = status != 'new' && status != 'cancelled';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: textMain.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _modernInfoRow(Icons.person_outline_rounded, 'КЛИЕНТ', clientName),
          const SizedBox(height: 18),
          _modernInfoRow(Icons.phone_outlined, 'КОНТАКТ', phone ?? 'Нет номера'),

          if (canCall && phone != null && phone.isNotEmpty) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () => _makePhoneCall(phone),
                icon: const Icon(Icons.call_rounded, size: 18),
                label: const Text(
                  'ПОЗВОНИТЬ КЛИЕНТУ',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryBlue,
                  side: const BorderSide(color: primaryBlue, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: textMain),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildAddressTimeline(Map<String, dynamic> data) {
    final pickup = data['pickup'] as Map<String, dynamic>?;
    final dropoff = data['dropoff'] as Map<String, dynamic>?;

    final String pickupText = pickup?['address']?.toString() ?? 'Адрес не указан';
    final String dropoffText = dropoff?['address']?.toString() ?? 'Адрес не указан';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: textMain.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _addressItem(Icons.circle, Colors.green, 'ТОЧКА ЗАБОРА', pickupText),
          Container(
            margin: const EdgeInsets.only(left: 11),
            height: 32,
            width: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.green, primaryBlue],
              ),
            ),
          ),
          _addressItem(Icons.location_on_rounded, primaryBlue, 'ТОЧКА ДОСТАВКИ', dropoffText),
        ],
      ),
    );
  }

  Widget _addressItem(IconData icon, Color color, String title, String sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: textMain,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sub,
                style: const TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildTimelineCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: textMain.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'СТАТУС ВЫПОЛНЕНИЯ',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 1,
              color: textMuted,
            ),
          ),
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

  Widget _buildBottomPanel(String status, Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 34),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: borderColor, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: textMain.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: _buildActionButton(status),
    );
  }

  Widget _buildActionButton(String status) {
    if (status == 'delivered') {
      return Container(
        height: 60,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: const Center(
          child: Text(
            '✅ ЗАКАЗ ДОСТАВЛЕН',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, letterSpacing: 0.8),
          ),
        ),
      );
    }

    String text = '';
    Color color = textMain;
    String nextStatus = '';

    if (status == 'new') {
      text = 'ПРИНЯТЬ ЗАКАЗ';
      color = primaryBlue;
      nextStatus = 'accepted';
    }
    else if (status == 'accepted') {
      text = 'НАЧАТЬ ПУТЬ';
      color = const Color(0xFFD97706);
      nextStatus = 'inProgress';
    }
    else if (status == 'inProgress') {
      text = 'ПОДТВЕРДИТЬ ДОСТАВКУ';
      color = Colors.green[700]!;
      nextStatus = 'delivered';
    }

    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: loading ? null : () => _takeAction(nextStatus),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
      ),
    );
  }
}

class DeliveryMapScreen extends StatefulWidget {
  final LatLng targetLocation;
  final String clientName;
  final LatLng? restaurantLocation;

  const DeliveryMapScreen({
    super.key,
    required this.targetLocation,
    required this.clientName,
    this.restaurantLocation,
  });

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
    } catch (e) {
      return false;
    }
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
    } catch (e) {
      debugPrint('OSRM Error: $e');
    }
  }

  void _fitMarkers() {
    List<LatLng> points = routePoints.isNotEmpty
        ? routePoints
        : [widget.targetLocation, if (widget.restaurantLocation != null) widget.restaurantLocation!];

    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(80),
        ),
      );
    } catch (e) {
      debugPrint('Ошибка центрирования камеры: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.clientName,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.targetLocation,
              initialZoom: 14,
            ),
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
                    Marker(
                      point: widget.restaurantLocation!,
                      child: const Icon(Icons.location_on_rounded, color: Color(0xFF2563EB), size: 35),
                    ),
                  Marker(
                    point: widget.targetLocation,
                    child: const Icon(Icons.flag_circle_rounded, color: Colors.redAccent, size: 40),
                  ),
                ],
              ),
            ],
          ),
          if (isLoadingRoute)
            Container(
              color: Colors.black.withOpacity(0.15),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF2563EB)),
              ),
            ),
        ],
      ),
    );
  }
}