import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

class LocalMeterSocketService {
  static const int _port = 8765;

  // Math params of the LCG defined in firmware
  static const int _m = 256;
  static const int _a = 1103515245;
  static const int _c = 12345;
  static const int _initialSeed = 42; // seed

  /// Transforms a set of bites with an XOR algorithm with symetric LCG flux
  static Uint8List _lcgTransform(Uint8List source) {
    final Uint8List result = Uint8List(source.length);
    int currentSeed = _initialSeed;

    for (int i = 0; i < source.length; i++) {
      // Replication from the MicroPython
      currentSeed = (_a * currentSeed + _c) % _m;
      result[i] = source[i] ^ (currentSeed & 0xFF);
    }
    return result;
  }

  /// Cyphered JSON map sent to specific host
  /// by TCP y and returning coded meter response.
  static Future<Map<String, dynamic>> sendCommand({
    required String hostname,
    required Map<String, dynamic> commandJson,
    Duration timeout = const Duration(seconds: 7),
  }) async {
    Socket? socket;
    try {
      // 1. Hostname cleanse
      final String targetHost = hostname.replaceAll('http://', '');

      // 2. Socket opens
      socket = await Socket.connect(targetHost, _port, timeout: timeout);

      // 3. Serialization and cyphering of LCG from order
      final String rawString = jsonEncode(commandJson);
      final Uint8List plainBytes = utf8.encode(rawString);
      final Uint8List encryptedBytes = _lcgTransform(plainBytes);

      // 4. Payload injection in binary channel
      socket.add(encryptedBytes);
      await socket.flush();

      // 5. Captures and waits for the ESP32 response on openning flux
      final Uint8List responseBuffer = await socket.first.timeout(timeout);
      
      // 6. decypher LCG from the response
      final Uint8List decryptedBytes = _lcgTransform(responseBuffer);
      final String jsonResponseStr = utf8.decode(decryptedBytes);

      return jsonDecode(jsonResponseStr) as Map<String, dynamic>;
    } catch (e) {
      throw Exception("Error de comunicación TCP local con $hostname: $e");
    } finally {
      // Close socket
      await socket?.close();
    }
  }
}