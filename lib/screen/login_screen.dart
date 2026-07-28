import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {

  final TextEditingController callsignController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool loading = false;
  bool isPasswordVisible = false;
  String? errorText;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // --- СВЕТЛАЯ И ДОРОГАЯ ПРЕМИАЛЬНАЯ ПАЛИТРА ---
  static const primaryGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)], // Благородный глубокий синий
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const surfaceBackground = Color(0xFFF8FAFC); // Чистый светлый фон
  static const cardBackground = Color(0xFFFFFFFF);
  static const textMain = Color(0xFF0F172A);
  static const textMuted = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    // Больше не нужен префикс телефона по умолчанию

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    callsignController.dispose();
    passwordController.dispose();
    super.dispose();
  }

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
      debugPrint("FCM Token error: $e");
    }
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    // Получаем позывной, приводим к строке и убираем лишние пробелы
    final callsign = callsignController.text.trim();
    final password = passwordController.text.trim();

    if (callsign.isEmpty || password.isEmpty) {
      setState(() => errorText = 'Введите позывной и пароль');
      return;
    }

    setState(() {
      loading = true;
      errorText = null;
    });

    try {
      // Поиск в Firestore по полю 'callsign' вместо 'phone'
      final query = await FirebaseFirestore.instance
          .collection('couriers')
          .where('callsign', isEqualTo: callsign)
          .where('password', isEqualTo: password)
          .where('active', isEqualTo: true)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        setState(() {
          errorText = 'Курьер с таким позывным не найден или деактивирован';
          loading = false;
        });
        return;
      }

      final courierDoc = query.docs.first;
      final courierData = courierDoc.data();

      // 🔹 Сохраняем ID курьера локально, чтобы при перезапуске сессия не сбрасывалась
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_courier_id', courierDoc.id);

      await _updateFcmToken(courierDoc.id);

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => CourierMainScreen(
            courierId: courierDoc.id,
            // Передаем позывной вместо телефона, либо оставляем пустую строку/телефон если требуется в HomeScreen
            courierPhone: courierData['callsign'] ?? '',
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
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: surfaceBackground,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            Positioned(
              top: -size.width * 0.3,
              right: -size.width * 0.2,
              child: _buildGradientBlob(
                color: const Color(0xFF3B82F6).withOpacity(0.08),
                radius: size.width * 0.85,
              ),
            ),
            Positioned(
              bottom: -size.width * 0.35,
              left: -size.width * 0.2,
              child: _buildGradientBlob(
                color: const Color(0xFF6366F1).withOpacity(0.06),
                radius: size.width * 0.9,
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                child: const SizedBox.expand(),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),
                          _buildHeaderLogo(),
                          const SizedBox(height: 36),
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: cardBackground,
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0F172A).withOpacity(0.05),
                                  blurRadius: 30,
                                  offset: const Offset(0, 15),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel("ПОЗЫВНОЙ"),
                                _buildField(
                                  controller: callsignController,
                                  icon: Icons.badge_rounded,
                                  hint: "Введите позывной",
                                ),
                                const SizedBox(height: 22),
                                _buildLabel("ПАРОЛЬ"),
                                _buildField(
                                  controller: passwordController,
                                  icon: Icons.lock_outline_rounded,
                                  hint: "••••••••",
                                  isPassword: true,
                                ),
                                if (errorText != null) _buildError(),
                                const SizedBox(height: 30),
                                _buildLoginButton(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderLogo() {
    return Column(
      children: [
        Container(
          height: 80,
          width: 80,
          decoration: BoxDecoration(
            gradient: primaryGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.delivery_dining_rounded,
            size: 40,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Вход для курьеров',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: textMain,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Введите данные для доступа к заказам',
          style: TextStyle(
            fontSize: 13,
            color: textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: textMuted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !isPasswordVisible,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: textMain,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: textMuted.withOpacity(0.4),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(icon, color: const Color(0xFF2563EB), size: 22),
          suffixIcon: isPassword
              ? IconButton(
            icon: Icon(
              isPasswordVisible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: textMuted,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                isPasswordVisible = !isPasswordVisible;
              });
            },
          )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 18,
            horizontal: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorText!,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: primaryGradient,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: loading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: loading
            ? const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        )
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Войти',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientBlob({required Color color, required double radius}) {
    return Container(
      width: radius,
      height: radius,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}