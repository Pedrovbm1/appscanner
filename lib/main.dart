import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const EscanerApp());
}

class EscanerApp extends StatelessWidget {
  const EscanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppScanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00796B)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
