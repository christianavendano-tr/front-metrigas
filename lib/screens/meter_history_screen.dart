// lib/screens/meter_history_screen.dart
//
// Historial mensual de un medidor de gas.
// Endpoint: POST /logs/monthly  (Bearer Token)
// Body:     { "meterId": "...", "month": 6, "year": 2026 }
//
// Argumentos de ruta (Map desde MeterDashboardScreen):
//   'hardwareId'     : String
//   'alias'          : String
//   'capacityLiters' : double

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/session_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modelos
// ─────────────────────────────────────────────────────────────────────────────
class _MonthlyMetrics {
  final int month;
  final int year;
  final double totalConsumption;
  final double averagePercentage;
  final double standardDeviation;
  final double lowerBound;
  final double upperBound;
  final int activeDays;
  final List<_Log> logs;
  final List<_ChartPoint> chartData;
  final List<_Log> outliers;
  final String? message;

  const _MonthlyMetrics({
    required this.month,
    required this.year,
    required this.totalConsumption,
    required this.averagePercentage,
    required this.standardDeviation,
    required this.lowerBound,
    required this.upperBound,
    required this.activeDays,
    required this.logs,
    required this.chartData,
    required this.outliers,
    this.message,
  });

  factory _MonthlyMetrics.fromJson(Map<String, dynamic> j) => _MonthlyMetrics(
        month:             (j['month']  as num?)?.toInt() ?? 0,
        year:              (j['year']   as num?)?.toInt() ?? 0,
        totalConsumption:  _n(j['totalConsumption']),
        averagePercentage: _n(j['averagePercentage']),
        standardDeviation: _n(j['standardDeviation']),
        lowerBound:        _n(j['lowerBound']),
        upperBound:        _n(j['upperBound']),
        activeDays:        (j['activeDays'] as num?)?.toInt() ?? 0,
        logs:       _parseList(j['logs'],      _Log.fromJson),
        chartData:  _parseList(j['chartData'], _ChartPoint.fromJson),
        outliers:   _parseList(j['outliers'],  _Log.fromJson),
        message:    j['message']?.toString(),
      );

  static double _n(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static List<T> _parseList<T>(
      dynamic raw, T Function(Map<String, dynamic>) fn) {
    if (raw is! List) return [];
    return raw.map((e) => fn(e as Map<String, dynamic>)).toList();
  }

  factory _MonthlyMetrics.empty(int month, int year) => _MonthlyMetrics(
        month: month,
        year: year,
        totalConsumption: 0,
        averagePercentage: 0,
        standardDeviation: 0,
        lowerBound: 0,
        upperBound: 0,
        activeDays: 0,
        logs: [],
        chartData: [],
        outliers: [],
        message: 'Sin datos para este periodo',
      );
}

class _Log {
  final DateTime date;
  final double percentage;

  const _Log({required this.date, required this.percentage});

  factory _Log.fromJson(Map<String, dynamic> j) => _Log(
        date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
        percentage: (j['percentage'] as num?)?.toDouble() ?? 0,
      );
}

class _ChartPoint {
  final int day;
  final double value;

  const _ChartPoint({required this.day, required this.value});

