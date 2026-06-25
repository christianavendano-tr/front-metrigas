import 'dart:convert';
import 'package:http/http.dart' as http;

/// Resultado de una consulta de telemetría, indicando además el origen
/// del dato (mDNS local en tiempo real, o fallback a la última lectura
/// guardada en la nube) para que la UI pueda, si quiere, distinguir
/// entre "dato en vivo" y "última lectura conocida".
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


/// Servicio de red encargado de obtener la telemetría instantánea de un
/// medidor. Implementa la estrategia de dos pasos que pide el ticket:
///
/// 1. Intenta resolver el medidor en la red local vía mDNS
///    (http://metrigas-[hardwareId].local/api/status). Esto solo
///    funciona cuando el celular está en la misma red Wi-Fi que el
///    dispositivo (típicamente, el usuario está en su casa).
/// 2. Si esa petición falla (timeout, DNS no resuelve, error de red),
///    hace fallback a `GET /metrics?meterId=...&page=1&limit=1`, el
///    mismo endpoint paginado de historial (`GetMetricDto`), pidiendo
///    un solo elemento para usarlo como "última lectura conocida". No
///    existe todavía un endpoint dedicado a "solo el último log"; si
///    el backend llega a exponer uno, este método es el único lugar
///    que habría que actualizar.
///
/// Nunca lanza una excepción hacia quien lo llama si ambas fuentes
/// fallan; en ese caso regresa `null` para que la pantalla pueda
/// mostrar un estado de "sin datos" sin romperse.
class MeterTelemetryService {
  /// Timeout corto para la consulta local: si el medidor está en la
  /// misma red, debe responder casi de inmediato. Un timeout largo
  /// aquí solo haría que el usuario espere innecesariamente cuando
  /// está fuera de casa y la resolución mDNS simplemente no aplica.
  static const Duration _localTimeout = Duration(seconds: 2);
  static const Duration _cloudTimeout = Duration(seconds: 6);

  /// Host base del backend en la nube. Ajustar según el ambiente
  /// (dev/staging/prod); de momento apunta al backend local de
  /// desarrollo, igual que el resto de los servicios de auth.
  static const String _cloudBaseUrl = 'http://localhost:3000';

  /// Intenta obtener telemetría en vivo por mDNS; si falla, regresa la
  /// última lectura conocida desde la nube usando `GET /metrics`
  /// (page=1, limit=1) — ver [_fetchLastLogFromCloud]. Si ninguna de
  /// las dos fuentes responde, regresa `null`.
  Future<TelemetryReading?> fetchLatestReading(String hardwareId) async {
    try {
      final local = await _fetchFromLocalMdns(hardwareId);
      if (local != null) return local;
    } catch (_) {
      // Esperado cuando el usuario no está en la misma red que el
      // medidor: no es un error real, simplemente se intenta el
      // fallback a continuación.
    }

    try {
      return await _fetchLastLogFromCloud(hardwareId);
    } catch (_) {
      // Ninguna fuente disponible. El llamador decide cómo mostrar
      // este caso (por ejemplo, conservando la última lectura que ya
      // tenía en memoria, o un estado vacío neutro).
      return null;
    }
  }

  /// GET http://metrigas-[hardwareId].local/api/status
  Future<TelemetryReading?> _fetchFromLocalMdns(String hardwareId) async {
    final url = Uri.parse('http://metrigas-$hardwareId.local/api/status');

    final response = await http.get(url).timeout(_localTimeout);

    if (response.statusCode != 200) {
      throw Exception('mDNS local respondió ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final percent = _extractPercentage(data);
    if (percent == null) {
      throw const FormatException('Respuesta mDNS sin porcentaje válido');
    }

    return TelemetryReading(
      percentAvailable: percent,
      source: TelemetrySource.localMdns,
      timestamp: DateTime.now(),
    );
  }

  /// Fallback en la nube: pide la lectura más reciente registrada para
  /// este medidor vía `GET /metrics`, el mismo endpoint paginado que
  /// describe `GetMetricDto` (meterId, page, limit). Como no existe un
  /// endpoint dedicado a "solo el último log", se pide la primera
  /// página con un único elemento (page=1, limit=1) y se toma ese
  /// elemento como la lectura más reciente, asumiendo que el backend
  /// ordena por `meditionDate` descendente (mismo orden que usa
  /// internamente `getLastLogByMeter` en LogsService).
  Future<TelemetryReading?> _fetchLastLogFromCloud(String hardwareId) async {
    final url = Uri.parse(
      '$_cloudBaseUrl/metrics?meterId=$hardwareId&page=1&limit=1',
    );

    final response = await http.get(url).timeout(_cloudTimeout);

    if (response.statusCode != 200) {
      throw Exception('GET /metrics respondió ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final entry = _firstEntryFrom(decoded);
    if (entry == null) {
      throw const FormatException('GET /metrics no devolvió registros');
    }

    final percent = _extractPercentage(entry);
    if (percent == null) {
      throw const FormatException('Último log sin currentPercentage válido');
    }

    final rawDate = entry['meditionDate'];
    final timestamp = rawDate is String ? DateTime.tryParse(rawDate) : null;

    return TelemetryReading(
      percentAvailable: percent,
      source: TelemetrySource.cloudFallback,
      timestamp: timestamp,
    );
  }

  /// `GET /metrics` es un endpoint paginado: el primer registro puede
  /// venir como `data` (lista directa), `data.items`, o `data.data`
  /// según cómo se envuelva la paginación en el controller. Se intentan
  /// las formas más probables sin asumir una sola estructura fija.
  Map<String, dynamic>? _firstEntryFrom(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final data = decoded['data'];

    if (data is List && data.isNotEmpty) {
      return data.first as Map<String, dynamic>;
    }
    if (data is Map<String, dynamic>) {
      final items = data['items'] ?? data['data'];
      if (items is List && items.isNotEmpty) {
        return items.first as Map<String, dynamic>;
      }
    }
    return null;
  }

  /// El backend siempre regresa el porcentaje como `currentPercentage`
  /// (ver `CreateLogDto` y la respuesta real de `POST /meters`).
  double? _extractPercentage(Map<String, dynamic> json) {
    final raw = json['currentPercentage'];
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }
}