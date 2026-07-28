import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class LocationService {
  static StreamSubscription<Position>? _positionStreamSubscription;

  static Future<void> startTracking(String courierId) async {
    stopTracking();

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('❌ GPS отключен.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('❌ Разрешения на геолокацию отклонены.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('❌ Разрешения на геолокацию заблокированы навсегда.');
      return;
    }

    // Профессиональная настройка с интервалом и фильтром расстояния
    LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Обновлять, если проехал хотя бы 10 метров
        intervalDuration: const Duration(seconds: 5), // Интервал не чаще 1 раза в 5 секунд
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "Курьер в работе",
          notificationText: "Отслеживание геолокации активно",
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
          (Position position) async {
        try {
          await FirebaseFirestore.instance
              .collection('couriers')
              .doc(courierId)
              .update({
            'latitude': position.latitude,
            'longitude': position.longitude,
            'lastLocationUpdate': FieldValue.serverTimestamp(),
          });

          debugPrint('📍 Координаты обновлены в БД: ${position.latitude}, ${position.longitude}');
        } catch (e) {
          debugPrint('❌ Ошибка записи геолокации в Firestore: $e');
        }
      },
      onError: (error) {
        debugPrint('❌ Ошибка в потоке геолокации: $error');
      },
    );
  }

  static void stopTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    debugPrint('🛑 Трекинг геолокации остановлен.');
  }
}