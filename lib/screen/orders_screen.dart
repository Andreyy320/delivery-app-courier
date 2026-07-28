import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'Glavna_Screen.dart';
import 'NO_USED_SCREEN/gorod_detail.dart';
import 'NO_USED_SCREEN/mejgorod_detail.dart';
import 'detail_screen/srok_detail.dart';
import 'detail_screen/order_detail.dart';
import 'order_status.dart';

class CourierOrdersScreen extends StatefulWidget {
  final String courierId;
  final String courierPhone;

  const CourierOrdersScreen({
    super.key,
    required this.courierId,
    required this.courierPhone,
  });

  @override
  State<CourierOrdersScreen> createState() => _CourierOrdersScreenState();
}

class _CourierOrdersScreenState extends State<CourierOrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Map<String, String> _userNamesCache = {};

  bool _isOnDuty = false;
  String _selectedCity = 'Тирасполь';
  String _selectedDistrict = 'БАЛКА';

  final List<String> _cities = [
    'Тирасполь',
    'Бендеры',
    'Рыбница',
    'Григориополь',
    'Дубоссары',
    'Слободзея',
    'Каменка',
  ];

  final Map<String, List<String>> _districtsByCity = {
    'Тирасполь': [
      'СОВХОЗ',
      'БОРОДИНКА',
      'ОРИОН',
      'ВЕРХНИЙ ЦЕНТР',
      'НИЖНИЙ ЦЕНТР',
      'АВТОСТАНЦИЯ',
      'ЛЕЧГОРОДОК',
      'БАЛКА',
      'КРАСНЫЕ',
      'КИРОВСКИЙ',
      'ТЕРНОВКА',
      'КИЦКАНЫ',
      'БЛИЖНИЙ',
      'СУКЛЕЯ',
    ],
    'Бендеры': [
      'ЦЕНТР',
      'ЛЕНИНСКИЙ',
      'ХОМУТЯНОВКА',
      'БОРИСОВКА',
      'ШЕЛКОВЫЙ',
      'ПРОТЯГАЙЛОВКА',
    ],
    'Рыбница': [
      'ЦЕНТР',
      'ВАЛЧИНЕЦ',
      'КОЛБАСНА',
      'МЕТАЛЛУРГОВ',
    ],
    'Григориополь': [
      'ЦЕНТР',
      'МОЛДАВАНКА',
    ],
    'Дубоссары': [
      'ЦЕНТР',
      'КОРЖЕВО',
      'ЛУНГА',
    ],
    'Слободзея': [
      'РУССКАЯ ЧАСТЬ',
      'МОЛДАВСКАЯ ЧАСТЬ',
    ],
    'Каменка': [
      'ЦЕНТР',
      'СОЛНЕЧНЫЙ',
    ],
  };

  // --- СВЕТЛЫЙ ФОН + ТОЛЬКО СИНИЕ И ГОЛУБЫЕ АКЦЕНТЫ (БЕЗ ЗЕЛЕНОГО) ---
  static const Color appBg = Color(0xFFF1F5F9);         // Светлый, чистый фон экрана
  static const Color cardBg = Color(0xFFFFFFFF);         // Белые карточки
  static const Color innerBg = Color(0xFFF8FAFC);        // Чуть сероватый для раскрывающегося блока
  static const Color primaryBlue = Color(0xFF2563EB);    // Глубокий фирменный синий
  static const Color accentCyan = Color(0xFF0EA5E9);     // Яркий голубой акцент
  static const Color textDark = Color(0xFF0F172A);       // Черный текст для идеальной видимости
  static const Color textMuted = Color(0xFF64748B);      // Серый текст для подписей
  static const Color borderColor = Color(0xFFE2E8F0);    // Аккуратные границы

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 2); // По умолчанию открываем вкладку "КОМАНДЫ"
    _loadCourierStatus();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCourierStatus() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('couriers').doc(widget.courierId).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          setState(() {
            _isOnDuty = data['isOnDuty'] ?? false;
            _selectedCity = data['selectedCity'] ?? 'Тирасполь';
            _selectedDistrict = data['currentDistrict'] ?? 'БАЛКА';
          });
        }
      }
    } catch (e) {
      // Игнорируем
    }
  }

  Future<void> _updateCourierStatus(bool isOnDuty, String city, String district) async {
    setState(() {
      _isOnDuty = isOnDuty;
      _selectedCity = city;
      _selectedDistrict = district;
    });

    try {
      await FirebaseFirestore.instance.collection('couriers').doc(widget.courierId).set({
        'isOnDuty': isOnDuty,
        'selectedCity': city,
        'currentDistrict': district,
        'phone': widget.courierPhone,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Ошибка: $e');
    }
  }

  Future<String> _getClientName(Map<String, dynamic> orderData, String userId) async {
    if (orderData['clientName'] != null && orderData['clientName'].toString().isNotEmpty) {
      return orderData['clientName'];
    }
    if (userId.isEmpty) return 'Без имени';
    if (_userNamesCache.containsKey(userId)) return _userNamesCache[userId]!;

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final name = userDoc.data()?['name'] ?? 'Без имени';
      _userNamesCache[userId] = name;
      return name;
    } catch (e) {
      return 'Без имени';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        title: TabBar(
          controller: _tabController,
          labelColor: primaryBlue,
          unselectedLabelColor: textMuted,
          indicatorColor: primaryBlue,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5),
          tabs: const [
            Tab(text: 'ГЛАВНАЯ'),
            Tab(text: 'ЗАКАЗЫ'),
            Tab(text: 'КОМАНДЫ'),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: borderColor, height: 1),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. Вкладка "ГЛАВНАЯ"
          _buildMainTab(),

          // 2. Вкладка "ЗАКАЗЫ"
          _buildOrdersTab(),

          // 3. Вкладка "КОМАНДЫ" (Точная структура твоего экрана)
          _buildTeamsTab(),
        ],
      ),
    );
  }

  // --- ЭКРАН 1: ГЛАВНАЯ ---
  Widget _buildMainTab() {
    return MainDashboardScreen(
      courierId: widget.courierId, // передаем ID документа курьера из Firestore
      onOpenMap: () {
        // Логика открытия карты (например, переключение таба или вызов экрана карты)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Открытие карты...')),
        );
      },
    );
  }

