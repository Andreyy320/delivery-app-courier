// файл: courier_order_model.dart
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';

/// Модель блюда в заказе
class Dish {
  final String name;
  final double price;
  final String description;
  final String category;
  final String imagePath;

  Dish({
    required this.name,
    required this.price,
    this.description = '',
    this.category = '',
    required this.imagePath,
  });
}

/// Модель позиции в корзине (CartItem)
class CartItem {
  final Dish dish;
  final int quantity;

  CartItem({
    required this.dish,
    required this.quantity,
  });
}

/// Модель заказа для курьера
class CourierOrder {
  final String id; // id заказа
  final List<CartItem> items;
  final LatLng deliveryLocation;
  final String comment;
  final String paymentMethod;
  final double total;
  final DateTime dateTime;
  final String status; // готовится, в пути, доставлено
  final String customerName; // имя клиента

  CourierOrder({
    required this.id,
    required this.items,
    required this.deliveryLocation,
    required this.comment,
    required this.paymentMethod,
    required this.total,
    required this.dateTime,
    required this.status,
    required this.customerName,
  });

  /// Создание объекта из Map (например, Firestore)
  factory CourierOrder.fromMap(String id, Map<String, dynamic> data) {
    DateTime date = DateTime.now();
    if (data['createdAt'] != null) {
      try {
        date = DateTime.parse(data['createdAt']);
      } catch (_) {}
    }

    return CourierOrder(
      id: id,
      items: (data['items'] as List<dynamic>? ?? []).map((e) {
        final dishData = e as Map<String, dynamic>? ?? {};
        return CartItem(
          dish: Dish(
            name: dishData['name'] ?? 'Без имени',
            price: (dishData['price'] ?? 0).toDouble(),
            description: dishData['description'] ?? '',
            category: dishData['category'] ?? '',
            imagePath: dishData['imagePath'] ?? 'assets/default.png',
          ),
          quantity: dishData['quantity'] ?? 1,
        );
      }).toList(),
      deliveryLocation: LatLng(
        (data['deliveryLocation']?['lat'] ?? 0).toDouble(),
        (data['deliveryLocation']?['lng'] ?? 0).toDouble(),
      ),
      comment: data['comment'] ?? '',
      paymentMethod: data['paymentMethod'] ?? 'online',
      total: (data['total'] ?? 0).toDouble(),
      dateTime: date,
      status: data['status'] ?? 'готовится',
      customerName: data['customerName'] ?? 'Клиент',
    );
  }
}
