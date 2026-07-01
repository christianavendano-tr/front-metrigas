import 'package:flutter_test/flutter_test.dart';
import 'package:front_metrigas/services/meter_manager.dart';
import 'package:front_metrigas/services/meter_telemetry_service.dart';
import 'package:front_metrigas/services/socket_services.dart';

void main() {
  group('SocketLcgService.parsePercentageFromResponse', () {
    test('devuelve el porcentaje cuando viene en status', () {
      final result = SocketLcgService.parsePercentageFromResponse({
        'status': [55],
      });

      expect(result, 55.0);
    });

    test('devuelve el porcentaje incluso cuando hay un aviso adicional', () {
      final result = SocketLcgService.parsePercentageFromResponse({
        'status': [55, 'internet_lost'],
      });

      expect(result, 55.0);
    });

    test('devuelve null cuando la respuesta no tiene un porcentaje válido', () {
      final result = SocketLcgService.parsePercentageFromResponse({
        'status': ['internet_lost'],
      });

      expect(result, isNull);
    });
  });

  group('MeterManager.parseCurrentPercentageFromLogResponse', () {
    test('extrae currentPercentage del bloque data', () {
      final result = MeterManager.parseCurrentPercentageFromLogResponse({
        'ok': true,
        'data': {
          'currentPercentage': 99,
        },
      });

      expect(result, 99.0);
    });

    test('devuelve null si no existe currentPercentage', () {
      final result = MeterManager.parseCurrentPercentageFromLogResponse({
        'ok': true,
        'data': {'id': '123'},
      });

      expect(result, isNull);
    });
  });

  group('MeterTelemetryService.extractCurrentPercentageFromDetailResponse', () {
    test('extrae currentPercentage del endpoint /logs/:meterId', () {
      final result =
          MeterTelemetryService.extractCurrentPercentageFromDetailResponse({
        'ok': true,
        'data': {
          'currentPercentage': 99,
          'meditionDate': '2026-07-01',
        },
      });

      expect(result, 99.0);
    });

    test('devuelve null si el detalle no trae currentPercentage', () {
      final result =
          MeterTelemetryService.extractCurrentPercentageFromDetailResponse({
        'ok': true,
        'data': {'id': '123'},
      });

      expect(result, isNull);
    });
  });

  group('SocketLcgService.isResetConfirmed', () {
    test('acepta respuestas con ok y factory_reset_initiated', () {
      final result = SocketLcgService.isResetConfirmed({
        'status': ['ok', 'factory_reset_initiated'],
      });

      expect(result, isTrue);
    });

    test('rechaza respuestas sin confirmación de reset', () {
      final result = SocketLcgService.isResetConfirmed({
        'status': ['error'],
      });

      expect(result, isFalse);
    });
  });
}
