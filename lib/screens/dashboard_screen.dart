// lib/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/storage_service.dart';
import '../services/session_service.dart'; 
import 'meter_dashboard_screen.dart'; // O la ruta relativa correcta, ej: '../widgets/meter_dashboard_screen.dart'

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

// AGREGADO: 'with WidgetsBindingObserver' para escuchar cuando el usuario regresa a la App
class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    // Registramos el observador del ciclo de vida
    WidgetsBinding.instance.addObserver(this);
    _sincronizarEstadoUsuario();
  }

  @override
  void dispose() {
    // Destruimos el observador al salir de la pantalla
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // SOLUCIÓN AL NAVEGADOR EXTERNO: Se ejecuta automáticamente al volver de Stripe/Navegador externo
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("La aplicación ha vuelto al primer plano. Sincronizando estado...");
      _sincronizarEstadoUsuario();
    }
  }

  /// Petición al Backend para leer el estado real de la base de datos
  Future<void> _sincronizarEstadoUsuario() async {
    if (StorageService.userStateNotifier.value == UserState.guest) return;

    try {
      final token = SessionService.getToken(); 
      final url = Uri.parse('http://localhost:3000/auth/profile'); 

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userMap = data['user'] ?? data;

        if (userMap != null) {
          final String nombreReal = userMap['username'] ?? 'Usuario Premium';
          final bool esSuscripcionActiva = userMap['isActive'] ?? false;

          StorageService.setMockState(
            esSuscripcionActiva ? UserState.premiumActive : UserState.premiumInactive,
            name: nombreReal,
          );
        }
      }
    } catch (e) {
      debugPrint('Sincronización silenciosa omitida: $e');
    }
  }

  void _cerrarSesion(BuildContext context) async {
    await StorageService.clearSession();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
    }
  }

  void _mostrarDialogoCancelar(BuildContext context, String? userName, String? userEmail) {
    final TextEditingController confirmacionController = TextEditingController();
    bool esBotonHabilitado = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: const Text('Cancelar Plan Premium', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Estas a punto de cancelar tu subscripcion, escribe eliminar para confirmar:',
                    style: TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmacionController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'eliminar',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (text) {
                      setDialogState(() {
                        esBotonHabilitado = text.trim().toLowerCase() == 'eliminar';
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Volver', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: esBotonHabilitado
                      ? () async {
                          Navigator.pop(context); 
                          await _ejecutarCancelacionSuscripcion(userName, userEmail);
                        }
                      : null,
                  child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _ejecutarCancelacionSuscripcion(String? userName, String? userEmail) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final token = SessionService.getToken();
      final url = Uri.parse('http://localhost:3000/auth/paymethods');

      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'email': userEmail, 
        }),
      );

      if (mounted) Navigator.pop(context); 

      if (response.statusCode == 200 || response.statusCode == 204) {
        StorageService.setMockState(
          UserState.premiumInactive,
          name: userName ?? 'Usuario Premium',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Suscripción cancelada correctamente.'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error del servidor: ${response.statusCode}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); 
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de red al intentar cancelar.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final String? userEmail = args is String ? args : null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0052CC),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Metri GAS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        // SOLUCIÓN DE RESPALDO: Agregamos un botón manual de actualizar en la barra superior
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Actualizar Estado',
            onPressed: () async {
              await _sincronizarEstadoUsuario();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Estado de cuenta actualizado.'), duration: Duration(seconds: 1)),
                );
              }
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<UserState>(
        valueListenable: StorageService.userStateNotifier,
        builder: (context, userState, child) {
          final String? userName = StorageService.userName;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPerfilSeccionCondicional(context, userState, userName, userEmail),
                      
                      const SizedBox(height: 24),
                      const Text('MIS MEDIDORES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),

                      _buildMedidoresSectionPlaceholder(userState),
                    ],
                  ),
                ),
              ),
              _buildBotonEnlazarPlaceholder(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPerfilSeccionCondicional(BuildContext context, UserState state, String? userName, String? userEmail) {
    switch (state) {
      case UserState.guest:
        return _buildCardInvitado(context);
      case UserState.premiumActive:
        return _buildCardPremium(context, esActivo: true, userName: userName, userEmail: userEmail);
      case UserState.premiumInactive:
        return _buildCardPremium(context, esActivo: false, userName: userName, userEmail: userEmail);
    }
  }

  Widget _buildCardInvitado(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Vuelvete premium y accede a las funciones completas',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• Historiales de consumo', style: TextStyle(color: Colors.grey)),
                Text('• Predicciones con IA', style: TextStyle(color: Colors.grey)),
                Text('• Pago rapido y seguro', style: TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0052CC),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pushNamed(context, '/login'),
                child: const Text('Volverme Premium', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCardPremium(BuildContext context, {required bool esActivo, required String? userName, required String? userEmail}) {
    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: Color(0xFF4285F4),
                  child: Icon(Icons.person, size: 32, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Nombre de usuario:', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      Text(userName ?? 'Usuario Premium', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Subscripcion:', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    Text(
                      esActivo ? 'ACTIVA' : 'INACTIVA', 
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        color: esActivo ? const Color(0xFF4285F4) : Colors.red,
                        fontSize: 14
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            if (!esActivo) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'Su suscripción no está activa. Si no paga en 1 mes se borrará toda su info de la BD',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                      side: BorderSide(color: Colors.grey[400]!),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () => _cerrarSesion(context),
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Salir', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: esActivo ? Colors.red[700] : const Color(0xFF0052CC),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () {
                      if (esActivo) {
                        _mostrarDialogoCancelar(context, userName, userEmail);
                      } else {
                        // Navegamos y al regresar (sea por pop o descarte) llamamos a la sincronización
                        Navigator.pushNamed(
                          context, 
                          '/subscription', 
                          arguments: userEmail
                        ).then((_) => _sincronizarEstadoUsuario());
                      }
                    },
                    child: Text(
                      esActivo ? 'Cancelar Plan' : 'Pagar Mes',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
////REEMPLAZAR POR DATOS REALES DE LA BASE DE DATOS, PERO POR AHORA USAMOS PLACEHOLDERS PARA PRUEBAS
  Widget _buildMedidoresSectionPlaceholder(UserState userState) {
    // Determinamos si el usuario actual tiene el premium activo según su estado
    final bool isPremiumActive = userState == UserState.premiumActive;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: const Icon(Icons.gas_meter, color: Color(0xFF0052CC), size: 36),
        title: const Text(
          'Cocina Principal',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('ID: 3BC8E162 • 15 Litros'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: () {
          // ENLAZAR AQUÍ: Navegación transfiriendo los parámetros exactos exigidos por el ticket
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MeterDashboardScreen(
                hardwareId: '3bc8e162-4217-4934-bc2c-5645367b1201',
                alias: 'Cocina Principal',
                capacityLiters: 15.0,
                isPremiumActive: isPremiumActive, // Sincronizado dinámicamente con el estado de tu Dashboard
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBotonEnlazarPlaceholder() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0052CC),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {},
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('Enlazar nuevo medidor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}