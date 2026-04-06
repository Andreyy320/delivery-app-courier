import 'package:courier_app/screen/profile_screen.dart';
import 'package:flutter/material.dart';
import 'order_history_screen.dart';
import 'orders_screen.dart';

class CourierMainScreen extends StatefulWidget {
  final String courierId;      // уникальный ID курьера
  final String courierPhone;   // телефон курьера

  const CourierMainScreen({
    super.key,
    required this.courierId,
    required this.courierPhone,
  });

  @override
  State<CourierMainScreen> createState() => _CourierMainScreenState();
}

class _CourierMainScreenState extends State<CourierMainScreen> {
  int _currentIndex = 0;

  final List<GlobalKey<NavigatorState>> _navigatorKeys =
  List.generate(3, (_) => GlobalKey<NavigatorState>());

  Future<bool> _onWillPop() async {
    final isFirstRouteInCurrentTab =
    !await _navigatorKeys[_currentIndex].currentState!.maybePop();
    return isFirstRouteInCurrentTab;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
          _buildTabNavigator(
          0,
          CourierOrdersScreen(
            courierId: widget.courierId,
            courierPhone: widget.courierPhone,
          ),
        ),
          _buildTabNavigator(
            1,
            OrderHistoryScreen(
              courierId: widget.courierId,
            ),
          ),
        _buildTabNavigator(
          2,
          CourierProfileScreen(
            courierId: widget.courierId,
            courierPhone: widget.courierPhone,
          ),
        ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.deepOrange,
          unselectedItemColor: Colors.grey,
          onTap: (index) {
            if (index == _currentIndex) {
              _navigatorKeys[index]
                  .currentState
                  ?.popUntil((route) => route.isFirst);
            } else {
              setState(() => _currentIndex = index);
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.list_alt),
              label: 'Заказы',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: 'История',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabNavigator(int index, Widget child) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child),
    );
  }
}
