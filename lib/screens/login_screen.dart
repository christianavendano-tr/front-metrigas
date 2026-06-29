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

        // 1. Guardamos el token de forma asíncrona y persistente en el dispositivo
        await SessionService.saveToken(token);

        String nombreReal = 'Usuario Premium';
        bool esSuscripcionActiva = false;
        String? serverUserId; // <-- Guarda el UUID real de la BD

        if (data['user'] != null) {
          nombreReal = data['user']['username'] ?? 'Usuario Premium';
          esSuscripcionActiva = data['user']['isActive'] ?? false;
          serverUserId = data['user']['id']?.toString(); // <-- EXTRAEMOS EL UUID REAL
        }
  
        UserState estadoFinalUsuario = esSuscripcionActiva 
            ? UserState.premiumActive 
            : UserState.premiumInactive;

        // 2. Guardamos el estado del usuario e incluimos el 'email' para que persista al reiniciar
        await StorageService.setMockState(
          estadoFinalUsuario, 
          name: nombreReal,
          email: _emailController.text.trim(),
        );

        // =======================================================================
        // ENTRADA SEGURO A LA MIGRACIÓN PASANDO EL UUID DEL USUARIO LOGGEADO (INTACTO)
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

  void _mostrarTerminosPopUp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text(
            'Aviso de Privacidad y Términos y Condiciones',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.6,
            child: const SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'METRIGAS\nAviso de Privacidad y Términos y Condiciones\nÚltima actualización: junio de 2026\n',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black),
                  ),
                  Text(
                    'Al crear una cuenta se dan por aceptados los siguientes terminos:\n\n'
                    'Datos personales que recabamos y su finalidad\n'
                    'En Metrigas, recabamos datos de identificación (nombre, correo, edad) y datos financieros (procesados exclusivamente por Stripe) para gestionar su cuenta, vincular sus medidores, habilitar el historial de consumo para usuarios Premium, procesar pagos y brindar soporte técnico.\n\n'
                    'Derechos ARCO (Acceso, Rectificación, Cancelación y Oposición)\n'
                    'Usted, como titular de los datos personales, tiene derecho a conocer qué datos tenemos de usted, para qué los utilizamos y las condiciones de su uso (Acceso). Asimismo, es su derecho solicitar la corrección de su información personal si está desactualizada, es inexacta o incompleta (Rectificación); que la eliminemos de nuestros registros cuando considere que no se está utilizando adecuadamente (Cancelación); así como oponerse al uso de sus datos personales para fines específicos (Oposición).\n\n'
                    'Para el ejercicio de estos derechos, deberá enviar una solicitud al correo electrónico: privacidad@metrigas.com, incluyendo nombre completo, documento de identidad, y una descripción clara de los datos sobre los que desea ejercer su derecho. Metrigas responderá en un plazo máximo de 20 días hábiles.\n\n'
                    'Alertas de Nivel de Gas y Datos de Consumo\n'
                    'Asi como parte del servicio, Metrigas utiliza los datos de consumo captados por su medidor para generar alertas automáticas. Por defecto, usted recibirá una notificación de existir una fuga de gas que provoque que el nivel del tanque descienda por debajo del 10% antes de que el sistema pueda detectarla, transmitirla o notificarla, Metrigas no será responsable por dicha situación ni por los daños, pérdidas o accidentes que de ella se deriven. El medidor no sustituye la inspección física periódica del tanque ni los mecanismos de seguridad y detección de fugas exigidos por la normatividad aplicable.\n\n'
                    'Propiedad Intelectual\n'
                    'Todo el software, código fuente, logotipos, gráficos, interfaces de usuario y algoritmos (incluyendo el generador congruencial de encriptación utilizado en nuestro firmware) son propiedad exclusiva de Metrigas. Queda prohibida la reproducción, copia, distribución o ingeniería inversa del sistema sin autorización expresa por escrito de los titulares.\n\n'
                    'Modificaciones al Aviso\n'
                    'Este Aviso de Privacidad y los presentes Términos y Condiciones podrán ser modificados por Metrigas para cumplir con cambios legislativos. Dichas actualizaciones estarán disponibles en nuestra aplicación móvil en el apartado correspondiente. El uso continuo de la aplicación constituye la aceptación de las versiones vigentes.\n\n'
                    'Jurisdicción\n'
                    'Para cualquier controversia derivada del uso de nuestros servicios, el usuario se somete a la jurisdicción de los tribunales competentes en la ciudad de Santiago de Querétaro, Querétaro.\n\n'
                    'Al continuar usando la aplicación de Metrigas, usted confirma que ha leído y acepta el presente Aviso de Privacidad y Términos y Condiciones.',
                    style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Entendido', 
                style: TextStyle(color: Color(0xFF0052CC), fontWeight: FontWeight.bold)
              ),
            ),
          ],
        );
      },
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

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: const TextStyle(color: Colors.black, fontSize: 12, height: 1.4),
                                children: [
                                  const TextSpan(text: 'Al continuar, aceptas nuestros '),
                                  TextSpan(
                                    text: 'Términos y Condiciones y Aviso de Privacidad',
                                    style: const TextStyle(
                                      color: Color(0xFF0052CC),
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () => _mostrarTerminosPopUp(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          TextButton.icon(
                            onPressed: () async {
                              // Cambiado a asíncrono para asegurar el guardado persistente del estado "guest"
                              await StorageService.setMockState(UserState.guest);
                              if (context.mounted) {
                                Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
                              }
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