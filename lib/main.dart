import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const HydroPulseApp());
}

class HydroPulseApp extends StatelessWidget {
  const HydroPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HydroPulse',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        fontFamily: 'Arial',
      ),
      home: const HomeScreen(),
    );
  }
}