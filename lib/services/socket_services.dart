import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class SocketLcgService {
  static const int _initialX = 256;
  static const int _a = 1103515245;
  static const int _b = 12345;
  static const int _base = 42; // seed

  static double? parsePercentageFromResponse(Map<String, dynamic>? response) {
    if (response == null) {
      return null;
    }

    final dynamic rawStatus = response['status'];
    if (rawStatus is! List) {
      return null;
    }

    for (final entry in rawStatus) {
      if (entry is num) {
        return entry.toDouble();
      }

      if (entry is String) {
        final parsed = double.tryParse(entry);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
  }

  static bool isResetConfirmed(Map<String, dynamic>? response) {
    if (response == null) {
      return false;
    }

    final dynamic rawStatus = response['status'];
    if (rawStatus is! List) {
      return false;
    }

    return rawStatus.any((entry) {
      if (entry is String) {
        return entry.toLowerCase() == 'ok' ||
            entry.toLowerCase() == 'factory_reset_initiated';
      }
      return false;
    });
  }

  static Uint8List _lcgTransform(Uint8List source) {
    final Uint8List result = Uint8List(source.length);
    int x = _initialX;

    for (int i = 0; i < source.length; i++) {
      x = (x * _a + _b) % _base;
      result[i] = source[i] ^ (x % 256);
    }
    return result;
  }

  static Future<Map<String, dynamic>> sendCommand({
    required String mdnsName,
    int port = 8765,
    required Map<String, dynamic> commandJson,
    Duration timeout = const Duration(seconds: 7),
  }) async {
    WebSocket? socket;
    try {
      // 1. Normalización del nombre mDNS: espacios y "-" -> "_"
      String targetHost =
          mdnsName.trim().replaceAll(' ', '-').replaceAll('_', '-');

      // 2. Aseguramos el sufijo .local requerido por mDNS
      if (!targetHost.endsWith('.local')) {
        targetHost = '$targetHost.local';
      }

      // 3. Apertura del WebSocket (handshake HTTP incluido)
      final Uri uri = Uri.parse('ws://$targetHost:$port');
      socket = await WebSocket.connect(uri.toString()).timeout(timeout);

      // 4. Serialización y cifrado LCG del comando
      final String rawString = jsonEncode(commandJson);
      final Uint8List plainBytes = Uint8List.fromList(utf8.encode(rawString));
      final Uint8List encryptedBytes = _lcgTransform(plainBytes);

      // 5. Envío del payload cifrado como frame binario
      socket.add(encryptedBytes);

      // 6. Espera de la respuesta (viene en texto/JSON plano, sin cifrar,
      //    igual que en el cliente Python de referencia)
      final dynamic rawResponse = await socket.first.timeout(timeout);

      final String jsonResponseStr;
      if (rawResponse is String) {
        jsonResponseStr = rawResponse;
      } else if (rawResponse is List<int>) {
        // jsonResponseStr = utf8.decode(rawResponse);
        // Si en algún momento el servidor SÍ cifra la respuesta, sería:
        jsonResponseStr =
            utf8.decode(_lcgTransform(Uint8List.fromList(rawResponse)));
      } else {
        throw Exception(
            'Tipo de respuesta no soportado: ${rawResponse.runtimeType}');
      }

      return jsonDecode(jsonResponseStr) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Error de comunicación con $mdnsName:$port -> $e');
    } finally {
      await socket?.close();
    }
  }
}
