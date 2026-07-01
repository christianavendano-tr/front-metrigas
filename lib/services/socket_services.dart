import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Servicio para comunicarse por WebSocket con un servidor que espera
/// los mensajes cifrados con un LCG (Linear Congruential Generator),
/// replicando el comportamiento del cliente Python funcional.
class SocketLcgService {
  // ---------------------------------------------------------------------
  // Parámetros del LCG. DEBEN coincidir EXACTAMENTE con el servidor.
  // Tomados del cliente Python que ya funciona:
  //   x = (x * A + B) % BASE
  //   byte_cifrado = byte_plano XOR (x % 256)
  // ---------------------------------------------------------------------
  static const int _initialX = 123456;
  static const int _a = 20011;
  static const int _b = 12345;
  static const int _base = 65536;

  /// Aplica el flujo LCG + XOR sobre [source]. Como el XOR es simétrico,
  /// esta misma función sirve para cifrar y, si algún día el servidor
  /// también cifra su respuesta, para descifrar (siempre que reinicie
  /// el estado igual que aquí, con _initialX en cada mensaje).
  static Uint8List _lcgTransform(Uint8List source) {
    final Uint8List result = Uint8List(source.length);
    int x = _initialX;

    for (int i = 0; i < source.length; i++) {
      x = (x * _a + _b) % _base;
      result[i] = source[i] ^ (x % 256);
    }
    return result;
  }

  /// FUNCIÓN PRINCIPAL: recibe el [commandJson], lo cifra con el LCG,
  /// abre el WebSocket, lo envía, espera la respuesta del servidor
  /// y la retorna ya decodificada como Map.
  ///
  /// [host] puede ser una IP ("192.168.1.105") o hostname.
  /// [port] por defecto 8765, igual que en el cliente Python.
  static Future<Map<String, dynamic>> sendCommand({
    required String host,
    int port = 8765,
    required Map<String, dynamic> commandJson,
    Duration timeout = const Duration(seconds: 7),
  }) async {
    WebSocket? socket;
    try {
      // 1. Limpieza básica del host, igual que en tu ejemplo
      final String targetHost = host.replaceAll(' ', '-').replaceAll('_', '-');

      // 2. Apertura del WebSocket (handshake HTTP incluido)
      final Uri uri = Uri.parse('ws://$targetHost:$port');
      socket = await WebSocket.connect(uri.toString()).timeout(timeout);

      // 3. Serialización y cifrado LCG del comando
      final String rawString = jsonEncode(commandJson);
      final Uint8List plainBytes = Uint8List.fromList(utf8.encode(rawString));
      final Uint8List encryptedBytes = _lcgTransform(plainBytes);

      // 4. Envío del payload cifrado como frame binario
      socket.add(encryptedBytes);

      // 5. Espera de la respuesta (viene en texto/JSON plano, sin cifrar,
      //    igual que en el cliente Python de referencia)
      final dynamic rawResponse = await socket.first.timeout(timeout);

      final String jsonResponseStr;
      if (rawResponse is String) {
        jsonResponseStr = rawResponse;
      } else if (rawResponse is List<int>) {
        jsonResponseStr = utf8.decode(rawResponse);
        // Si en algún momento el servidor SÍ cifra la respuesta, sería:
        // jsonResponseStr = utf8.decode(_lcgTransform(Uint8List.fromList(rawResponse)));
      } else {
        throw Exception(
            'Tipo de respuesta no soportado: ${rawResponse.runtimeType}');
      }

      return jsonDecode(jsonResponseStr) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Error de comunicación con $host:$port -> $e');
    } finally {
      await socket?.close();
    }
  }
}
