import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool loading = false;
  bool isPasswordVisible = false;
  String? errorText;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // --- LUXURY EMERALD & GOLD PALETTE ---
  static const primaryGradient = LinearGradient(
    colors: [Color(0xFF047857), Color(0xFF10B981)], // Deep Emerald to Vibrant Mint
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const goldAccent = Color(0xFFD97706); // Warm Metallic Gold
  static const surfaceBackground = Color(0xFFFAFAF9); // Pure Warm Pearl
  static const cardBackground = Color(0xFFFFFFFF);
  static const textMain = Color(0xFF0F172A);
  static const textMuted = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    phoneController.text = '+373 ';

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
      debugPrint("FCM Token error: $e");
    }
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    final phone = phoneController.text.replaceAll(' ', '');
    final password = passwordController.text.trim();

    if (phone.length < 12 || password.isEmpty) {
      setState(() => errorText = 'Введите 8 цифр номера и пароль');
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
          errorText = 'Аккаунт не найден или деактивирован';
          loading = false;
        });
        return;
      }

      final courierDoc = query.docs.first;
      final courierData = courierDoc.data();

      await _updateFcmToken(courierDoc.id);

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
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: surfaceBackground,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            // --- ТЁПЛЫЕ ПРЕМИАЛЬНЫЕ СВЕЧЕНИЯ НА ФОНЕ ---
            Positioned(
              top: -size.width * 0.3,
              right: -size.width * 0.2,
              child: _buildGradientBlob(
                color: const Color(0xFF10B981).withOpacity(0.12),
                radius: size.width * 0.85,
              ),
            ),
            Positioned(
              bottom: -size.width * 0.35,
              left: -size.width * 0.2,
              child: _buildGradientBlob(
                color: goldAccent.withOpacity(0.08),
                radius: size.width * 0.9,
              ),
            ),

            // Эффект мягкого матового стекла
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

                          // --- КАРТОЧКА ФОРМЫ С ЗОЛОТИСТОЙ ОКОЙМКОЙ ---
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: cardBackground,
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: const Color(0xFFF1F5F9),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0F172A).withOpacity(0.04),
                                  blurRadius: 40,
                                  offset: const Offset(0, 20),
                                ),
                                BoxShadow(
                                  color: const Color(0xFF047857).withOpacity(0.03),
                                  blurRadius: 15,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel("ТЕЛЕФОН КУРЬЕРА"),
                                _buildField(
                                  controller: phoneController,
                                  icon: Icons.phone_iphone_rounded,
                                  hint: "77X XX XXX",
                                  isPhone: true,
                                  onChanged: (value) {
                                    if (!value.startsWith('+373 ')) {
                                      phoneController.text = '+373 ';
                                      phoneController.selection =
                                          TextSelection.fromPosition(
                                            TextPosition(
                                              offset: phoneController.text.length,
                                            ),
                                          );
                                    }
                                  },
                                ),
                                const SizedBox(height: 22),
                                _buildLabel("ПАРОЛЬ ДОСТУПА"),
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

                          const SizedBox(height: 36),
                          _buildFooterVersion(),
                          const SizedBox(height: 16),
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

  // --- РОСКОШНЫЙ ЛОГОТИП И ШРИФТЫ ---
  Widget _buildHeaderLogo() {
    return Column(
      children: [
        Container(
          height: 88,
          width: 88,
          decoration: BoxDecoration(
            gradient: primaryGradient,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF047857).withOpacity(0.35),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: const Icon(
            Icons.delivery_dining_rounded,
            size: 48,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              color: textMain,
            ),
            children: [
              TextSpan(text: 'COURIER'),
              TextSpan(
                text: ' PRO',
                style: TextStyle(color: Color(0xFF047857)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7), // Soft Gold Fill
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: goldAccent.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, size: 12, color: goldAccent),
                  SizedBox(width: 4),
                  Text(
                    'EXPRESS TERMINAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: goldAccent,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- МЕТКИ И ПОЛЯ ВВОДА ---
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: textMuted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool isPassword = false,
    bool isPhone = false,
    Function(String)? onChanged,
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
        onChanged: onChanged,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: textMain,
        ),
        keyboardType: isPhone ? TextInputType.number : TextInputType.text,
        inputFormatters: isPhone
            ? [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
          LengthLimitingTextInputFormatter(13),
        ]
            : [],
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: textMuted.withOpacity(0.5),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(icon, color: const Color(0xFF047857), size: 22),
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

  // --- БЛОК ОШИБКИ ---
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

  // --- ПРЕМИАЛЬНАЯ ИЗУМРУДНАЯ КНОПКА ---
  Widget _buildLoginButton() {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: primaryGradient,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF047857).withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: loading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
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
              'ВХОД В ТЕРМИНАЛ',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: Colors.white,
                letterSpacing: 1.2,
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

  // --- ПОДПИСЬ ВЕРСИИ С ИНДИКАТОРОМ ---
  Widget _buildFooterVersion() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "Система готова к работе",
                style: TextStyle(
                  fontSize: 11,
                  color: textMain,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Версия 1.0.4 • Secure Connection",
          style: TextStyle(
            fontSize: 10,
            color: textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
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