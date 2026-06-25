// lib/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/storage_service.dart';
import '../services/session_service.dart'; 
import '../services/meter_manager.dart'; 

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _medidores = [];
  bool _isLoadingMeters = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sincronizarEstadoUsuario();
    _cargarListadoMedidores(); 
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sincronizarEstadoUsuario();
      _cargarListadoMedidores();
    }
  }

  Future<void> _cargarListadoMedidores() async {
    if (!mounted) return;
    setState(() => _isLoadingMeters = true);
    
    final lista = await MeterManager.obtenerMedidores();
    
    if (mounted) {
      setState(() {
        _medidores = lista;
        _isLoadingMeters = false;
      });
    }
  }

  // =======================================================================
  // INYECTOR MODO DEV OPTIMIZADO CON FORMATO ESTRUCTURAL DE GUIONES UUID
  // =======================================================================
  Future<void> _inyectarMedidoresModoDev() async {
    final medidor1 = {
      "id": "e3b0c442-98fc-413b-9671-9a81817fc7e2", // Formato estructural correcto
      "metername": "Cocina Principal",
      "capacity": "20.0",
      "ownerId": "invitado-local-id"
    };
    final medidor2 = {
      "id": "f2a1d553-09eb-524c-8762-0b92928ed8f3", // Formato estructural correcto
      "metername": "Calentador",
      "capacity": "10.0",
      "ownerId": "invitado-local-id"
    };

    await MeterManager.guardarMedidorLocal(medidor1);
    await MeterManager.guardarMedidorLocal(medidor2);
    await _cargarListadoMedidores();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔧 Modo Dev: Medidores UUID inyectados localmente.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

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

  void _manejarAccionNuevoMedidor(UserState estadoActual, String? userEmail) {
    Navigator.pushNamed(context, '/add-meter', arguments: userEmail).then((_) {
      _cargarListadoMedidores();
    });
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () async {
              await _sincronizarEstadoUsuario();
              await _cargarListadoMedidores();
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('MIS MEDIDORES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          if (userState == UserState.guest)
                            TextButton.icon(
                              onPressed: _inyectarMedidoresModoDev,
                              icon: const Icon(Icons.developer_mode, size: 16, color: Colors.orange),
                              label: const Text('Inyectar Medidores (Dev)', style: TextStyle(color: Colors.orange, fontSize: 12)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      _buildSeccionMedidoresDinamica(),
                    ],
                  ),
                ),
              ),
              _buildBotonEnlazarDinamico(userState, userEmail),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSeccionMedidoresDinamica() {
    if (_isLoadingMeters) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_medidores.isEmpty) {
      return Card(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: const Padding(
          padding: EdgeInsets.all(24.0),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              'Aún no tienes medidores enlazados.\nVincule un nuevo medidor a su cuenta para poder acceder a su monitoreo en tiempo real.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, height: 1.4, fontSize: 13),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _medidores.length,
      itemBuilder: (context, index) {
        final meter = _medidores[index];
        final String idHardware = meter['id']?.toString() ?? 'ID-UNK';
        final String aliasHardware = meter['metername'] ?? 'Medidor';
        final String capacidad = meter['capacity']?.toString() ?? '20';
        
        final int porcentajeGas = index == 0 ? 85 : (index == 1 ? 16 : 50);

        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.pushNamed(context, '/meter-dashboard', arguments: idHardware),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        aliasHardware,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$capacidad L - ID:$idHardware',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: porcentajeGas / 100,
                            minHeight: 8,
                            backgroundColor: Colors.blue.withOpacity(0.2),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0052CC)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$porcentajeGas%',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey),
                      )
                    ],
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBotonEnlazarDinamico(UserState estado, String? email) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0052CC),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 2,
          ),
          onPressed: () => _manejarAccionNuevoMedidor(estado, email),
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('Enlazar nuevo medidor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
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
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
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
                        Navigator.pushNamed(
                          context, 
                          '/subscription', 
                          arguments: userEmail
                        ).then((_) {
                          _sincronizarEstadoUsuario();
                          _cargarListadoMedidores();
                        });
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
}