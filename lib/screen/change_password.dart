import 'package:courier_app/screen/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class ChangePasswordScreen extends StatefulWidget {
  final String courierId;
  final String courierPhone;
  final VoidCallback? onPasswordChanged; // ← коллбек после смены пароля

  const ChangePasswordScreen({
    super.key,
    required this.courierId,
    required this.courierPhone,
    this.onPasswordChanged,
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _repeatPasswordController = TextEditingController();

  bool isLoading = false;

  Future<void> _changePassword() async {
    setState(() => isLoading = true);

    final oldPassword = _oldPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final repeatPassword = _repeatPasswordController.text.trim();

    if (newPassword.length < 3) {
      _showMessage('Минимум 3 символа');
      setState(() => isLoading = false);
      return;
    }

    if (newPassword != repeatPassword) {
      _showMessage('Пароли не совпадают');
      setState(() => isLoading = false);
      return;
    }

    try {
      // Берем документ курьера из Firestore
      final docRef = FirebaseFirestore.instance
          .collection('couriers')
          .doc(widget.courierId);

      final doc = await docRef.get();

      if (!doc.exists) {
        _showMessage('Курьер не найден');
        setState(() => isLoading = false);
        return;
      }

      final data = doc.data()!;
      if (data['password'] != oldPassword) {
        _showMessage('Старый пароль неверный');
        setState(() => isLoading = false);
        return;
      }

      // Обновляем пароль
      await docRef.update({'password': newPassword});

      setState(() => isLoading = false);

      _showMessage('Пароль успешно изменён');

      // Навигация на экран профиля
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => CourierProfileScreen(
            courierId: widget.courierId,
            courierPhone: widget.courierPhone,
          ),
        ),
            (route) => false, // удаляем все предыдущие экраны
      );
    } catch (e) {
      _showMessage('Ошибка при смене пароля');
      setState(() => isLoading = false);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Изменить пароль'),
        backgroundColor: Colors.deepOrange,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _oldPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Старый пароль',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Новый пароль',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _repeatPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Повторите новый пароль',
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Сохранить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
