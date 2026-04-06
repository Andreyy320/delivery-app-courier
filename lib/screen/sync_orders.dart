import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> syncOrders() async {
  final usersCollection = FirebaseFirestore.instance.collection('users');
  final ordersCollection = FirebaseFirestore.instance.collection('orders');

  final usersSnapshot = await usersCollection.get();

  for (final userDoc in usersSnapshot.docs) {
    final uid = userDoc.id;

    final userOrders = await usersCollection.doc(uid).collection('orders').get();

    for (final orderDoc in userOrders.docs) {
      final orderData = orderDoc.data();

      // Проверяем, чтобы не дублировать
      final existing = await ordersCollection.doc(orderDoc.id).get();
      if (existing.exists) continue;

      await ordersCollection.doc(orderDoc.id).set({
        ...orderData,           // копируем все поля
        'userId': uid,          // добавляем поле userId
        'courierId': null,      // пока никто не взял заказ
      });

      print('Синхронизирован заказ ${orderDoc.id} пользователя $uid');
    }
  }

  print('Все заказы синхронизированы!');
}
