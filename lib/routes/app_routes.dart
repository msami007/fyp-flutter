import 'package:flutter/material.dart';
import '../presentation/screens/splash_screen.dart';
import '../presentation/screens/login_screen.dart';
import '../presentation/screens/signup_screen.dart';
import '../presentation/screens/home_screen.dart';
import '../presentation/screens/connect_device_screen.dart';
import '../presentation/screens/main_screen.dart';
import '../presentation/screens/onboarding.dart';
import '../presentation/screens/transcription_screen.dart';
import '../presentation/screens/conversation_history_screen.dart';
import '../presentation/screens/model_settings_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String main = '/main';
  static const String home = '/home';
  static const String connectDevice = '/connect-device';
  static const String transcription = '/transcription';
  static const String conversationHistory = '/conversation-history';
  static const String modelSettings = '/model-settings';

  static Map<String, WidgetBuilder> routes = {
    splash: (context) => const SplashScreen(),
    onboarding: (context) => const OnboardingPage(),
    login: (context) => const LoginScreen(),
    signup: (context) => const SignupScreen(),
    main: (context) => const MainScreen(),
    home: (context) => const HomeScreen(),
    connectDevice: (context) => const ConnectDeviceScreen(),
    transcription: (context) => const TranscriptionScreen(),
    conversationHistory: (context) => const ConversationHistoryScreen(),
    modelSettings: (context) => const ModelSettingsScreen(),
  };
}

