import 'package:flutter/material.dart';

class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Красивая иконка или картинка
              Icon(Icons.wifi_off_rounded, size: 100, color: Colors.grey[300]),
              const SizedBox(height: 30),
              const Text(
                "УПС... ИНТЕРНЕТ ПРОПАЛ",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
              const SizedBox(height: 15),
              Text(
                "Приложение временно заблокировано. Проверьте подключение к мобильной сети или Wi-Fi, чтобы продолжить работу с заказами.",                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5),
              ),
              const SizedBox(height: 40),
              // Можно добавить лоадер, который крутится, пока ждем сеть
              const CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
            ],
          ),
        ),
      ),
    );
  }
}