import 'package:cloud_firestore/cloud_firestore.dart';

class Order {
  final String id;
  final String clientName;
  final String clientPhone;
  final String status;
  final double total;
  final List<Map<String, dynamic>> items;
  final String type; // normal, city, mejCity, express
  final Timestamp? createdAt;
  final Map<String, dynamic>? deliveryLocation;
  final String fromAddress;
  final String toAddress;
  final String comment;

  Order({
    required this.id,
    required this.clientName,
    required this.clientPhone,
    required this.status,
    this.total = 0,
    this.items = const [],
    this.type = 'normal',
    this.createdAt,
    this.deliveryLocation,
    this.fromAddress = '',
    this.toAddress = '',
    this.comment = '',
  });

  factory Order.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    String clientName = data['clientName'] ?? '';
    String clientPhone = data['clientPhone'] ?? '';

    // Если межгород и нет имени, берём из users
    if ((clientName.isEmpty || clientPhone.isEmpty) && data['userId'] != null) {
      // тут можно добавить логику запроса к users
    }

    return Order(
      id: doc.id,
      clientName: clientName.isEmpty ? 'Не указан' : clientName,
      clientPhone: clientPhone.isEmpty ? '-' : clientPhone,
      status: data['status'] ?? 'new',
      total: (data['total'] ?? data['totalPrice'] ?? 0).toDouble(),
      items: (data['items'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ?? [],
      type: data['type'] ?? 'normal',
      createdAt: data['createdAt'] as Timestamp?,
      deliveryLocation: data['deliveryLocation'] as Map<String, dynamic>?,
      fromAddress: data['fromAddress'] ?? '',
      toAddress: data['toAddress'] ?? '',
      comment: data['comment'] ?? '',
    );
  }
}
