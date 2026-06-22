import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/verification_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/placeholder_screen.dart';

void main() {
  // Inicialización limpia nativa de Flutter sin componentes externos
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
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/verify': (context) => const VerificationScreen(),
        '/subscription': (context) => const SubscriptionScreen(),
        '/dashboard': (context) => const PlaceholderScreen(title: 'Dashboard Principal (Usuario Premium)'),
        '/reset-password': (context) => const PlaceholderScreen(title: 'Recuperación de Contraseña'),
      },
    );
  }
}