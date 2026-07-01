// lib/services/meter_manager.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'session_service.dart';

class MeterManager {
  static const String _localMetersKey = 'local_meters_cache';
  static final String _baseUrl = SessionService.getURL();

  /// Generador nativo de UUID v4 para cumplir con las restricciones estrictas de Postgres
  static String _generarUUIDv4() {
    final random = Random();
    const hexDigits = '0123456789abcdef';

    String randomHex(int length) {
      return List.generate(length, (index) => hexDigits[random.nextInt(16)])
          .join();
    }

    final s1 = randomHex(8);
    final s2 = randomHex(4);
    final s3 = '4${randomHex(3)}';
    final s4 = ['8', '9', 'a', 'b'][random.nextInt(4)] + randomHex(3);
    final s5 = randomHex(12);

    return '$s1-$s2-$s3-$s4-$s5';
  }

  /// 1. CARGA DINÁMICA: Determina si busca en la Nube o en el LocalStorage
  /// OPTIMIZADO: Incluye prints de diagnóstico para ver qué responde NestJS exactamente.
  static Future<List<Map<String, dynamic>>> obtenerMedidores() async {
    final token = SessionService.getToken();

    if (token != null && token.isNotEmpty) {
      try {
        final url = Uri.parse('$_baseUrl/meters');
        final response = await http.get(url, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });

        // =====================================================================
        // DIAGNÓSTICO DE RESPUESTA EN CONSOLA
        // =====================================================================
        debugPrint(
            '🔍 [MeterManager] HTTP GET /meters - Status: ${response.statusCode}');
        debugPrint('🔍 [MeterManager] JSON del Servidor: ${response.body}');
        // =====================================================================

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          // Caso A: El backend devuelve directamente un Array de medidores: [ {...}, {...} ]
          if (data is List) {
            return List<Map<String, dynamic>>.from(data);
          }

          // Caso B: El backend devuelve un objeto que contiene los medidores dentro: { "meters": [...] }
          if (data is Map && data['meters'] != null) {
            return List<Map<String, dynamic>>.from(data['meters']);
          }

          // Caso C: NestJS devuelve un objeto de paginación o data genérica: { "data": [...] }
          if (data is Map && data['data'] != null && data['data'] is List) {
            return List<Map<String, dynamic>>.from(data['data']);
          }

          // Caso D: Si devolvió un objeto vacío o mapeo extraño
          if (data is Map) {
            debugPrint(
                '⚠️ [MeterManager] Estructura Map detectada pero no reconocida automáticamente.');
            // Si el objeto único representa a un solo medidor devuelto por error, lo envolvemos en lista
            if (data.containsKey('id') && data.containsKey('metername')) {
              return [Map<String, dynamic>.from(data)];
            }
          }
        }
      } catch (e) {
        debugPrint('❌ Error cargando medidores desde la nube: $e');
      }
      return []; // Si falla o la estructura no coincide, retorna vacío para proteger la UI
    }

    // FALLBACK MODO INVITADO / LOCAL STORAGE
    final prefs = await SharedPreferences.getInstance();
    final String? metersRaw = prefs.getString(_localMetersKey);
    if (metersRaw == null) return [];

    final List<dynamic> decoded = jsonDecode(metersRaw);
    return decoded.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  /// 2. GUARDADO LOCAL (Modo Invitado)
  static Future<void> guardarMedidorLocal(
      Map<String, dynamic> nuevoMedidor) async {
    final prefs = await SharedPreferences.getInstance();
    final medidoresActuales = await obtenerMedidores();

    medidoresActuales.add(nuevoMedidor);
    await prefs.setString(_localMetersKey, jsonEncode(medidoresActuales));
  }

  /// 3. MIGRACIÓN HÍBRIDA MASIVA (Transfiere local -> Postgres)
  static Future<void> migrarMedidoresLocalesAlServidor(
      String? realUserId) async {
    final token = SessionService.getToken();
    if (token == null || token.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final String? metersRaw = prefs.getString(_localMetersKey);

    if (metersRaw == null || metersRaw == '[]') return;

    try {
      final List<dynamic> locales = jsonDecode(metersRaw);
      final url = Uri.parse('$_baseUrl/meters/migrate');

      final payload = locales.map((m) {
        String currentId = m['id']?.toString() ?? '';

        if (currentId.length != 36 || !currentId.contains('-')) {
          currentId = _generarUUIDv4();
        }

        final rawCapacity = m['capacity']?.toString() ?? '20';
        final parsedDouble = double.tryParse(rawCapacity) ?? 20.0;
        final int capacityInt = parsedDouble.toInt();
        final String capacityString = capacityInt.toString();

        return {
          "id": currentId,
          "metername": m['metername'] ?? "Medidor Desconocido",
          "capacity": capacityString,
          "ownerId": realUserId ?? "00000000-0000-0000-0000-000000000000"
        };
      }).toList();

      debugPrint(
          '📤 [MeterManager] Enviando payload de migración: ${jsonEncode(payload)}');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('🚀 ¡Migración masiva completada con éxito en Postgres!');
        await prefs.remove(_localMetersKey);
      } else {
        debugPrint(
            'Falla en respuesta del endpoint de migración: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error crítico durante el mapeo o envío de la migración: $e');
    }
  }

  /// 4. BAJA DE HARDWARE — combinado (se mantiene por compatibilidad,
  /// pero NO distingue premium. Para la pantalla de dashboard usar
  /// `eliminarMedidorRemoto` + `eliminarMedidorSoloLocal` por separado.
  static Future<bool> eliminarMedidor(String id) async {
    final token = SessionService.getToken();

    if (token != null && token.isNotEmpty) {
      try {
        final url = Uri.parse('$_baseUrl/meters/$id');
        final response = await http.delete(url, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });
        return response.statusCode == 200 || response.statusCode == 204;
      } catch (e) {
        return false;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final medidores = await obtenerMedidores();
    medidores.removeWhere((m) => m['id']?.toString() == id);
    await prefs.setString(_localMetersKey, jsonEncode(medidores));
    return true;
  }

  /// 4a. BAJA SOLO EN EL SERVIDOR (Postgres)
  /// Úsalo cuando el usuario es premium: borra el registro en la nube
  /// (y por cascada, sus logs asociados en el backend).
  static Future<bool> eliminarMedidorRemoto(String id) async {
    final token = SessionService.getToken();

    if (token == null || token.isEmpty) {
      debugPrint(
          '⚠️ [MeterManager] No hay token, no se puede eliminar del servidor.');
      return false;
    }

    try {
      final url = Uri.parse('$_baseUrl/meters/$id');
      final response = await http.delete(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });

      debugPrint(
          '🔍 [MeterManager] HTTP DELETE /meters/$id - Status: ${response.statusCode}');

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint('❌ Error eliminando medidor del servidor: $e');
      return false;
    }
  }

  static double? parseCurrentPercentageFromLogResponse(
      Map<String, dynamic>? response) {
    if (response == null) {
      return null;
    }

    final dynamic data = response['data'];
    if (data is! Map) {
      return null;
    }

    final dynamic percentage = data['currentPercentage'];
    if (percentage is num) {
      return percentage.toDouble();
    }

    if (percentage is String) {
      return double.tryParse(percentage);
    }

    return null;
  }

  static Future<double?> obtenerPorcentajeDesdeLogs(String meterId) async {
    final token = SessionService.getToken();

    if (token == null || token.isEmpty) {
      return null;
    }

    try {
      final url = Uri.parse('$_baseUrl/logs/$meterId');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      return parseCurrentPercentageFromLogResponse(decoded);
    } catch (e) {
      debugPrint('❌ Error consultando logs para $meterId: $e');
      return null;
    }
  }

  /// 4b. BAJA SOLO EN LOCAL STORAGE
  /// Siempre limpia el caché local, sin importar si hay token activo.
  /// Úsalo para usuarios invitados (sin token) o como segundo paso
  /// después de eliminar exitosamente del servidor (usuario premium).
  static Future<bool> eliminarMedidorSoloLocal(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? metersRaw = prefs.getString(_localMetersKey);

      if (metersRaw == null) return true; // no había nada que borrar

      final List<dynamic> decoded = jsonDecode(metersRaw);
      final medidores =
          decoded.map((item) => Map<String, dynamic>.from(item)).toList();

      medidores.removeWhere((m) => m['id']?.toString() == id);
      await prefs.setString(_localMetersKey, jsonEncode(medidores));
      return true;
    } catch (e) {
      debugPrint('❌ Error eliminando medidor del local storage: $e');
      return false;
    }
  }
}
