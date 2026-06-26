// lib/screens/meter_history_screen.dart
//
// Pantalla de historial de consumo.
// Consume: GET /metrics?medidor_id={id}   (requiere token JWT)
//
// Criterios de aceptación implementados:
//   ✅ Gráfica de barras con datos_mensuales[]
//   ✅ Tarjetas: consumo_total, promedio_mensual, max_mensual, porcentaje_promedio
//   ✅ Fecha último log + proyección próxima carga
//   ✅ Si no hay datos → pantalla vacía amigable (no 404)
//   ✅ Motor de cálculo: Restante = CapTotal × (% / 100)
//
// Argumentos de ruta (Map):
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
class _MetricsData {
  final double consumoTotal;
  final double promedioMensual;
  final double maxMensual;
  final double porcentajePromedio;
  final String? fechaUltimoLog;
  final String? proximaCarga;
  final List<_MesData> datosMensuales;

  const _MetricsData({
    required this.consumoTotal,
    required this.promedioMensual,
    required this.maxMensual,
    required this.porcentajePromedio,
    this.fechaUltimoLog,
    this.proximaCarga,
    required this.datosMensuales,
  });

  factory _MetricsData.empty() => const _MetricsData(
        consumoTotal: 0,
        promedioMensual: 0,
        maxMensual: 0,
        porcentajePromedio: 0,
        datosMensuales: [],
      );

  factory _MetricsData.fromJson(Map<String, dynamic> j) {
    final raw = j['datos_mensuales'];
    final meses = raw is List
        ? raw.map((m) => _MesData.fromJson(m as Map<String, dynamic>)).toList()
        : <_MesData>[];

    return _MetricsData(
      consumoTotal:       _toDouble(j['consumo_total']),
      promedioMensual:    _toDouble(j['promedio_mensual']),
      maxMensual:         _toDouble(j['max_mensual']),
      porcentajePromedio: _toDouble(j['porcentaje_promedio']),
      fechaUltimoLog:     j['fecha_ultimo_log']?.toString(),
      proximaCarga:       j['proyeccion_proxima_carga']?.toString(),
      datosMensuales:     meses,
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

class _MesData {
  final String etiqueta; // "Ene", "Feb", …
  final int mes;
  final int anio;
  final double consumo;
  final double porcentajePromedio;

  const _MesData({
    required this.etiqueta,
    required this.mes,
    required this.anio,
    required this.consumo,
    required this.porcentajePromedio,
  });

  factory _MesData.fromJson(Map<String, dynamic> j) {
    final mes  = (j['mes']  as num?)?.toInt() ?? 1;
    final anio = (j['anio'] as num?)?.toInt() ?? DateTime.now().year;
    return _MesData(
      etiqueta:           _mesAbrev(mes),
      mes:                mes,
      anio:               anio,
      consumo:            _MetricsData._toDouble(j['consumo']),
      porcentajePromedio: _MetricsData._toDouble(j['porcentaje_promedio']),
    );
  }

  static String _mesAbrev(int m) => const [
        '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
        'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
      ][m.clamp(1, 12)];
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

  // ── estado ───────────────────────────────────────────────────────────────
  bool         _isLoading = true;
  String?      _error;
  _MetricsData _metrics   = _MetricsData.empty();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_paramsResolved) {
      _paramsResolved = true;
      _resolveParams();
      _fetchMetrics();
    }
  }

  void _resolveParams() {
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

  // ── GET /metrics?medidor_id={id} ─────────────────────────────────────────
  Future<void> _fetchMetrics() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; });

