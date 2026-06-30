import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

class LocalMeterSocketService {
  static const int _port = 8765;

  // Parámetros matemáticos del LCG definidos en tu firmware
  static const int _m = 256;
  static const int _a = 1103515245;
  static const int _c = 12345;
  static const int _initialSeed = 42; // Semilla/Clave compartida base

  /// Transforma un set de bytes aplicando el algoritmo XOR con flujo LCG simétrico
  static Uint8List _lcgTransform(Uint8List source) {
    final Uint8List result = Uint8List(source.length);
    int currentSeed = _initialSeed;

    for (int i = 0; i < source.length; i++) {
      // Replicación exacta del desborde y la aritmética de MicroPython
      currentSeed = (_a * currentSeed + _c) % _m;
      result[i] = source[i] ^ (currentSeed & 0xFF);
    }
    return result;
  }

  /// FUNCIÓN REUTILIZABLE CENTRAL: Envía un mapa JSON cifrado a un Host específico
  /// por TCP y retorna la respuesta decodificada del medidor.
  static Future<Map<String, dynamic>> sendCommand({
    required String hostname,
    required Map<String, dynamic> commandJson,
    Duration timeout = const Duration(seconds: 7),
  }) async {
    Socket? socket;
    try {
      // 1. Limpieza del hostname (remover http:// o .local si se pasa el host crudo)
      final String targetHost = hostname.replaceAll('http://', '');

      // 2. Apertura del Socket TCP Nativo
      socket = await Socket.connect(targetHost, _port, timeout: timeout);

      // 3. Serialización y cifrado LCG de la orden
      final String rawString = jsonEncode(commandJson);
      final Uint8List plainBytes = utf8.encode(rawString);
      final Uint8List encryptedBytes = _lcgTransform(plainBytes);

      // 4. Inyección del Payload al canal binario
      socket.add(encryptedBytes);
      await socket.flush();

      // 5. Captura y espera de la respuesta del ESP32 en el flujo de entrada
      final Uint8List responseBuffer = await socket.first.timeout(timeout);
      
      // 6. Descifrado LCG de la respuesta binaria recibida
      final Uint8List decryptedBytes = _lcgTransform(responseBuffer);
      final String jsonResponseStr = utf8.decode(decryptedBytes);

      return jsonDecode(jsonResponseStr) as Map<String, dynamic>;
    } catch (e) {
      throw Exception("Error de comunicación TCP local con $hostname: $e");
    } finally {
      // Cierre atómico del socket para liberar los descriptores en RAM del celular
      await socket?.close();
    }
  }
}