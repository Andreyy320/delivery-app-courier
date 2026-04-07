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

  @override
  void initState() {
    super.initState();
    // Устанавливаем префикс сразу при загрузке
    phoneController.text = '+373 ';
  }

  Future<void> _login() async {
    // 1. Очищаем номер от пробелов для поиска в базе (будет +37377xxxxxx)
    final phone = phoneController.text.replaceAll(' ', '');
    final password = passwordController.text.trim();

    // Проверка на пустые поля (префикс +373 занимает 4 символа)
    if (phone.length <= 4 || password.isEmpty) {
      setState(() => errorText = 'Введите полный номер и пароль');
      return;
    }

    setState(() {
      loading = true;
      errorText = null;
    });

    try {
      // 2. Ищем курьера в коллекции 'couriers'
      final query = await FirebaseFirestore.instance
          .collection('couriers')
          .where('phone', isEqualTo: phone)
          .where('password', isEqualTo: password)
          .where('active', isEqualTo: true)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        setState(() {
          errorText = 'Курьер не найден или не активен.';
          loading = false;
        });
        return;
      }

      final courierData = query.docs.first.data();

      if (!mounted) return;

      // 3. Переход в главное приложение
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => CourierMainScreen(
            courierId: query.docs.first.id,
            courierPhone: courierData['phone'] ?? '',
          ),
        ),
            (route) => false,
      );
    } catch (e) {
      setState(() {
        errorText = 'Ошибка подключения: $e';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Иконка курьера
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delivery_dining_rounded,
                    color: Colors.deepOrange,
                    size: 80,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Вход для курьера',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Доставка заказов',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 40),

                // Карточка с формой
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildTextField(
                        controller: phoneController,
                        label: 'Номер телефона',
                        icon: Icons.phone_android_rounded,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        controller: passwordController,
                        label: 'Пароль',
                        icon: Icons.lock_outline_rounded,
                        isPassword: true,
                      ),
                    ],
                  ),
                ),

                if (errorText != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 40),

                // Кнопка входа
                Container(
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepOrange.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                      'ВОЙТИ В СИСТЕМУ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      onChanged: (value) {
        // Не даем удалить +373
        if (!isPassword && !value.startsWith('+373 ')) {
          controller.text = '+373 ';
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: controller.text.length),
          );
        }
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.deepOrange),
        hintText: isPassword ? null : '77X XX XXX',
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.deepOrange, width: 1.5),
        ),
      ),
    );
  }
}