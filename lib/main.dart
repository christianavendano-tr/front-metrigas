import 'package:flutter/material.dart';
import 'services/storage_service.dart';
import 'services/session_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/verification_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/meter_dashboard_screen.dart';
import 'screens/add_meter_bt_screen.dart';
import 'screens/meter_history_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SessionService.init();
  await StorageService.init();
  
  // ======================================


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
        scaffoldBackgroundColor: const Color(0xFFE5E5E5),
        useMaterial3: true,
      ),
      initialRoute: StorageService.isFirstTime ? '/welcome' : '/dashboard',
      routes: {
        '/welcome':         (context) => const WelcomeScreen(),
        '/dashboard':       (context) => const DashboardScreen(),
        '/login':           (context) => const LoginScreen(),
        '/register':        (context) => const RegisterScreen(),
        '/verify':          (context) => const VerificationScreen(),
        '/subscription':    (context) => const SubscriptionScreen(),
        '/forgot':          (context) => const ForgotPasswordScreen(),
        '/meter-dashboard': (context) => const MeterDashboardScreen(),
        '/add-meter': (context) => const AddMeterBtScreen(),
        '/meter-history':   (context) => const MeterHistoryScreen(),
      },
    );
  }
}