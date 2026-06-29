// lib/screens/add_meter_bt_screen.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/meter_manager.dart'; // Sincronizado con tu manejador real

class AddMeterBtScreen extends StatefulWidget {
  const AddMeterBtScreen({super.key});

  @override
  State<AddMeterBtScreen> createState() => _AddMeterBtScreenState();
}

class _AddMeterBtScreenState extends State<AddMeterBtScreen> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Llaves globales para validar los formularios nativos de Flutter
  final GlobalKey<FormState> _wifiFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _tankFormKey = GlobalKey<FormState>();

  late AnimationController _animationController;

  // Paleta de colores idéntica a tus otras pantallas
  static const Color primaryBlue = Color(0xFF0052CC); 
  static const Color lightBlue = Color(0xFF0088FF);

  // Controladores de estado de conectividad Bluetooth
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isSendingWifi = false;
  List<ScanResult> _scanResults = [];

  // Variables de control de Hardware BLE
  BluetoothDevice? _targetDevice;
  BluetoothCharacteristic? _wifiCharacteristic; 
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  // Controladores de texto para los formularios de las Fases 3 y 4
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _aliasController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController();

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
    _scanSubscription?.cancel();
    _ssidController.dispose();
    _passwordController.dispose();
    _aliasController.dispose();
    _capacityController.dispose();
    _pageController.dispose();
    // Cerramos canales de radio de forma segura si el usuario abandona a mitad del proceso
    _targetDevice?.disconnect();
    super.dispose();
  }

  // Navegación interna controlada entre fases
  void _goToStep(int step) {
    if (step >= 0 && step <= 3) {
      setState(() => _currentStep = step);
      _pageController.animateToPage(
        step,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  // ===========================================================================
  // MOTOR BLUETOOTH (FASES 1 Y 2)
  // ===========================================================================
  Future<void> _startBleScan() async {
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      _showSnackBar("Por favor, enciende el Bluetooth de tu dispositivo", Colors.orange);
      return;
    }

    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });

    try {
      // Iniciamos escaneo buscando señales cercanas por 15 segundos
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;
        setState(() {
          // Filtramos dispositivos cuyo nombre sea Metrigas (o similar)
          _scanResults = results.where((r) {
            final name = r.device.advName.trim();
            final platformName = r.device.platformName.trim();
            return name.toLowerCase().contains('metrigas') || 
                   platformName.toLowerCase().contains('metrigas') ||
                   name.isNotEmpty; // Deja pasar nombres válidos si estás en pruebas custom
          }).toList();
        });
      });

      Future.delayed(const Duration(seconds: 15), () {
        if (mounted) setState(() => _isScanning = false);
      });
    } catch (e) {
      _showSnackBar("Error al iniciar escaneo: $e", Colors.red);
      setState(() => _isScanning = false);
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() => _isConnecting = true);
    
    try {
      await FlutterBluePlus.stopScan();
      await device.connect(timeout: const Duration(seconds: 5));
      _targetDevice = device;

      // Descubrimos los servicios GATT expuestos por la ESP32
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        // Buscamos características de escritura primaria (UUIDs típicos FFF0 o de datos custom)
        for (var char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _wifiCharacteristic = char;
            break;
          }
        }
      }

      _showSnackBar("¡Medidor enlazado por Bluetooth!", Colors.green);
      _goToStep(2); // Avanza automáticamente a la Fase 3 (Índice 2)

    } catch (e) {
      _showSnackBar("Fallo en el enlace físico. Reintenta.", Colors.red);
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  // ===========================================================================
  // TRANSMIÓN DE CREDENCIALES WI-FI VÍA BLE (FASE 3)
  // ===========================================================================
  Future<void> _enviarCredencialesWifi() async {
    if (_wifiCharacteristic == null) {
      _showSnackBar("Canal de datos BLE no disponible. Reconecta el medidor.", Colors.red);
      return;
    }

    setState(() => _isSendingWifi = true);

    try {
      // Estructura limpia en formato JSON para que el script MicroPython la decodifique con json.loads()
      final Map<String, String> dataMap = {
        "ssid": _ssidController.text.trim(),
        "pwd": _passwordController.text
      };
      
      final String jsonStr = jsonEncode(dataMap);
      final List<int> bytes = utf8.encode(jsonStr);

      // Inyección binaria a la característica del microcontrolador
      await _wifiCharacteristic!.write(bytes, withoutResponse: false);
      
      _showSnackBar("Configuración Wi-Fi enviada al medidor", Colors.green);
      _goToStep(3); // Avanza automáticamente a la Fase 4 (Índice 3)

    } catch (e) {
      _showSnackBar("Error al transmitir datos por Bluetooth: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isSendingWifi = false);
    }
  }

  // ===========================================================================
  // PERSISTENCIA COMPATIBLE CON METER_MANAGER (FASE 4)
  // ===========================================================================
  Future<void> _finalizarConfiguracionMedidor(String? userEmail) async {
    try {
      final String alias = _aliasController.text.trim();
      final String capacidad = _capacityController.text.trim();
      // Usamos el ID de hardware detectado por la antena Bluetooth
      final String dispositivoId = _targetDevice?.remoteId.toString() ?? "ESP32-GENERICO";

      // MAPA DE DATOS REFINADO: Sincronizado milimétricamente con tu MeterManager
      final Map<String, dynamic> nuevoMedidor = {
        "id": dispositivoId,
        "metername": alias, 
        "capacity": capacidad, 
        "ownerId": userEmail ?? "00000000-0000-0000-0000-000000000000" 
      };

      // Invocación nativa a tu servicio local
      await MeterManager.guardarMedidorLocal(nuevoMedidor);

      // Liberación de la antena Bluetooth para ahorrar energía en ambos extremos
      await _targetDevice?.disconnect();
      _targetDevice = null;

      _showSnackBar("¡Medidor registrado en tu almacenamiento local!", Colors.green);
      
      if (mounted) {
        // Regresa limpiando la pila para refrescar el listado del Dashboard
        Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
      }
    } catch (e) {
      _showSnackBar("Error al salvar los cambios en caché: $e", Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 3)),
    );
  }

  // Widget auxiliar para crear las ondas expansivas de escaneo (Tu diseño original)
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

  // Header azul original intacto
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

  // Sub-header adaptado dinámicamente según la fase en curso
  Widget _buildSubHeader(BuildContext context) {
    String stepTitle = "Enlazar Medidor";
    if (_currentStep == 2) stepTitle = "Configuración Wi-Fi";
    if (_currentStep == 3) stepTitle = "Detalles del Tanque";

    return Container(
      width: double.infinity,
      color: lightBlue,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (_currentStep == 0) {
                Navigator.maybePop(context);
              } else {
                _goToStep(_currentStep - 1);
              }
            },
          ),
          Expanded(
            child: Text(
              '$stepTitle (${_currentStep + 1}/4)',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white, 
                fontWeight: FontWeight.w600, 
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 48), 
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Recuperamos el email que le pasa tu Dashboard como argumento
    final args = ModalRoute.of(context)?.settings.arguments;
    final String? userEmail = args is String ? args : null;

    return Scaffold(
      backgroundColor: const Color(0xFFE5E5E5),
      body: Column(
        children: [
          _buildHeader(),
          _buildSubHeader(context),
          
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), 
              children: [
                _fase1Instrucciones(),
                _fase2ListadoDispositivos(),
                _fase3FormularioWiFi(),
                _fase4MetadatosTanque(userEmail),
              ],
            ),
          ),
        ],
      ),
      // ¡AQUÍ ESTÁ TU BOTÓN DE DESARROLLADOR DE VUELTA!
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.developer_mode, color: Colors.white),
        label: const Text('Dev: Forzar Paso', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () {
          if (_currentStep < 3) {
            _goToStep(_currentStep + 1);
          } else {
            // Si estás en la última pantalla, te regresa a la primera para reiniciar el loop de pruebas
            _goToStep(0);
          }
        },
      ),
    );
  }

  // ===========================================================================
  // VISTA: FASE 1 - INSTRUCCIONES INICIALES
  // ===========================================================================
  Widget _fase1Instrucciones() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 30.0),
        child: Column(
          children: [
            const SizedBox(height: 25),
            const Text(
              'Conecta tu medidor por medio de bluetooth para poder iniciar el proceso de enlace. Una vez que tu dispositivo se conecte, pasaremos al aprovisionamiento local.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 45),
            Center(
              child: SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _buildOnda(0.0),
                    _buildOnda(0.35),
                    _buildOnda(0.7),
                    Container(
                      width: 175,
                      height: 175,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12, spreadRadius: 4, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 115,
                          height: 115,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [Color(0xFF66B2FF), lightBlue], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                          ),
                          child: const Icon(Icons.bluetooth, size: 70, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 45),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 2),
                onPressed: () {
                  _goToStep(1);
                  _startBleScan();
                },
                child: const Text('Iniciar Escaneo', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // VISTA: FASE 2 - RASTREO Y SELECCIÓN DE HARDWARE
  // ===========================================================================
  Widget _fase2ListadoDispositivos() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          if (_isScanning) const LinearProgressIndicator(color: lightBlue, backgroundColor: Color(0xFFD0D0D0)),
          const SizedBox(height: 16),
          Expanded(
            child: _scanResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.radar, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(_isScanning ? 'Buscando señales Metrigas...' : 'No se encontró hardware activo', style: const TextStyle(color: Colors.grey)),
                        if (!_isScanning)
                          TextButton.icon(onPressed: _startBleScan, icon: const Icon(Icons.refresh), label: const Text('Volver a buscar'))
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final result = _scanResults[index];
                      final name = result.device.advName.isNotEmpty ? result.device.advName : "Medidor Inteligente";
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Color(0xFFE6F0FF), child: Icon(Icons.router, color: primaryBlue)),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('ID: ${result.device.remoteId} | Señal: ${result.rssi} dBm'),
                          trailing: _isConnecting
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.link, color: primaryBlue),
                          onTap: _isConnecting ? null : () => _connectToDevice(result.device),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // VISTA: FASE 3 - FORMULARIO DE LLEGADA WI-FI (¡PROPIEDAD CORREGIDA!)
  // ===========================================================================
  Widget _fase3FormularioWiFi() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _wifiFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aprovisionamiento de Red', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryBlue)),
            const SizedBox(height: 6),
            const Text('Ingresa la red del hogar para que el hardware se conecte de forma independiente.', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _ssidController,
              decoration: const InputDecoration(labelText: 'Nombre de red (SSID)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.wifi), fillColor: Colors.white, filled: true),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'El SSID es obligatorio' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock), fillColor: Colors.white, filled: true),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'La contraseña es obligatoria' : null,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: _isSendingWifi ? null : () {
                  if (_wifiFormKey.currentState!.validate()) {
                    _enviarCredencialesWifi();
                  }
                },
                child: _isSendingWifi 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Transmitir Parámetros', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // VISTA: FASE 4 - METADATOS TÉCNICOS DEL TANQUE (¡PROPIEDAD CORREGIDA!)
  // ===========================================================================
  Widget _fase4MetadatosTanque(String? userEmail) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _tankFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dimensiones Comerciales', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryBlue)),
            const SizedBox(height: 6),
            const Text('Asigna valores precisos para realizar cálculos volumétricos perfectos.', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _aliasController,
              decoration: const InputDecoration(labelText: 'Nombre identificador (ej: Tanque Principal)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.label), fillColor: Colors.white, filled: true),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Asigna un nombre de medidor' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _capacityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Capacidad nominal (Litros)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.equalizer), fillColor: Colors.white, filled: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Especifica el litraje';
                if (int.tryParse(v.trim()) == null) return 'Ingresa un número entero válido';
                return null;
              },
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: () {
                  if (_tankFormKey.currentState!.validate()) {
                    _finalizarConfiguracionMedidor(userEmail);
                  }
                },
                child: const Text('Completar Enlace con Éxito', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }
}