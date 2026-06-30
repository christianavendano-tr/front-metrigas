// lib/services/meter_telemetry_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:front_metrigas/services/session_service.dart';

class TelemetryReading {
  final double percentAvailable;
  final TelemetrySource source;
  final DateTime? timestamp;

  const TelemetryReading({
    required this.percentAvailable,
    required this.source,
    this.timestamp,
  });
}

enum TelemetrySource { localMdns, cloudFallback }

class MeterTelemetryService {
  static const Duration _localTimeout = Duration(seconds: 2);
  static const Duration _cloudTimeout = Duration(seconds: 6);
  static const String _cloudBaseUrl = 'http://localhost:3000';

  Future<TelemetryReading?> fetchLatestReading(String hardwareId) async {
    // 1. Intento mDNS local (falla silenciosamente si el usuario no está en casa)
    try {
      final local = await _fetchFromLocalMdns(hardwareId);
      if (local != null) return local;
    } catch (e) {
      debugPrint('📡 [Telemetry] mDNS falló (esperado fuera de casa): $e');
    }

    // 2. Fallback: último log en la nube
    try {
      return await _fetchLastLogFromCloud(hardwareId);
    } catch (e) {
      debugPrint('❌ [Telemetry] Fallback cloud también falló: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // mDNS local
  // ─────────────────────────────────────────────────────────────────────────
  Future<TelemetryReading?> _fetchFromLocalMdns(String hardwareId) async {
    final url = Uri.parse('http://metrigas-$hardwareId.local/api/status');
    final response = await http.get(url).timeout(_localTimeout);

    if (response.statusCode != 200) {
      throw Exception('mDNS respondió ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final percent = _extractPercentage(data);
    if (percent == null) throw const FormatException('mDNS sin porcentaje válido');

    return TelemetryReading(
      percentAvailable: percent,
      source: TelemetrySource.localMdns,
      timestamp: DateTime.now(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Fallback cloud: GET /logs?meterId=:id&page=1&limit=1
  // Requiere token de sesión igual que el resto de endpoints protegidos.
  // ─────────────────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────
  // Fallback cloud CORREGIDO: GET /logs?meterId=:id&page=1&limit=1
  // ─────────────────────────────────────────────────────────────────────────
  Future<TelemetryReading?> _fetchLastLogFromCloud(String hardwareId) async {
    // CORRECCIÓN: Agregamos el 'await' para obtener el String real del token
    final token = "750f9994-8d29-4353-8379-8e4e3bd95237"; 
    
    final url = Uri.parse(
      '$_cloudBaseUrl/logs?meterId=$hardwareId&page=1&limit=1',
    );

    debugPrint('🔍 [Telemetry] GET $url');

    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        // Si el token es válido, se inyecta correctamente en los Headers protegidos
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    ).timeout(_cloudTimeout);

    debugPrint('🔍 [Telemetry] Status: ${response.statusCode}');
    debugPrint('🔍 [Telemetry] Body:   ${response.body}');

    if (response.statusCode != 200) {
      throw Exception('GET /logs respondió ${response.statusCode}');
    }

    // El resto del código que ya tenías está perfecto...
    final decoded = jsonDecode(response.body);
    final entry = _firstEntryFrom(decoded);

    if (entry == null) {
      debugPrint('⚠️ [Telemetry] /logs no devolvió registros para $hardwareId');
      return null;
    }

    final percent = _extractPercentage(entry);
    if (percent == null) {
      debugPrint('⚠️ [Telemetry] Entrada sin currentPercentage: $entry');
      return null;
    }

    final rawDate = entry['meditionDate'] ?? entry['createdAt'] ?? entry['timestamp'];
    final timestamp = rawDate is String ? DateTime.tryParse(rawDate) : null;

    debugPrint('✅ [Telemetry] Lectura cloud: $percent% @ $timestamp');

    return TelemetryReading(
      percentAvailable: percent,
      source: TelemetrySource.cloudFallback,
      timestamp: timestamp,
    );
  }
  // ─────────────────────────────────────────────────────────────────────────
  // Helpers de parsing — tolerantes a distintas estructuras de respuesta
  // ─────────────────────────────────────────────────────────────────────────

  /// Extrae el primer objeto de log de cualquier estructura que devuelva NestJS:
  ///   [ {...} ]                          → lista directa
  ///   { data: [ {...} ] }                → paginación plana
  ///   { data: { items: [ {...} ] } }     → paginación anidada
  ///   { data: { data: [ {...} ] } }      → variante de paginación
  Map<String, dynamic>? _firstEntryFrom(dynamic decoded) {
    if (decoded is List && decoded.isNotEmpty) {
      return decoded.first as Map<String, dynamic>?;
    }

    if (decoded is! Map<String, dynamic>) return null;

    // CAPTURA: Si el backend responde con el formato estadístico de consultMeters
    if (decoded['ok'] == true && decoded['data'] is Map) {
      final dataObj = decoded['data'] as Map<String, dynamic>;
      
      // Si el backend calculó un porcentaje promedio global para el medidor, lo empaquetamos al vuelo
      if (dataObj.containsKey('porcentaje_promedio') && dataObj['porcentaje_promedio'] != 0) {
        return {
          'currentPercentage': dataObj['porcentaje_promedio'],
          'meditionDate': dataObj['fecha_ultimo_log'],
        };
      }
    }

    final data = decoded['data'];
    if (data is List && data.isNotEmpty) {
      return data.first as Map<String, dynamic>?;
    }

    if (data is Map<String, dynamic>) {
      for (final key in ['items', 'data', 'logs', 'results']) {
        final inner = data[key];
        if (inner is List && inner.isNotEmpty) {
          return inner.first as Map<String, dynamic>?;
        }
      }
    }

    return null;
  }

  /// Extrae el porcentaje del sensor probando los nombres de campo más comunes.
  double? _extractPercentage(Map<String, dynamic> json) {
    for (final key in [
      'currentPercentage',
      'percent',
      'percentage',
      'level',
      'percentAvailable',
    ]) {
      final raw = json[key];
      if (raw == null) continue;
      if (raw is num) return raw.toDouble();
      final parsed = double.tryParse(raw.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }
}