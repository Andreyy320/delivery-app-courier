import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool loading = false;
  String? errorText;

  Future<void> _login() async {
    final phone = phoneController.text.trim();
    final password = passwordController.text.trim();

    if (phone.isEmpty || password.isEmpty) {
      setState(() => errorText = 'Введите телефон и пароль');
      return;
    }

    setState(() {
      loading = true;
      errorText = null;
    });

    try {
      final query = await FirebaseFirestore.instance
          .collection('couriers')
          .where('phone', isEqualTo: phone)
          .where('password', isEqualTo: password)
          .where('active', isEqualTo: true)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        setState(() {
          errorText = 'Неверный телефон, пароль или курьер не активен';
          loading = false;
        });
        return;
      }

      final courierData = query.docs.first.data();

      // ✅ Успешный вход — переходим на главный экран с нижней панелью
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => CourierMainScreen(
            courierId: query.docs.first.id,
            courierPhone: courierData['phone'] ?? '',
          ),
        ),
            (route) => false, // ← удаляем все предыдущие экраны
      );
    } catch (e) {
      setState(() {
        errorText = 'Ошибка входа: $e';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вход для курьера'),
        backgroundColor: Colors.deepOrange,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Телефон',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Пароль',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (errorText != null)
              Text(errorText!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Войти'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
