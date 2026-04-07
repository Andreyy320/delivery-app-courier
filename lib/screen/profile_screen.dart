import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'change_password.dart';
import 'login_screen.dart';
import 'order_history_screen.dart';
import 'order_status.dart';

class CourierProfileScreen extends StatefulWidget {
  final String courierId;
  final String courierPhone;

  const CourierProfileScreen({
    super.key,
    required this.courierId,
    required this.courierPhone,
  });

  @override
  State<CourierProfileScreen> createState() => _CourierProfileScreenState();
}

class _CourierProfileScreenState extends State<CourierProfileScreen> {
  Map<String, dynamic>? courierData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCourier();
  }

  Future<void> _loadCourier() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('couriers')
          .doc(widget.courierId)
          .get();

      if (mounted) {
        setState(() {
          courierData = doc.data();
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.deepOrange)),
      );
    }

    final name = courierData?['name'] ?? 'Курьер';
    final phone = courierData?['phone'] ?? widget.courierPhone;

    return Scaffold(
      backgroundColor: Colors.grey[50], // Чистый светлый фон
      body: CustomScrollView( // Используем CustomScrollView для лучшей адаптивности
        slivers: [
          // Красивая шапка с градиентом
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.deepOrange, Color(0xFFFF8E53)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(30.0),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 45,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        child: const Icon(Icons.person, size: 50, color: Colors.white),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          phone,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Основной контент
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const Text(
                  "МЕНЮ",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 15),

                // Основная карточка меню
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildMenuTile(
                        icon: Icons.history_rounded,
                        title: 'История заказов',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderHistoryScreen(courierId: widget.courierId),
                          ),
                        ),
                      ),
                      _buildDivider(),
                      _buildMenuTile(
                        icon: Icons.local_shipping_rounded,
                        title: 'Мои текущие заказы',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrdersStatusScreen(
                              courierId: widget.courierId,
                              courierPhone: widget.courierPhone,
                            ),
                          ),
                        ),
                      ),
                      _buildDivider(),
                      _buildMenuTile(
                        icon: Icons.lock_reset_rounded,
                        title: 'Изменить пароль',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChangePasswordScreen(
                              courierId: widget.courierId,
                              courierPhone: widget.courierPhone,
                              onPasswordChanged: () => Navigator.pop(context),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Кнопка выхода (делаем её стильной, а не просто красной)
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (route) => false,
                      );
                    },
                    icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                    label: const Text(
                      'Выйти из аккаунта',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(color: Colors.redAccent.withOpacity(0.2)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 50),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // Вспомогательный виджет для пунктов меню
  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.deepOrange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.deepOrange, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      indent: 60,
      endIndent: 20,
      color: Colors.grey.withOpacity(0.1),
    );
  }
}