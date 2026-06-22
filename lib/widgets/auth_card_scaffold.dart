import 'package:flutter/material.dart';

/// Estructura visual compartida por las pantallas de recuperación de
/// contraseña (Recuperar contraseña, Token de verificación, Nueva
/// contraseña). Reutiliza el mismo azul y la misma tipografía que el
/// login para que las 3 pantallas se vean consistentes con el resto
/// de la app.
class AuthCardScaffold extends StatelessWidget {
  final Widget child;
  const AuthCardScaffold({super.key, required this.child});

  /// Mismo azul que usa el header del login (Color(0xFF0052CC)).
  static const Color primaryBlue = Color(0xFF0052CC);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Franja azul de fondo, igual a la que se ve detrás de la
          // tarjeta blanca en el diseño.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 230,
            child: Container(color: primaryBlue),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Metri GAS',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFD9D9D9)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: child,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}