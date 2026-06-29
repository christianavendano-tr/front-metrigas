// lib/screens/add_meter_bt.dart
import 'package:flutter/material.dart';

class AddMeterBtScreen extends StatefulWidget {
  const AddMeterBtScreen({super.key});

  @override
  State<AddMeterBtScreen> createState() => _AddMeterBtScreenState();
}

class _AddMeterBtScreenState extends State<AddMeterBtScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  // Paleta de colores idéntica a tus otras pantallas
  static const Color primaryBlue = Color(0xFF0052CC); 
  static const Color lightBlue = Color(0xFF0088FF);

  @override
  void initState() {
    super.initState();
    // Controlador para la animación de ondas de radar en bucle continuo
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Widget auxiliar para crear las ondas expansivas de escaneo
  Widget _buildOnda(double retraso) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        double progreso = (_animationController.value + retraso) % 1.0;
        double escala = 1.0 + (progreso * 1.2);
        double opacidad = (1.0 - progreso).clamp(0.0, 1.0) * 0.3;

        return Transform.scale(
          scale: escala,
          child: Opacity(
            opacity: opacidad,
            child: Container(
              width: 150,
              height: 150,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: lightBlue,
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Header azul: "Metri GAS" (Totalmente Centrado y sin avatar de usuario)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: primaryBlue,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: const SafeArea(
        bottom: false,
        child: Text(
          'Metri GAS',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white, 
            fontSize: 20, 
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sub-header: Flecha atrás + Título "Enlazar Medidor" perfectamente centrado
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSubHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      color: lightBlue,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
          ),
          const Expanded(
            child: Text(
              'Enlazar Medidor',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white, 
                fontWeight: FontWeight.w600, 
                fontSize: 15,
              ),
            ),
          ),
          // Mantenemos un espacio del mismo tamaño del botón de atrás para equilibrar el centrado
          const SizedBox(width: 48), 
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E5E5),
      body: Column(
        children: [
          // Sección de cabeceras estructuradas
          _buildHeader(),
          _buildSubHeader(context),
          
          // Cuerpo compacto y centrado
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 30.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 25),
                    
                    // 1. Texto instructivo
                    const Text(
                      'Conecta tu medidor por medio de bluetooth para poder iniciar el proceso de enlace. Una vez que tu dispositivo se conecte, vuelve a esta pantalla y da click en continuar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    
                    const SizedBox(height: 45),

                    // 2. Icono de Bluetooth con Ondas de radar activas
                    Center(
                      child: SizedBox(
                        width: 260,
                        height: 260,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Capas de ondas en segundo plano
                            _buildOnda(0.0),
                            _buildOnda(0.35),
                            _buildOnda(0.7),

                            // Círculo base blanco con sombras fijas
                            Container(
                              width: 175,
                              height: 175,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 12,
                                    spreadRadius: 4,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Center(
                                // Círculo interno con degradado azul
                                child: Container(
                                  width: 115,
                                  height: 115,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF66B2FF), lightBlue],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.bluetooth,
                                    size: 70,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 45),

                    // 3. Botón Continuar
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 2,
                        ),
                        onPressed: () {
                          // Espacio listo para la inyección de lógica posterior
                        },
                        child: const Text(
                          'Continuar',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}