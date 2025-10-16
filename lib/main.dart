import 'package:flutter/material.dart';
import 'presentation/screens/splash_screen.dart';
import 'routes/app_routes.dart';
import 'core/constants/app_colors.dart';

void main() {
  runApp(const HearWiseApp());
}

class HearWiseApp extends StatelessWidget {
  const HearWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HearWise',
      theme: ThemeData(
        fontFamily: 'Poppins',
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
      ),
      initialRoute: AppRoutes.splash,
      routes: AppRoutes.routes,
    );
  }
}
