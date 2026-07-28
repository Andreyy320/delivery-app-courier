import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MainDashboardScreen extends StatefulWidget {
  final String courierId;
  final VoidCallback onOpenMap;

  const MainDashboardScreen({
    super.key,
    required this.courierId,
    required this.onOpenMap,
  });

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  static const Color appBg = Color(0xFFF1F5F9);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color innerBg = Color(0xFFF8FAFC);
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderColor = Color(0xFFE2E8F0);

  Future<void> _toggleDutyStatus(bool newDutyState) async {
    try {
      await FirebaseFirestore.instance.collection('couriers').doc(widget.courierId).update({
        'isOnDuty': newDutyState,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Ошибка обновления смены: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.courierId.isEmpty) {
      return const Scaffold(
        backgroundColor: appBg,
        body: Center(child: Text('Ошибка: ID курьера не передан', style: TextStyle(color: textDark, fontWeight: FontWeight.bold))),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('couriers').doc(widget.courierId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: appBg,
            body: Center(child: CircularProgressIndicator(color: primaryBlue)),
          );
        }

        if (!snapshot.hasData || snapshot.data?.data() == null) {
          return const Scaffold(
            backgroundColor: appBg,
            body: Center(child: Text('Данные курьера не найдены', style: TextStyle(color: textMuted, fontWeight: FontWeight.bold))),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;

        final String callsign = data['callsign'] ?? '---';
        final String name = data['name'] ?? 'Без имени';
        final bool isOnDuty = data['isOnDuty'] ?? false;

        final String priority = data['priority']?.toString() ?? '1';
        final String rating = data['rating']?.toString() ?? '75';

        return Scaffold(
          backgroundColor: appBg,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Главная карточка профиля
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Позывной
                      Text(
                        callsign,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 28,
                          color: primaryBlue,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Имя
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: textMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Divider(height: 1, color: borderColor),
                      const SizedBox(height: 20),

                      // Блоки с приоритетом и рейтингом (в виде аккуратных мини-карточек)
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              icon: Icons.flash_on_rounded,
                              label: 'ПРИОРИТЕТ',
                              value: priority,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              icon: Icons.star_rounded,
                              label: 'РЕЙТИНГ',
                              value: rating,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Кнопки управления сменой
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: isOnDuty ? null : () => _toggleDutyStatus(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isOnDuty ? innerBg : primaryBlue,
                            foregroundColor: isOnDuty ? textMuted : Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text(
                            'НАЧАТЬ',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: !isOnDuty ? null : () => _toggleDutyStatus(false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: !isOnDuty ? innerBg : const Color(0xFFDC2626),
                            foregroundColor: !isOnDuty ? textMuted : Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.stop_rounded, size: 20),
                          label: const Text(
                            'ЗАВЕРШИТЬ',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Кнопка карты
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: widget.onOpenMap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textDark,
                      backgroundColor: cardBg,
                      side: const BorderSide(color: borderColor, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.map_rounded, size: 18, color: primaryBlue),
                    label: const Text(
                      'ОТКРЫТЬ КАРТУ',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Виджет для красивой мини-карточки показателей (приоритет / рейтинг)
  Widget _buildMetricCard({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: innerBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: primaryBlue),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: textMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}