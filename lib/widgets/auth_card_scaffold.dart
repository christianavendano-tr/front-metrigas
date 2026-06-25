import 'package:flutter/material.dart';

/// Estructura visual compartida por las pantallas de autenticación
/// (Recuperar contraseña, Token de verificación, Registro, Nueva
/// contraseña). Fondo azul de marca con "Metri GAS" en la parte
/// superior y una tarjeta blanca centrada que contiene el formulario.
class AuthCardScaffold extends StatelessWidget {
  final Widget child;
  const AuthCardScaffold({super.key, required this.child});

  /// Azul de marca usado en toda la app.
  static const Color primaryBlue = Color(0xFF0052CC);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryBlue,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Metri GAS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 25),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}