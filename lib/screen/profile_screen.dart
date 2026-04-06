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
    setState(() => isLoading = true);

    final doc = await FirebaseFirestore.instance
        .collection('couriers')
        .doc(widget.courierId)
        .get();

    setState(() {
      courierData = doc.data();
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final name = courierData?['name'] ?? 'Курьер';
    final phone = courierData?['phone'] ?? widget.courierPhone;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // 🌟 Верхняя карточка профиля
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.deepOrange, Colors.orangeAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Привет, $name',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Телефон: $phone',
                        style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 🔹 Ссылки профиля
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.history, color: Colors.deepOrange),
                      title: const Text('История заказов'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderHistoryScreen(courierId: widget.courierId),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.list_alt, color: Colors.deepOrange),
                      title: const Text('Мои текущие заказы'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrdersStatusScreen(
                              courierId: widget.courierId,
                              courierPhone: widget.courierPhone,
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.lock, color: Colors.deepOrange),
            title: const Text('Изменить пароль'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChangePasswordScreen(
                    courierId: widget.courierId,         // ← передаем ID
                    courierPhone: widget.courierPhone,   // ← передаем телефон
                    onPasswordChanged: () {
                      // После успешной смены пароля возвращаемся в профиль
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CourierProfileScreen(
                            courierId: widget.courierId,
                            courierPhone: widget.courierPhone,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // 🔴 Кнопка выхода
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (route) => false,
                      );

                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Выйти', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