    try {
      final token = SessionService.getToken();
      final url   = Uri.parse(
        '${MeterHistoryScreen._baseUrl}/metrics?medidor_id=$_hardwareId',
      );

      debugPrint('📊 [History] GET $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('📊 [History] Status: ${response.statusCode}');
      debugPrint('📊 [History] Body:   ${response.body}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        // El backend puede envolver en { data: {...} } o devolver el objeto directo
        final payload = decoded is Map && decoded['data'] is Map
            ? decoded['data'] as Map<String, dynamic>
            : decoded as Map<String, dynamic>;

        setState(() => _metrics = _MetricsData.fromJson(payload));
      } else if (response.statusCode == 403) {
        setState(() => _error = 'No tienes permiso para ver este medidor.');
      } else {
        setState(() => _error = 'Error del servidor (${response.statusCode}).');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Sin conexión: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  // ── Header ───────────────────────────────────────────────────────────────
  Widget _buildHeader() => Container(
        width: double.infinity,
        color: MeterHistoryScreen.primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const SizedBox(width: 36),
            const Expanded(
              child: Text(
                'Metri GAS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              child: Icon(Icons.person,
                  color: MeterHistoryScreen.primaryBlue, size: 18),
            ),
          ],
        ),
      );

  // ── Sub-header ───────────────────────────────────────────────────────────
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
                  Text(
                    _alias,
                    style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Historial · ID: $shortId',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: _isLoading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh, color: Colors.white),
              onPressed: _isLoading ? null : _fetchMetrics,
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
                style: const TextStyle(color: Colors.black45, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _fetchMetrics,
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

    final bool vacio = _metrics.datosMensuales.isEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Chips de info ──────────────────────────────────────────────
          Wrap(
            spacing: 8,
            children: [
              _chip(
                'Capacidad: ${_capacityLiters.toStringAsFixed(0)} L',
                Colors.blue[50]!,
                MeterHistoryScreen.primaryBlue,
              ),
              if (_metrics.fechaUltimoLog != null)
                _chip(
                  'Último log: ${_formatDate(_metrics.fechaUltimoLog!)}',
                  Colors.green[50]!,
                  Colors.green[700]!,
                ),
              if (_metrics.proximaCarga != null)
                _chip(
                  'Próx. carga: ${_formatDate(_metrics.proximaCarga!)}',
                  Colors.orange[50]!,
                  Colors.orange[700]!,
                ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Tarjetas de métricas ───────────────────────────────────────
          _buildMetricasGrid(),

          const SizedBox(height: 24),

          // ── Gráfica de barras ──────────────────────────────────────────
          const Text(
            'Consumo mensual (litros)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            vacio
                ? 'Sin registros históricos todavía.'
                : 'Basado en ${_metrics.datosMensuales.length} mes(es) de datos.',
            style: const TextStyle(fontSize: 12, color: Colors.black38),
          ),
          const SizedBox(height: 16),

          vacio ? _buildEmptyChart() : _buildBarChart(),

          const SizedBox(height: 24),

          // ── Porcentaje promedio por mes ────────────────────────────────
          if (!vacio) ...[
            const Text(
              'Nivel promedio del tanque por mes (%)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 16),
            _buildPercentChart(),
          ],
        ],
      ),
    );
  }

  // ── Grid de 4 tarjetas de métricas ───────────────────────────────────────
  Widget _buildMetricasGrid() {
    // Motor de cálculo: Restante = CapTotal × (porcentajePromedio / 100)
    final double restantePromedio =
        _capacityLiters * (_metrics.porcentajePromedio / 100.0);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _metricCard(
          icon: Icons.local_fire_department,
          iconColor: Colors.orange,
          label: 'Consumo total',
          value: '${_metrics.consumoTotal.toStringAsFixed(1)} L',
        ),
        _metricCard(
          icon: Icons.calendar_month,
          iconColor: MeterHistoryScreen.primaryBlue,
          label: 'Promedio mensual',
          value: '${_metrics.promedioMensual.toStringAsFixed(1)} L',
        ),
        _metricCard(
          icon: Icons.trending_up,
          iconColor: Colors.red[700]!,
          label: 'Máximo en un mes',
          value: '${_metrics.maxMensual.toStringAsFixed(1)} L',
        ),
        _metricCard(
          icon: Icons.opacity,
          iconColor: MeterHistoryScreen.availableGreen,
          // Fórmula explícita en el tooltip visual:
          // Restante = CapTotal × (% / 100)
          label: 'Restante promedio',
          value: '${restantePromedio.toStringAsFixed(1)} L',
          subtitle: '${_metrics.porcentajePromedio.toStringAsFixed(0)}% prom.',
        ),
      ],
    );
  }

  Widget _metricCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.black38),
            ),
        ],
      ),
    );
  }

  // ── Gráfica de barras: consumo mensual ───────────────────────────────────
  Widget _buildBarChart() {
    final datos  = _metrics.datosMensuales;
    final maxVal = datos.map((d) => d.consumo).fold(0.0, (a, b) => a > b ? a : b);
    final barMaxH = 130.0;

    return SizedBox(
      height: barMaxH + 48,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: datos.map((d) {
          final fraction = maxVal > 0 ? d.consumo / maxVal : 0.0;
          final barH     = (barMaxH * fraction).clamp(4.0, barMaxH);
          final isMax    = d.consumo == maxVal && maxVal > 0;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Valor encima de la barra
                  Text(
                    d.consumo > 0
                        ? d.consumo.toStringAsFixed(1)
                        : '',
                    style: TextStyle(
                      fontSize: 9,
                      color: isMax ? Colors.red[700] : Colors.black38,
                      fontWeight: isMax ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Barra
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOut,
                    height: barH,
                    decoration: BoxDecoration(
                      color: isMax
                          ? Colors.red[400]
                          : MeterHistoryScreen.primaryBlue,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Etiqueta mes
                  Text(
                    d.etiqueta,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                  // Año (solo si hay más de un año en los datos)
                  if (_hayMultiplesAnios())
                    Text(
                      '${d.anio}',
                      style: const TextStyle(fontSize: 8, color: Colors.black26),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Gráfica de barras: porcentaje promedio ────────────────────────────────
  Widget _buildPercentChart() {
    final datos  = _metrics.datosMensuales;
    final barMaxH = 100.0;

    return SizedBox(
      height: barMaxH + 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: datos.map((d) {
          final fraction = d.porcentajePromedio.clamp(0.0, 100.0) / 100.0;
          final barH     = (barMaxH * fraction).clamp(4.0, barMaxH);
          final color    = fraction >= 0.5
              ? MeterHistoryScreen.availableGreen
              : fraction >= 0.25
                  ? Colors.orange
                  : Colors.red;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${d.porcentajePromedio.toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 9, color: color),
                  ),
                  const SizedBox(height: 3),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOut,
                    height: barH,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    d.etiqueta,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyChart() => Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 36, color: Colors.black26),
            SizedBox(height: 8),
            Text(
              'Sin datos mensuales todavía.\nLos registros aparecerán aquí cuando el medidor envíe lecturas.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black38, height: 1.4),
            ),
          ],
        ),
      );

  // ── Helpers ──────────────────────────────────────────────────────────────
  bool _hayMultiplesAnios() {
    final anios = _metrics.datosMensuales.map((d) => d.anio).toSet();
    return anios.length > 1;
  }

  Widget _chip(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600),
        ),
      );

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }
}