import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/registration_service.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  // 6 cajas para los 6 caracteres de tu backend
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  
  // Variable de control crucial para congelar la interfaz
  bool _isLoading = false;

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyToken() async {
    // 1. BARRERA INVISIBLE: Si ya está cargando, ignora cualquier clic extra
    if (_isLoading) return;

    String pin = _controllers.map((c) => c.text).join();
    
    if (pin.length < 6) {
      _showSnackBar('Por favor complete el código de 6 caracteres.', Colors.orange);
      return;
    }

    final email = RegistrationService.temporaryEmail;
    if (email == null) {
      _showSnackBar('Falta referencia del correo electrónico.', Colors.red);
      return;
    }

    // 2. CONGELACIÓN DE UI: Cambiamos el estado a cargando inmediatamente
    setState(() => _isLoading = true);

    try {
      // Realizamos el POST único hacia /auth/verify
      final response = await RegistrationService.verifyCode(email: email, code: pin);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          _showSnackBar('¡Cuenta verificada con éxito!', Colors.green);
          
          // Como tu endpoint no devuelve token (JWT), mandamos al usuario a iniciar
          // sesión para que capture su token real en la pantalla de Login.
          Navigator.pushNamedAndRemoveUntil(context, '/subscription', (route) => false);
        }
      }
    } on DioException catch (e) {
      final errorData = e.response?.data;
      
      // 3. TOLERANCIA DE RED FANTASMA: Si por milésimas llegó a pasarse un segundo clic de red
      // y el backend responde que ya estaba verificada, lo tomamos como éxito.
      if (errorData != null && errorData['message'] == "La cuenta ya está verificada") {
        if (mounted) {
          _showSnackBar('¡Cuenta lista! Procediendo...', Colors.green);
          Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        }
        return;
      }

      final errorMsg = errorData?['message'] ?? 'Código incorrecto o expirado.';
      _showSnackBar(errorMsg.toString(), Colors.red);
    } catch (e) {
      _showSnackBar('Error de conexión con el servidor de Metrigas.', Colors.red);
    } finally {
      // 4. LIBERACIÓN: Si hubo un error real (código equivocado), volvemos a activar el botón
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final targetEmail = RegistrationService.temporaryEmail ?? 'tu correo registrado';

    return Scaffold(
      backgroundColor: const Color(0xFF0052CC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Metri GAS', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 25),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Escriba su token de verificación', style: TextStyle(color: Color(0xFF0052CC), fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 10),
                          Text('Enviamos un código de 6 caracteres a\n$targetEmail', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF0044CC), fontSize: 14, height: 1.3)),
                          const SizedBox(height: 25),
                          const Align(alignment: Alignment.centerLeft, child: Text('Token:', style: TextStyle(fontWeight: FontWeight.bold))),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: List.generate(6, (index) {
                              return SizedBox(
                                width: 42, // Ancho ideal para pantallas medianas/grandes de iOS
                                height: 50, // Forzamos una altura fija estructural
                                child: TextField(
                                  controller: _controllers[index],
                                  focusNode: _focusNodes[index],
                                  keyboardType: TextInputType.number, // Si tu backend solo manda números, mejor asegurar teclado numérico
                                  textAlign: TextAlign.center,
                                  maxLength: 1,
                                  // Estilo de texto calibrado para que no se desborde
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                                  decoration: const InputDecoration(
                                    counterText: "", 
                                    border: OutlineInputBorder(),
                                    // LA CLAVE: Eliminamos los paddings por defecto para que el texto no se corte
                                    contentPadding: EdgeInsets.zero, 
                                  ),
                                  onChanged: (value) {
                                    if (value.isNotEmpty && index < 5) {
                                      FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
                                    } else if (value.isEmpty && index > 0) {
                                      FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
                                    }
                                  },
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              // Aquí está la magia: si carga es null (deshabilitado), si no corre la función
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black, 
                                disabledBackgroundColor: Colors.grey, // Color gris si se congela
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                              ),
                              onPressed: _isLoading ? null : _verifyToken,
                              child: _isLoading 
                                  ? const CircularProgressIndicator(color: Colors.white) 
                                  : const Text('Confirmar', style: TextStyle(color: Colors.white, fontSize: 16)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}