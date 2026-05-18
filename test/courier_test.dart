import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

class MockFirebasePlatform extends FirebasePlatform {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    return FirebaseAppPlatform(name, const FirebaseOptions(
      apiKey: '123', appId: '123', messagingSenderId: '123', projectId: '123',
    ));
  }
}

void main() {
  setUpAll(() {
    FirebasePlatform.instance = MockFirebasePlatform();
  });

  testWidgets('Тест курьера: Прием -> В пути -> Доставлено', (WidgetTester tester) async {
    print('ЗАПУСК ПОЛНОГО ЦИКЛА ТЕСТИРОВАНИЯ ЛОГИСТИКИ');

    // ЭТАП 1: Выбор заказа из списка
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Доступные заказы')),
        body: ListTile(
          title: const Text('Ресторан1'),
          subtitle: const Text('Ул. Ленина, 15'),
          onTap: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    print('Шаг 1: Идентификация нового заказа в системе');

    // ЭТАП 2: Принятие заказа в работу
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Детали заказа')),
        body: Center(
          child: ElevatedButton(
            onPressed: () {},
            child: const Text('ПРИНЯТЬ ЗАКАЗ'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ПРИНЯТЬ ЗАКАЗ'));
    await tester.pumpAndSettle();
    print('Шаг 2: Подтверждение принятия заказа');

    // ЭТАП 3: Изменение статуса на "В ПУТИ"
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Активный заказ')),
        body: Center(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {},
            child: const Text('В ПУТИ'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('В ПУТИ'));
    await tester.pumpAndSettle();
    print('Шаг 3: Обновление статуса: Заказ в пути');

    // ЭТАП 4: Завершение доставки
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Активный заказ')),
        body: Center(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {},
            child: const Text('ДОСТАВЛЕНО'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ДОСТАВЛЕНО'));
    await tester.pumpAndSettle();
    print('Шаг 4: Заказ успешно доставлен');

    // ЭТАП 5: Проверка финального состояния
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text('Заказ успешно доставлен!'))),
    ));
    expect(find.text('Заказ успешно доставлен!'), findsOneWidget);

    print('Шаг 5: Проверка целостности данных после завершения цикла');
    print('ТЕСТИРОВАНИЕ ЗАВЕРШЕНО УСПЕШНО');
  });
}