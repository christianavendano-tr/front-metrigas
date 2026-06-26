import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../widgets/wave_clipper.dart';
import '../services/session_service.dart';
import '../services/storage_service.dart'; 
import '../services/meter_manager.dart'; 

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final url = Uri.parse('http://localhost:3000/auth/login'); 
    
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'pwd': _passwordController.text,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        String token = data['accessToken'];

        SessionService.saveToken(token);

        String nombreReal = 'Usuario Premium';
        bool esSuscripcionActiva = false;
        String? serverUserId; // <-- Guardará el UUID real de la BD

        if (data['user'] != null) {
          nombreReal = data['user']['username'] ?? 'Usuario Premium';
          esSuscripcionActiva = data['user']['isActive'] ?? false;
          serverUserId = data['user']['id']?.toString(); // <-- EXTRAEMOS EL UUID REAL
        }

        UserState estadoFinalUsuario = esSuscripcionActiva 
            ? UserState.premiumActive 
            : UserState.premiumInactive;

        StorageService.setMockState(
          estadoFinalUsuario, 
          name: nombreReal, 
        );

        // =======================================================================
        // ENTRADA SEGURO A LA MIGRACIÓN PASANDO EL UUID DEL USUARIO LOGGEADO
        // =======================================================================
        try {
          await MeterManager.migrarMedidoresLocalesAlServidor(serverUserId);
        } catch (e) {
          debugPrint('Error en la llamada de migración de datos: $e');
        }
        // =======================================================================

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('¡Ingreso Exitoso!')),
          );
          
          Navigator.pushNamedAndRemoveUntil(
            context, 
            '/dashboard', 
            (route) => false,
            arguments: _emailController.text.trim(), 
          );
        }
      } else if (response.statusCode == 401) {
        _showErrorDialog('Correo o contraseña incorrectos.');
      } else {
        _showErrorDialog('Error en el servidor. Código: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorDialog('No se pudo conectar al servidor. Verifica tu red y el backend.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error de Autenticación'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Políticas de Privacidad'),
        content: const SingleChildScrollView(
          child: ListBody(
            children: [
              Text('Título 1: Aviso de Privacidad', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 5),
              Text('Datos personales que recabamos y su finalidad En Metrigas...'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            ClipPath(
              clipper: WaveClipper(),
              child: Container(
                width: double.infinity,
                height: size.height * 0.42,
                color: const Color(0xFF0052CC), 
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: 40),
                    Text('Metri GAS', style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold)),
                    SizedBox(height: 25),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40.0),
                      child: Text(
                        'Inicia sesion con tu correo\ny contraseña para ingresar',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 18, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Correo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'correoelectrónico@dominio.com',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'El correo no puede estar vacío';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text('Contraseña', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: 'contraseña',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'La contraseña no puede estar vacía';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Continuar', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pushNamed(context, '/forgot'),
                            child: const Text(
                              '¿Olvidaste tu contraseña?',
                              style: TextStyle(color: Color(0xFF0066FF), fontSize: 15, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(height: 20),
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(color: Colors.black, fontSize: 15),
                              children: [
                                const TextSpan(text: '¿Aun no tienes una cuenta? '),
                                TextSpan(
                                  text: 'Registrarme',
                                  style: const TextStyle(color: Color(0xFF0044CC), fontWeight: FontWeight.bold),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () => Navigator.pushNamed(context, '/register'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextButton.icon(
                            onPressed: () {
                              StorageService.setMockState(UserState.guest);
                              Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
                            },
                            icon: const Icon(Icons.arrow_back, size: 16, color: Color(0xFF0052CC)),
                            label: const Text(
                              'Continuar como invitado',
                              style: TextStyle(
                                color: Color(0xFF0052CC), 
                                fontSize: 15, 
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}