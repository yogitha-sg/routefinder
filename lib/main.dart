import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/voice_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize voice / text-to-speech
  await VoiceService.instance.init();

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