// --- ЭКРАН 2: ЗАКАЗЫ ---
  Widget _buildOrdersTab() {
    return OrdersStatusScreen(
      courierId: widget.courierId,
      courierPhone: widget.courierPhone,
    );
  }

  // --- ЭКРАН 3: КОМАНДЫ (Твоя оригинальная структура) ---
  Widget _buildTeamsTab() {
    final districts = _districtsByCity[_selectedCity] ?? [];

    return Column(
      children: [
        // --- ВЕРХНЯЯ ПАНЕЛЬ СТАТУСА ---
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          color: cardBg,
          child: Text(
            _isOnDuty ? 'РАЙОН: $_selectedDistrict' : 'СТАТУС: СВОБОДЕН',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: primaryBlue,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(color: borderColor, height: 1),

        // --- ВЕРХНЯЯ ПАНЕЛЬ УПРАВЛЕНИЯ ---
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Кнопка выбора города (Сине-голубой стиль)
              Expanded(
                flex: 12,
                child: InkWell(
                  onTap: _showCitySelector,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: innerBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accentCyan.withOpacity(0.5), width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_city_rounded, color: primaryBlue, size: 18),
                            const SizedBox(width: 10),
                            Text(
                              _selectedCity.toUpperCase(),
                              style: const TextStyle(color: textDark, fontWeight: FontWeight.w900, fontSize: 13),
                            ),
                          ],
                        ),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Кнопка Статуса (Синяя)
              Expanded(
                flex: 11,
                child: InkWell(
                  onTap: () {
                    _updateCourierStatus(!_isOnDuty, _selectedCity, _selectedDistrict);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      color: primaryBlue,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: primaryBlue.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _isOnDuty ? 'НА СМЕНЕ' : 'СВОБОДЕН',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // --- СПИСОК РАЙОНОВ ---
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: districts.length,
            itemBuilder: (context, index) {
              final district = districts[index];
              final isCurrentDistrict = _selectedDistrict == district && _isOnDuty;

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('couriers')
                    .where('selectedCity', isEqualTo: _selectedCity)
                    .where('currentDistrict', isEqualTo: district)
                    .where('isOnDuty', isEqualTo: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  int couriersCount = 0;
                  if (snapshot.hasData) {
                    couriersCount = snapshot.data!.docs.length;
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrentDistrict ? primaryBlue : borderColor,
                        width: isCurrentDistrict ? 2.0 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ExpansionTile(
                      collapsedIconColor: textMuted,
                      iconColor: primaryBlue,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              district,
                              style: const TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (isCurrentDistrict)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: primaryBlue,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'ВАШ РАЙОН',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                              ),
                            ),
                        ],
                      ),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: innerBg,
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                            border: Border(top: BorderSide(color: borderColor, width: 1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.people_alt_outlined, color: textMuted, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Курьеров на смене: $couriersCount',
                                    style: const TextStyle(color: textMuted, fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () {
                                        _updateCourierStatus(true, _selectedCity, district);
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryBlue,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                      child: const Text('ВЫБРАТЬ РАЙОН', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        _updateCourierStatus(false, _selectedCity, district);
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFDC2626),
                                        side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                      child: const Text('УЙТИ С РАЙОНА', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCitySelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ВЫБЕРИТЕ ГОРОД',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: textDark),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _cities.length,
                  itemBuilder: (context, index) {
                    final city = _cities[index];
                    final isSelected = city == _selectedCity;

                    return ListTile(
                      title: Text(
                        city.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: isSelected ? primaryBlue : textDark,
                        ),
                      ),
                      trailing: isSelected ? const Icon(Icons.check_rounded, color: primaryBlue) : null,
                      onTap: () {
                        setState(() {
                          _selectedCity = city;
                          final districts = _districtsByCity[city] ?? [];
                          if (districts.isNotEmpty) _selectedDistrict = districts.first;
                        });
                        _updateCourierStatus(_isOnDuty, _selectedCity, _selectedDistrict);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}