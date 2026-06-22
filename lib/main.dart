import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/register_screen.dart';
import 'screens/verification_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/placeholder_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MetriGasApp());
}

class MetriGasApp extends StatelessWidget {
  const MetriGasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Metri GAS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF0052CC),
        useMaterial3: true,
      ),
      initialRoute: '/login',
      routes: {
        '/login':        (context) => const LoginScreen(),
        '/reset-password': (context) => const ForgotPasswordScreen(),
        '/register':     (context) => const RegisterScreen(),
        '/verify':       (context) => const VerificationScreen(),
        '/subscription': (context) => const SubscriptionScreen(),
        '/dashboard':    (context) => const PlaceholderScreen(title: 'Dashboard Principal (Usuario Premium)'),
      },
    );
  }
}