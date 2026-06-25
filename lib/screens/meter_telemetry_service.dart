import 'dart:convert';
import 'package:http/http.dart' as http;

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
    try {
      final local = await _fetchFromLocalMdns(hardwareId);
      if (local != null) return local;
    } catch (_) {
      // Esperado cuando el usuario no está en la misma red: se continúa con fallback.
    }

    try {
      return await _fetchLastLogFromCloud(hardwareId);
    } catch (_) {
      return null;
    }
  }

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

  /// Fallback en la nube: usa GET /logs (prefijo real del controller NestJS),
  /// NO /metrics. Pide page=1&limit=1 para obtener solo la lectura más reciente.
  Future<TelemetryReading?> _fetchLastLogFromCloud(String hardwareId) async {
    // CORREGIDO: era /metrics — el @Controller('logs') expone /logs
    final url = Uri.parse(
      '$_cloudBaseUrl/logs?meterId=$hardwareId&page=1&limit=1',
    );

    final response = await http.get(url).timeout(_cloudTimeout);

    if (response.statusCode != 200) {
      throw Exception('GET /logs respondió ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final entry = _firstEntryFrom(decoded);
    if (entry == null) {
      throw const FormatException('GET /logs no devolvió registros');
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

  double? _extractPercentage(Map<String, dynamic> json) {
    final raw = json['currentPercentage'];
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }
}