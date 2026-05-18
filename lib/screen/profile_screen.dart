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
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    }

    final name = courierData?['name'] ?? 'Курьер';
    final phone = courierData?['phone'] ?? widget.courierPhone;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            backgroundColor: Colors.white,
            elevation: 0,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: Colors.white,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black12, width: 1),
                      ),
                      child: const CircleAvatar(
                        radius: 40,
                        backgroundColor: Color(0xFFF0F2F5),
                        child: Icon(Icons.person_outline_rounded, size: 45, color: Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(phone, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildSectionHeader("ВАША СТАТИСТИКА ЗА СЕГОДНЯ"),
                const SizedBox(height: 12),
                _buildStatsBlock(),

                const SizedBox(height: 32),

                _buildSectionHeader("ИНСТРУМЕНТЫ"),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 30,
                        offset: const Offset(0, 15),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildMenuRow(
                        icon: Icons.history_rounded,
                        title: 'История заказов',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => OrderHistoryScreen(courierId: widget.courierId)),
                        ),
                      ),
                      _buildMenuDivider(),
                      _buildMenuRow(
                        icon: Icons.local_shipping_outlined,
                        title: 'Текущие задачи',
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
                      _buildMenuDivider(),
                      _buildMenuRow(
                        icon: Icons.lock_outline_rounded,
                        title: 'Безопасность',
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

                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                    side: const BorderSide(color: Color(0xFFEEEEEE)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    foregroundColor: Colors.redAccent,
                  ),
                  child: const Text('ВЫЙТИ ИЗ АККАУНТА', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
                ),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    "Версия 1.0.4 • ПМР",
                    style: TextStyle(color: Colors.black12, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBlock() {
    DateTime now = DateTime.now();
    DateTime startOfToday = DateTime(now.year, now.month, now.day);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('couriers')
          .doc(widget.courierId)
          .collection('history')
          .where('status', isEqualTo: 'delivered')
          .snapshots(),
      builder: (context, snapshot) {
        int todayOrdersCount = 0;
        double todayEarnings = 0;

        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            Timestamp? ts = data['updatedAt'] ?? data['statusUpdatedAt'];

            if (ts != null) {
              DateTime date = ts.toDate();
              // Проверяем, был ли заказ выполнен сегодня
              if (date.isAfter(startOfToday)) {
                todayOrdersCount++;
                final price = data['deliveryPrice'] ?? data['totalPrice'] ?? 0;
                todayEarnings += (price is num) ? price.toDouble() : 0;
              }
            }
          }
        }

        return Row(
          children: [
            Expanded(child: _statCard("ЗАКАЗОВ СЕГОДНЯ", todayOrdersCount.toString(), const Color(0xFF3B82F6))),
            const SizedBox(width: 12),
            Expanded(child: _statCard("СУММА (РУБ)", todayEarnings.toStringAsFixed(0), const Color(0xFF10B981))),
          ],
        );
      },
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.1), width: 1),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black26, letterSpacing: 2)),
    );
  }

  Widget _buildMenuRow({required IconData icon, required String title, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Colors.black87),
            const SizedBox(width: 16),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black12),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuDivider() {
    return Divider(height: 1, indent: 64, endIndent: 24, color: Colors.black.withOpacity(0.04));
  }
}


