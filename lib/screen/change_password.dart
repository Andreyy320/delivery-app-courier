import 'package:courier_app/screen/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChangePasswordScreen extends StatefulWidget {
  final String courierId;
  final String courierPhone;
  final VoidCallback? onPasswordChanged;

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
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureRepeat = true;

  Future<void> _changePassword() async {
    // Валидация
    final oldPassword = _oldPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final repeatPassword = _repeatPasswordController.text.trim();

    if (oldPassword.isEmpty || newPassword.isEmpty) {
      _showMessage('Заполните все поля', isError: true);
      return;
    }

    if (newPassword.length < 3) {
      _showMessage('Минимум 3 символа', isError: true);
      return;
    }

    if (newPassword != repeatPassword) {
      _showMessage('Пароли не совпадают', isError: true);
      return;
    }

    setState(() => isLoading = true);

    try {
      final docRef = FirebaseFirestore.instance.collection('couriers').doc(widget.courierId);
      final doc = await docRef.get();

      if (!doc.exists) {
        _showMessage('Курьер не найден', isError: true);
        return;
      }

      final data = doc.data()!;
      if (data['password'] != oldPassword) {
        _showMessage('Старый пароль неверный', isError: true);
        return;
      }

      await docRef.update({'password': newPassword});
      _showMessage('Пароль успешно изменён', isError: false);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => CourierProfileScreen(
              courierId: widget.courierId,
              courierPhone: widget.courierPhone,
            ),
          ),
              (route) => false,
        );
      }
    } catch (e) {
      _showMessage('Ошибка при смене пароля', isError: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red[800] : Colors.green[800],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Безопасность', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Обновление пароля',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Придумайте сложный пароль, чтобы защитить свой профиль курьера.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),

            _buildPasswordField(
              controller: _oldPasswordController,
              label: 'Старый пароль',
              isObscure: _obscureOld,
              onToggle: () => setState(() => _obscureOld = !_obscureOld),
            ),
            const SizedBox(height: 16),
            _buildPasswordField(
              controller: _newPasswordController,
              label: 'Новый пароль',
              isObscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
            ),
            const SizedBox(height: 16),
            _buildPasswordField(
              controller: _repeatPasswordController,
              label: 'Повторите новый пароль',
              isObscure: _obscureRepeat,
              onToggle: () => setState(() => _obscureRepeat = !_obscureRepeat),
            ),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: isLoading ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('СОХРАНИТЬ ИЗМЕНЕНИЯ', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool isObscure,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isObscure,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              icon: Icon(isObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
              onPressed: onToggle,
              color: Colors.grey,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }
}