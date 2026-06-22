import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart'; 
import '../services/registration_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isProcessing = false;

  Future<void> _redirectStripeCheckout() async {
    setState(() => _isProcessing = true);

    try {
      // Recuperamos el email transicional capturado en el registro
      final String? userEmail = RegistrationService.temporaryEmail;

      if (userEmail == null) {
        _showSnackBar('No se encontró el correo de la sesión actual.', Colors.red);
        return;
      }

      // Invocamos el servicio pasándole únicamente el correo que pide el MailDto
      final response = await RegistrationService.createSubscription(
        email: userEmail,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Tu backend modificado ahora devuelve: { "url": "https://checkout.stripe.com/..." }
        final stripeUrl = response.data['url'];

        if (stripeUrl != null) {
          final Uri url = Uri.parse(stripeUrl);
          
          // Abre de forma segura la pasarela web de Stripe en el navegador del dispositivo
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
            
            if (mounted) {
              _showSnackBar('Abriendo pasarela de pago seguro...', Colors.green);
              
              // REDIRECCIÓN COMPLETA: Una vez lanzada con éxito la respuesta, 
              // limpiamos el historial de pantallas y lo mandamos al Dashboard/Home principal.
              // (Si tu ruta se llama '/home' en vez de '/dashboard', cámbiala aquí)
              Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
            }
          } else {
            _showSnackBar('No se pudo abrir la plataforma de Stripe.', Colors.red);
          }
        } else {
          _showSnackBar('El servidor no generó un enlace de pago válido.', Colors.orange);
        }
      }
    } on DioException catch (e) {
      final errorMsg = e.response?.data['message'] ?? 'Error al procesar la pasarela de pago.';
      _showSnackBar(errorMsg.toString(), Colors.red);
    } catch (e) {
      _showSnackBar('Error de conexión con el servidor.', Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSnackBar(String msg, Color col) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: col));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0052CC),
      body: SafeArea(
        child: Stack(
          children: [
            // MODIFICADO: Botón superior izquierdo que destruye el flujo actual y regresa al Login
            Positioned(
              top: 10,
              left: 10,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                },
              ),
            ),
            // Contenido original completamente intacto
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Metri GAS Premium ✨', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          const Text('Estás a un paso de activar tu cuenta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 20),
                          _buildBenefit(Icons.analytics, 'Análisis de consumo en tiempo real'),
                          _buildBenefit(Icons.picture_as_pdf, 'Reportes descargables'),
                          const SizedBox(height: 25),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: const Color(0xFFE6F0FF), borderRadius: BorderRadius.circular(12)),
                            child: const Column(
                              children: [
                                Text('\$80 MXN', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF0044CC))),
                                Text('por mes', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 25),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF002266)),
                              onPressed: _isProcessing ? null : _redirectStripeCheckout,
                              child: _isProcessing 
                                  ? const CircularProgressIndicator(color: Colors.white) 
                                  : const Text('Proceder al pago seguro', style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefit(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(children: [Icon(icon, color: const Color(0xFF0052CC)), const SizedBox(width: 10), Text(text)]),
    );
  }
}