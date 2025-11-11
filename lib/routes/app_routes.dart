import 'package:flutter/material.dart';
import '../presentation/screens/splash_screen.dart';
import '../presentation/screens/login_screen.dart';
import '../presentation/screens/signup_screen.dart';
import '../presentation/screens/home_screen.dart';
import '../presentation/screens/connect_device_screen.dart';
import '../presentation/screens/main_screen.dart';
import '../presentation/screens/onboarding.dart';

class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String main = '/main'; // 👈 add this
  static const String home = '/home';
  static const String connectDevice = '/connect-device';

  static Map<String, WidgetBuilder> routes = {
    splash: (context) => const SplashScreen(),
    onboarding: (context) => const OnboardingPage(),
    login: (context) => const LoginScreen(),
    signup: (context) => const SignupScreen(),
    main: (context) => const MainScreen(), // 👈 add this
    home: (context) => const HomeScreen(),
    connectDevice: (context) => const ConnectDeviceScreen(),
  };
}
