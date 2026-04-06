import 'package:flutter/material.dart';
import 'courier_order_model.dart'; // модель заказа

class CourierOrderCard extends StatelessWidget {
  final CourierOrder order;
  final VoidCallback onTap;

  const CourierOrderCard({super.key, required this.order, required this.onTap});

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'готовится':
        return Colors.orange;
      case 'в пути':
        return Colors.blue;
      case 'доставлено':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Верхняя строка: имя клиента и статус
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(order.customerName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: getStatusColor(order.status),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      order.status,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Адрес
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.deepOrange, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(
                          'Широта: ${order.deliveryLocation.latitude.toStringAsFixed(4)}, Долгота: ${order.deliveryLocation.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(fontSize: 14, color: Colors.grey))),
                ],
              ),
              const SizedBox(height: 8),
              // Список товаров (показываем первые 2 для компактности)
              ...order.items.take(2).map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        item.dish.imagePath,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item.dish.name} × ${item.quantity}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Text('${item.dish.price * item.quantity} ₽',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              )),
              if (order.items.length > 2)
                Text('+ ещё ${order.items.length - 2} товаров',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              // Итого
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Итого: ${order.total.toStringAsFixed(0)} ₽',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey)
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
