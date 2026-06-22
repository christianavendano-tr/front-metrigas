import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
<<<<<<< HEAD
import 'screens/register_screen.dart';
import 'screens/verification_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/placeholder_screen.dart';
=======
import 'screens/forgot_password_screen.dart';
import 'screens/verify_token_screen.dart';
import 'screens/new_password_screen.dart';

// Importa aquí tus pantallas ya existentes para que las rutas que
// el login ya usa (/dashboard y /register) también funcionen:
// import 'screens/dashboard_screen.dart';
// import 'screens/register_screen.dart';
>>>>>>> 75a1f083963708866c2e9a834108180791b30696

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
        primaryColor: const Color(0xFF0052CC),
        useMaterial3: true,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
<<<<<<< HEAD
        '/register': (context) => const RegisterScreen(),
        '/verify': (context) => const VerificationScreen(),
        '/subscription': (context) => const SubscriptionScreen(),
        '/dashboard': (context) => const PlaceholderScreen(title: 'Dashboard Principal (Usuario Premium)'),
        '/reset-password': (context) => const PlaceholderScreen(title: 'Recuperación de Contraseña'),
=======
        '/reset-password': (context) => const ForgotPasswordScreen(),
        '/verify-token': (context) => const VerifyTokenScreen(),
        '/new-password': (context) => const NewPasswordScreen(),

        // Descomenta estas líneas cuando tengas esos archivos listos,
        // si no, Navigator.pushNamed(context, '/dashboard') o
        // '/register' lanzará un error de ruta no encontrada:
        // '/dashboard': (context) => const DashboardScreen(),
        // '/register': (context) => const RegisterScreen(),
>>>>>>> 75a1f083963708866c2e9a834108180791b30696
      },
    );
  }
}