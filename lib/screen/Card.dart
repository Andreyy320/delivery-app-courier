import 'package:flutter/material.dart';
import 'courier_order_model.dart';

class CourierOrderCard extends StatelessWidget {
  final CourierOrder order;
  final VoidCallback onTap;

  const CourierOrderCard({super.key, required this.order, required this.onTap});

  // Улучшенные цвета для статусов
  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'готовится':
        return Colors.orange[700]!;
      case 'в пути':
        return Colors.blue[700]!;
      case 'доставлено':
        return Colors.green[700]!;
      case 'готов':
        return Colors.deepPurple[600]!;
      default:
        return Colors.grey[700]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. ВЕРХНЯЯ СТРОКА: КЛИЕНТ И СТАТУС
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        order.customerName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            letterSpacing: -0.5
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _buildStatusBadge(order.status),
                  ],
                ),
                const SizedBox(height: 12),

                // 2. АДРЕС (КООРДИНАТЫ) С АКЦЕНТОМ
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.red[700], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${order.deliveryLocation.latitude.toStringAsFixed(5)}, ${order.deliveryLocation.longitude.toStringAsFixed(5)}',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.blueGrey[800],
                              fontWeight: FontWeight.w500
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 3. СПИСОК ТОВАРОВ (Еда)
                const Text(
                  "СОСТАВ ЗАКАЗА",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                ...order.items.take(2).map((item) => _buildItemRow(item)),

                if (order.items.length > 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 48),
                    child: Text(
                      'и еще ${order.items.length - 2} поз.',
                      style: TextStyle(fontSize: 12, color: Colors.deepOrange[700], fontWeight: FontWeight.bold),
                    ),
                  ),

                const Divider(height: 24, thickness: 0.5),

                // 4. НИЖНЯЯ СТРОКА: ИТОГО
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('К оплате', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text(
                          '${order.total.toStringAsFixed(0)} ₽',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              color: Colors.black
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: const Row(
                        children: [
                          Text("Детали"),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward, size: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final color = getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5
        ),
      ),
    );
  }

  Widget _buildItemRow(dynamic item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Миниатюра блюда
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              item.dish.imagePath,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              // Заглушка, если картинка не найдена
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: Colors.grey[200], child: const Icon(Icons.fastfood, size: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.dish.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${item.quantity} шт.',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Text(
            '${item.dish.price * item.quantity} ₽',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }
}