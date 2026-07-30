import 'package:flutter/material.dart';
import 'package:fyp/home_screen.dart';

void main() => runApp(const GestureVoiceApp());

/// App-wide colors (ek hi jagah se theme control)
class AppColors {
  static const bg1 = Color(0xFF0B0B1A);
  static const bg2 = Color(0xFF1A1633);
  static const accent = Color(0xFF7C4DFF);
  static const accent2 = Color(0xFF4D8AFF);
  static const danger = Color(0xFFFF5C7A);
  static const glass = Color(0x14FFFFFF); // white @ 8%
}

class GestureVoiceApp extends StatelessWidget {
  const GestureVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GestureVoice',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bg1,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}