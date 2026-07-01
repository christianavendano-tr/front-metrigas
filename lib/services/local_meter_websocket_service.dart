// lib/services/local_meter_websocket_service.dart
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

class LocalMeterWebSocketService {
  static const int _port = 8765;

  // Parámetros matemáticos del LCG idénticos a tu lógica original del firmware
  static const int _m = 256;
  static const int _a = 1103515245;
  static const int _c = 12345;
  static const int _initialSeed = 42; 

  /// Transforma un set de bytes con un algoritmo XOR con flujo simétrico LCG
  static Uint8List _lcgTransform(Uint8List source) {
    final Uint8List result = Uint8List(source.length);
    int currentSeed = _initialSeed;

    for (int i = 0; i < source.length; i++) {
      currentSeed = (_a * currentSeed + _c) % _m;
      result[i] = source[i] ^ (currentSeed & 0xFF);
    }
    return result;
  }

/// Envía un mapa JSON cifrado a un host específico por medio de WebSockets nativos (dart:io)
  /// y retorna la respuesta decodificada del hardware.
  static Future<Map<String, dynamic>> sendCommand({
    required String hostname,
    required Map<String, dynamic> commandJson,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    WebSocket? webSocket;
    try {
      // 1. Limpieza estricta del Hostname para evitar esquemas duplicados
      // Quitamos cualquier rastro previo de ws://, wss:// o http://
      String cleanHost = hostname
          .replaceAll('ws://', '')
          .replaceAll('wss://', '')
          .replaceAll('http://', '')
          .replaceAll('https://', '')
          .trim();

      // HARDCODEO DE PRUEBA EN HOTSPOT:
      // Si quieres forzar que SIEMPRE use la IP del ESP32 en el hotspot, descomenta la línea de abajo:
      // cleanHost = "10.202.246.147";

      // 2. Construcción correcta de la URL del WebSocket
      final String wsUrl = "ws://$cleanHost:$_port";
      print("🔌 Conectando vía WebSocket a: $wsUrl");

      // Conexión nativa con un timeout preventivo
      webSocket = await WebSocket.connect(wsUrl).timeout(timeout);

      // 3. Serialización y cifrado LCG del comando JSON
      final String rawString = jsonEncode(commandJson);
      final Uint8List plainBytes = utf8.encode(rawString);
      final Uint8List encryptedBytes = _lcgTransform(plainBytes);

      // 4. Inyección del payload binario directamente en la trama Frame de WebSocket
      webSocket.add(encryptedBytes);

      // 5. Captura y espera del primer stream de respuesta de la ESP32
      final responseEvent = await webSocket.first.timeout(timeout);

      // 6. Normalización segura del evento recibido a buffer de bytes
      Uint8List responseBuffer;
      if (responseEvent is List<int>) {
        responseBuffer = Uint8List.fromList(responseEvent);
      } else if (responseEvent is String) {
        responseBuffer = Uint8List.fromList(utf8.encode(responseEvent));
      } else {
        throw Exception("Formato de trama de WebSocket desconocido.");
      }

      // 7. Descifrado LCG inverso y decodificación UTF-8
      final Uint8List decryptedBytes = _lcgTransform(responseBuffer);
      final String jsonResponseStr = utf8.decode(decryptedBytes);

      return jsonDecode(jsonResponseStr) as Map<String, dynamic>;
    } catch (e) {
      throw Exception("Error de comunicación WebSocket local con $hostname: $e");
    } finally {
      // Aseguramos el cierre del socket para liberar los descriptores del sistema operativo
      await webSocket?.close();
    }
  }
}