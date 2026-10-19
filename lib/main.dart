import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppTheme.registerFontLicenses();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const EscanerApp());
}

final routeObserver = RouteObserver<ModalRoute<void>>();

class EscanerApp extends StatelessWidget {
  const EscanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppScanner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      navigatorObservers: [routeObserver],
      home: const HomeScreen(),
    );
  }
}