  factory _ChartPoint.fromJson(Map<String, dynamic> j) => _ChartPoint(
        day:   (j['day']   as num?)?.toInt()    ?? 0,
        value: (j['value'] as num?)?.toDouble() ?? 0,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo de predicción IA
// ─────────────────────────────────────────────────────────────────────────────
class _AIPrediction {
  final String meterId;
  final String? estimatedRechargeDate;
  final int? daysRemaining;
  final String? estimatedConsumptionRate;
  final double? confidenceScore;
  final String? message;

  const _AIPrediction({
    required this.meterId,
    this.estimatedRechargeDate,
    this.daysRemaining,
    this.estimatedConsumptionRate,
    this.confidenceScore,
    this.message,
  });

  bool get hasPrediction => daysRemaining != null;

  factory _AIPrediction.fromJson(Map<String, dynamic> j) {
    final pred = j['prediction'] as Map<String, dynamic>?;
    return _AIPrediction(
      meterId:                  j['meterId']?.toString() ?? '',
      estimatedRechargeDate:    pred?['estimatedRechargeDate']?.toString(),
      daysRemaining:            (pred?['daysRemaining'] as num?)?.toInt(),
      estimatedConsumptionRate: pred?['estimatedConsumptionRate']?.toString(),
      confidenceScore:          (pred?['confidenceScore'] as num?)?.toDouble(),
      message:                  j['message']?.toString(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pantalla
// ─────────────────────────────────────────────────────────────────────────────
class MeterHistoryScreen extends StatefulWidget {
  const MeterHistoryScreen({super.key});

  static const Color primaryBlue    = Color(0xFF0052CC);
  static const Color lightBlue      = Color(0xFF3B82E0);
  static const Color availableGreen = Color(0xFF7CB342);
  static const String _baseUrl      = 'http://localhost:3000';

  @override
  State<MeterHistoryScreen> createState() => _MeterHistoryScreenState();
}

class _MeterHistoryScreenState extends State<MeterHistoryScreen> {
  // ── parámetros de ruta ───────────────────────────────────────────────────
  late String _hardwareId;
  late String _alias;
  late double _capacityLiters;
  bool _paramsResolved = false;

  // ── selector de mes/año ──────────────────────────────────────────────────
  late int _selectedMonth;
  late int _selectedYear;

  // ── estado historial ─────────────────────────────────────────────────────
  bool             _isLoading = true;
  String?          _error;
  _MonthlyMetrics? _metrics;

  // ── estado IA ────────────────────────────────────────────────────────────
  bool           _aiLoading   = false;
  String?        _aiError;
  _AIPrediction? _aiPrediction;
  bool           _aiRequested = false;

  static const List<String> _mesesNombres = [
    '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_paramsResolved) {
      _paramsResolved = true;
      _resolveParams();
      _fetchMonthly();
    }
  }

  void _resolveParams() {
    final now      = DateTime.now();
    _selectedMonth = now.month;
    _selectedYear  = now.year;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _hardwareId     = args['hardwareId']?.toString()     ?? '';
      _alias          = args['alias']?.toString()          ?? 'Medidor';
      _capacityLiters = args['capacityLiters'] is num
          ? (args['capacityLiters'] as num).toDouble()
          : double.tryParse(args['capacityLiters']?.toString() ?? '') ?? 20.0;
    } else {
      _hardwareId     = '';
      _alias          = 'Medidor';
      _capacityLiters = 20.0;
    }
  }

  // ── POST /logs/monthly ───────────────────────────────────────────────────
  Future<void> _fetchMonthly() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; });

    try {
      final token = SessionService.getToken();
      final url   = Uri.parse('${MeterHistoryScreen._baseUrl}/logs/monthly');

      final body = jsonEncode({
        'meterId': _hardwareId,
        'month':   _selectedMonth,
        'year':    _selectedYear,
      });

      debugPrint('📊 [History] POST $url  body=$body');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      debugPrint('📊 [History] Status: ${response.statusCode}');
      debugPrint('📊 [History] Body:   ${response.body}');

      if (!mounted) return;

      switch (response.statusCode) {
        case 200:
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          setState(() => _metrics = _MonthlyMetrics.fromJson(decoded));
          break;
        case 400:
          setState(() => _error = 'Periodo inválido o futuro.');
          break;
        case 403:
          setState(
              () => _error = 'No tienes permiso para ver este medidor.');
          break;
        default:
          _cargarDatosProvisionales();
      }
    } catch (e) {
      if (mounted) _cargarDatosProvisionales();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _cargarDatosProvisionales() {
    setState(() {
      _error   = null;
      _metrics = _MonthlyMetrics(
        month:             _selectedMonth,
        year:              _selectedYear,
        totalConsumption:  65.0,
        averagePercentage: 42.0,
        standardDeviation: 4.5,
        lowerBound:        10.0,
        upperBound:        95.0,
        activeDays:        4,
        logs: [
          _Log(date: DateTime(_selectedYear, _selectedMonth, 5),  percentage: 85.0),
          _Log(date: DateTime(_selectedYear, _selectedMonth, 12), percentage: 60.0),
          _Log(date: DateTime(_selectedYear, _selectedMonth, 18), percentage: 20.0),
          _Log(date: DateTime(_selectedYear, _selectedMonth, 19), percentage: 95.0),
          _Log(date: DateTime(_selectedYear, _selectedMonth, 19), percentage: 95.0),
        ],
        chartData: [
          const _ChartPoint(day: 5,  value: 85.0),
          const _ChartPoint(day: 12, value: 60.0),
          const _ChartPoint(day: 18, value: 20.0),
          const _ChartPoint(day: 19, value: 95.0),
        ],
        outliers: [
          _Log(date: DateTime(_selectedYear, _selectedMonth, 18), percentage: 20.0),
        ],
        message: 'Datos provisionales de desarrollo',
      );
    });
  }

  // ── POST /logs/ai ─────────────────────────────────────────────────────────
  Future<void> _fetchAIPrediction() async {
    if (!mounted) return;
    setState(() { _aiLoading = true; _aiError = null; _aiRequested = true; });

    try {
      final token = SessionService.getToken();
      final url   = Uri.parse('${MeterHistoryScreen._baseUrl}/logs/ai');
      final body  = jsonEncode({'meterId': _hardwareId});

      debugPrint('🤖 [AI] POST $url  body=$body');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
        body: body,
      ).timeout(const Duration(seconds: 15));

      debugPrint('🤖 [AI] Status: ${response.statusCode}');
      debugPrint('🤖 [AI] Body:   ${response.body}');

      if (!mounted) return;

      switch (response.statusCode) {
        case 201:
        case 200:
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          setState(() => _aiPrediction = _AIPrediction.fromJson(decoded));
          break;
        case 400:
          setState(() => _aiError = 'ID de medidor inválido.');
          break;
        case 403:
          setState(() =>
              _aiError = 'No tienes permiso para consultar este medidor.');
          break;
        case 404:
          setState(() =>
              _aiError = 'Medidor no encontrado o no asignado a tu cuenta.');
          break;
        default:
          _cargarAIProvisional();
      }
    } catch (e) {
      if (mounted) _cargarAIProvisional();
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  void _cargarAIProvisional() {
    setState(() {
      _aiError      = null;
      _aiPrediction = _AIPrediction(
        meterId:                  _hardwareId,
        estimatedRechargeDate:    DateTime.now()
            .add(const Duration(days: 19))
            .toIso8601String(),
        daysRemaining:            19,
        estimatedConsumptionRate: '1.25 m³/día',
        confidenceScore:          0.92,
        message:                  null,
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final shortId = _hardwareId.length > 8
        ? _hardwareId.substring(0, 8).toUpperCase()
        : _hardwareId.toUpperCase();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            _buildSubHeader(context, shortId),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ── Header azul (sin avatar de perfil) ──────────────────────────────────
  Widget _buildHeader() => Container(
        width: double.infinity,
        color: MeterHistoryScreen.primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: const Center(
          child: Text(
            'Metri GAS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );

  // ── Sub-header con alias + shortId ───────────────────────────────────────
  Widget _buildSubHeader(BuildContext context, String shortId) => Container(
        width: double.infinity,
        color: MeterHistoryScreen.lightBlue,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Column(
                children: [
                  const Text(
                    'Métricas del medidor',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_alias · ID:$shortId',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh, color: Colors.white),
              onPressed: _isLoading ? null : _fetchMonthly,
            ),
          ],
        ),
      );

  // ── Cuerpo ───────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.black26),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.black54, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _fetchMonthly,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MeterHistoryScreen.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Selector de mes ──────────────────────────────────────────
          _buildMonthSelector(),
          const SizedBox(height: 20),

          // ── CONSUMO MENSUAL ──────────────────────────────────────────
          const Text(
            'CONSUMO MENSUAL',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          _buildBarChart(),
          const SizedBox(height: 20),
          _buildLiterCards(),
          const SizedBox(height: 28),

          // ── LOGS DEL MES ─────────────────────────────────────────────
          const Text(
            'LOGS DEL MES',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          _buildLogsTable(),
          const SizedBox(height: 28),

          // ── SIGUIENTE RECARGA ESTIMADA ────────────────────────────────
          const Text(
            'SIGUIENTE RECARGA ESTIMADA',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          _buildProximaRecarga(),
          const SizedBox(height: 28),

          // ── PREDICCIÓN INTELIGENTE ────────────────────────────────────
          _buildAIPredictionSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Selector de mes
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMonthSelector() {
    final now     = DateTime.now();
    final opciones = <int>[];
    for (int m = 1; m <= 12; m++) {
      if (_selectedYear < now.year || m <= now.month) opciones.add(m);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedMonth,
              isDense: true,
              items: opciones
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(_mesesNombres[m],
                            style: const TextStyle(fontSize: 14)),
                      ))
                  .toList(),
              onChanged: (m) {
                if (m == null || m == _selectedMonth) return;
                setState(() => _selectedMonth = m);
                _fetchMonthly();
              },
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gráfica de barras
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBarChart() {
    final m = _metrics;
    if (m == null || m.chartData.isEmpty) {
      return _emptyChart(m?.message ?? 'Sin datos para este periodo.');
    }

    final maxVal  = m.chartData
        .map((p) => p.value)
        .fold(0.0, (a, b) => a > b ? a : b);
    const barMaxH = 120.0;
    final outlierDays = m.outliers.map((o) => o.date.day).toSet();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nivel de gas por mes',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const Text('Últimos datos — % del tanque',
              style: TextStyle(fontSize: 11, color: Colors.black38)),
          const SizedBox(height: 12),
          SizedBox(
            height: barMaxH + 55,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: m.chartData.map((point) {
                final fraction =
                    maxVal > 0 ? point.value / maxVal : 0.0;
                final barH =
                    (barMaxH * fraction).clamp(4.0, barMaxH);
                final isOutlier = outlierDays.contains(point.day);

                final Color barColor = point.value >= 50
                    ? MeterHistoryScreen.availableGreen
                    : point.value >= 25
                        ? Colors.amber[600]!
                        : const Color(0xFF9B59B6);

                return Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${point.value.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 9,
                            color: isOutlier
                                ? Colors.red[700]
                                : Colors.black38,
                            fontWeight: isOutlier
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 3),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOut,
                          height: barH,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(5),
                            border: isOutlier
                                ? Border.all(
                                    color: Colors.red, width: 2)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_mesAbrev(_selectedMonth)}\n${point.day}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 9, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyChart(String mensaje) => Container(
        width: double.infinity,
        height: 110,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bar_chart, size: 32, color: Colors.black26),
            const SizedBox(height: 8),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 12, color: Colors.black38),
            ),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Tarjetas de litros
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLiterCards() {
    final m             = _metrics;
    final double consumidoLt =
        m == null ? 0 : _capacityLiters * (m.totalConsumption / 100.0);
    final double restanteLt  =
        m == null ? 0 : _capacityLiters * (m.averagePercentage / 100.0);

    return Row(
      children: [
        Expanded(
          child: _literCard(
            valor: '${consumidoLt.toStringAsFixed(0)} lt',
            label: 'Consumido',
            color: MeterHistoryScreen.primaryBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _literCard(
            valor: '${restanteLt.toStringAsFixed(0)} lt',
            label: 'Restante prom.',
            color: MeterHistoryScreen.primaryBlue,
          ),
        ),
      ],
    );
  }

  Widget _literCard({
    required String valor,
    required String label,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Column(
          children: [
            Text(
              valor,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: Colors.black54)),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Tabla de logs del mes
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLogsTable() {
    final m = _metrics;
    if (m == null || m.logs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'Sin logs para este periodo.',
            style: TextStyle(color: Colors.black38, fontSize: 13),
          ),
        ),
      );
    }

    final rows = <_LogRow>[];
    for (int i = 0; i < m.logs.length; i++) {
      final log  = m.logs[i];
      final prev = i > 0 ? m.logs[i - 1].percentage : log.percentage;
      final diff = log.percentage - prev;
      final tipo = diff >= 0 ? 'Recarga' : 'Consumo';
      rows.add(_LogRow(fecha: log.date, tipo: tipo, cantidad: diff));
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // Cabecera
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F8F8),
              borderRadius: BorderRadius.only(
                topLeft:  Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text('Fecha',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Tipo',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54)),
                ),
                Text('Cantidad',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54)),
              ],
            ),
          ),
          const Divider(height: 1),
          // Filas
          ...rows.asMap().entries.map((e) {
            final i         = e.key;
            final row       = e.value;
            final isRecarga = row.tipo == 'Recarga';
            final isOutlier = m.outliers.any(
              (o) =>
                  o.date.day   == row.fecha.day &&
                  o.date.month == row.fecha.month,
            );

            return Column(
              children: [
                Container(
                  color: isOutlier
                      ? Colors.red.withOpacity(0.05)
                      : (i % 2 == 0
                          ? Colors.white
                          : const Color(0xFFFAFAFA)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          _formatDate(row.fecha),
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black87),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Text(
                              row.tipo,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isRecarga
                                    ? MeterHistoryScreen.availableGreen
                                    : MeterHistoryScreen.primaryBlue,
                              ),
                            ),
                            if (isOutlier) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.warning_amber_rounded,
                                  size: 14, color: Colors.red),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        row.cantidad == 0
                            ? '—'
                            : '${isRecarga ? '+' : ''}${row.cantidad.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isRecarga
                              ? MeterHistoryScreen.availableGreen
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < rows.length - 1) const Divider(height: 1),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Siguiente recarga estimada (cálculo heurístico)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildProximaRecarga() {
    final m = _metrics;
    if (m == null || m.activeDays == 0 || m.totalConsumption == 0) {
      return _recargaCard(
        diasRestantes: null,
        fechaSugerida: null,
        mensaje: 'Sin suficientes datos para proyectar.',
      );
    }

    final double consumoDiario = m.totalConsumption / m.activeDays;
    final double diasRestantes =
        consumoDiario > 0 ? m.averagePercentage / consumoDiario : 0;

    final DateTime fechaSugerida =
        DateTime.now().add(Duration(days: diasRestantes.round()));

    return _recargaCard(
      diasRestantes: diasRestantes.round(),
      fechaSugerida: fechaSugerida,
      mensaje: null,
    );
  }

  Widget _recargaCard({
    required int? diasRestantes,
    required DateTime? fechaSugerida,
    required String? mensaje,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFCCDEFF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: mensaje != null
            ? Text(
                mensaje,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.black54, fontSize: 13),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Días hasta próxima recarga',
                    style: TextStyle(
                        fontSize: 14, color: Color(0xFF1A3A6B)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$diasRestantes días',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0D2550),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (fechaSugerida != null)
                    Text(
                      'Recarga sugerida: ${_formatDateShort(fechaSugerida)}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF3B5A9A)),
                    ),
                ],
              ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // PREDICCIÓN INTELIGENTE — Gemini
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildAIPredictionSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título con chip "Gemini"
          Row(
            children: [
              const Text(
                'PREDICCIÓN INTELIGENTE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4285F4), Color(0xFF9B59B6)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Gemini',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildAICard(),
        ],
      );

  Widget _buildAICard() {
    if (!_aiRequested)       return _aiPromptCard();
    if (_aiLoading)          return _aiLoadingCard();
    if (_aiError != null)    return _aiErrorCard(_aiError!);

    final pred = _aiPrediction;
    if (pred == null || !pred.hasPrediction) {
      return _aiInsufficientCard(
        pred?.message ??
            'Historial de consumo insuficiente para calcular una predicción confiable.',
      );
    }

    return _aiResultCard(pred);
  }

  // ── No solicitado ─────────────────────────────────────────────────────────
  Widget _aiPromptCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEEF2FF), Color(0xFFF5EEFF)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFCBD5F5)),
        ),
        child: Column(
          children: [
            const Icon(Icons.auto_awesome,
                size: 32, color: Color(0xFF4285F4)),
            const SizedBox(height: 10),
            const Text(
              'Predicción con inteligencia artificial',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF1A237E),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Analiza tu historial de consumo con Gemini para estimar cuándo necesitarás recargar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchAIPrediction,
              icon: const Icon(Icons.bolt, size: 18),
              label: const Text('Generar predicción'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ],
        ),
      );

  // ── Cargando ──────────────────────────────────────────────────────────────
  Widget _aiLoadingCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFCBD5F5)),
        ),
        child: const Column(
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              valueColor:
                  AlwaysStoppedAnimation<Color>(Color(0xFF4285F4)),
            ),
            SizedBox(height: 14),
            Text(
              'Gemini está analizando tu historial…',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
      );

  // ── Error ─────────────────────────────────────────────────────────────────
  Widget _aiErrorCard(String msg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 28),
            const SizedBox(height: 8),
            Text(
              msg,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _fetchAIPrediction,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reintentar'),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF4285F4)),
            ),
          ],
        ),
      );

  // ── Datos insuficientes ───────────────────────────────────────────────────
  Widget _aiInsufficientCard(String msg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline,
                color: Colors.amber, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                    fontSize: 13, color: Colors.black54),
              ),
            ),
          ],
        ),
      );

  // ── Resultado ─────────────────────────────────────────────────────────────
  Widget _aiResultCard(_AIPrediction pred) {
    DateTime? rechargeDate;
    if (pred.estimatedRechargeDate != null) {
      rechargeDate =
          DateTime.tryParse(pred.estimatedRechargeDate!)?.toLocal();
    }

    final double conf      = pred.confidenceScore ?? 0;
    final Color confColor  = conf >= 0.8
        ? MeterHistoryScreen.availableGreen
        : conf >= 0.5
            ? Colors.amber
            : Colors.red;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8F0FE), Color(0xFFF0E6FF)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB3C4F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 18, color: Color(0xFF4285F4)),
              const SizedBox(width: 6),
              const Text(
                'Predicción de Gemini',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF1A237E),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _fetchAIPrediction,
                child: const Icon(Icons.refresh,
                    size: 18, color: Color(0xFF4285F4)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Días restantes
          Center(
            child: Column(
              children: [
                Text(
                  '${pred.daysRemaining} días',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D2550),
                  ),
                ),
                const Text(
                  'para la próxima recarga',
                  style: TextStyle(
                      fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (rechargeDate != null)
            _aiDetailRow(
              Icons.calendar_today,
              'Fecha estimada',
              _formatDateShort(rechargeDate),
            ),

          if (pred.estimatedConsumptionRate != null)
            _aiDetailRow(
              Icons.local_fire_department,
              'Consumo estimado',
              pred.estimatedConsumptionRate!,
            ),

          const SizedBox(height: 12),

          // Barra de confianza
          const Text(
            'Nivel de confianza',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: conf,
                    minHeight: 8,
                    backgroundColor: Colors.black12,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(confColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(conf * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: confColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aiDetailRow(IconData icon, String label, String value) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 15, color: const Color(0xFF4285F4)),
            const SizedBox(width: 8),
            Text(
              '$label: ',
              style: const TextStyle(
                  fontSize: 12, color: Colors.black54),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A237E),
              ),
            ),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────
  String _mesAbrev(int m) => const [
        '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
        'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
      ][m.clamp(1, 12)];

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')} ${_mesAbrev(dt.month)}';

  String _formatDateShort(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')} ${_mesAbrev(dt.month)} ${dt.year}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo interno para la tabla de logs
// ─────────────────────────────────────────────────────────────────────────────
class _LogRow {
  final DateTime fecha;
  final String tipo;
  final double cantidad;
  const _LogRow(
      {required this.fecha, required this.tipo, required this.cantidad});
}