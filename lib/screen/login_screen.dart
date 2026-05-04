import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'home_screen.dart';
import 'notification_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool loading = false;
  String? errorText;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // --- СИСТЕМА УВЕДОМЛЕНИЙ ---
  final Set<String> _notifiedActions = {}; // Храним "ID_статус"
  late DateTime _startTime;

  @override
  void initState() {
    super.initState();
    phoneController.text = '+373 ';
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeOut);
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    super.dispose();
  }


  // --- ЛОГИКА ВХОДА ---
  Future<void> _updateFcmToken(String courierId) async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('couriers')
            .doc(courierId)
            .update({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print("FCM Token error: $e");
    }
  }

  Future<void> _login() async {
    final phone = phoneController.text.replaceAll(' ', '');
    final password = passwordController.text.trim();

    if (phone.length < 12 || password.isEmpty) {
      setState(() => errorText = 'Введите 8 цифр номера и пароль');
      return;
    }

    setState(() => loading = true);

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
          errorText = 'Аккаунт не найден или деактивирован';
          loading = false;
        });
        return;
      }

      final courierDoc = query.docs.first;
      final courierData = courierDoc.data();

      await _updateFcmToken(courierDoc.id);

      // Запускаем прослушку перед переходом
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => CourierMainScreen(
            courierId: courierDoc.id,
            courierPhone: courierData['phone'] ?? '',
          ),
        ),
            (route) => false,
      );
    } catch (e) {
      setState(() {
        errorText = 'Сбой подключения к серверу';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned(
            top: -50,
            left: -50,
            child: CircleAvatar(radius: 100, backgroundColor: const Color(0xFFF8F9FB)),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      _buildLogo(),
                      const SizedBox(height: 50),
                      _buildLabel("ТЕЛЕФОН КУРЬЕРА"),
                      _buildField(
                        controller: phoneController,
                        icon: Icons.phone_android_rounded,
                        hint: "77X XX XXX",
                        isPhone: true,
                        onChanged: (value) {
                          if (!value.startsWith('+373 ')) {
                            phoneController.text = '+373 ';
                            phoneController.selection = TextSelection.fromPosition(
                              TextPosition(offset: phoneController.text.length),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 24),
                      _buildLabel("ПАРОЛЬ ДОСТУПА"),
                      _buildField(
                        controller: passwordController,
                        icon: Icons.lock_open_rounded,
                        hint: "••••••••",
                        isPassword: true,
                      ),
                      if (errorText != null) _buildError(),
                      const SizedBox(height: 40),
                      _buildLoginButton(),
                      const SizedBox(height: 32),
                      const Text("Версия терминала 1.0.4", style: TextStyle(fontSize: 9, color: Colors.black12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- ВСПОМОГАТЕЛЬНЫЕ ВИДЖЕТЫ ---
  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          height: 90, width: 90,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(28)),
          child: const Icon(Icons.delivery_dining_rounded, size: 55, color: Colors.white),
        ),
        const SizedBox(height: 32),
        const Text('COURIER', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.black)),
        const Text('MANAGEMENT SYSTEM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black26, letterSpacing: 1.5)),
      ],
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Text(errorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity, height: 65,
      child: ElevatedButton(
        onPressed: loading ? null : _login,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
        child: loading ? const CircularProgressIndicator(color: Colors.white) : const Text('ВОЙТИ В СИСТЕМУ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(left: 8, bottom: 8), child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black26))));
  }

  Widget _buildField({required TextEditingController controller, required IconData icon, required String hint, bool isPassword = false, bool isPhone = false, Function(String)? onChanged}) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(20)),
      child: TextField(
        controller: controller, obscureText: isPassword, onChanged: onChanged,
        keyboardType: isPhone ? TextInputType.number : TextInputType.text,
        inputFormatters: isPhone ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(13)] : [],
        decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, color: Colors.black45, size: 20), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 22)),
      ),
    );
  }
}
