import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // 🔹 теперь Firebase видит курьерское приложение
  );

  runApp(const CourierApp());
}

class CourierApp extends StatelessWidget {
  const CourierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Courier App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.deepOrange),
      home: const LoginScreen(),
    );
  }
}
