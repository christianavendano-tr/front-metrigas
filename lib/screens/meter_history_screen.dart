// // Historial mensual de un medidor de gas.
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

  factory _MonthlyMetrics.fromJson(Map<String, dynamic> rawJson) {
    final j = rawJson.containsKey('data') ? rawJson['data'] : rawJson;

    return _MonthlyMetrics(
      month:             (j['month']  as num?)?.toInt() ?? 6,
      year:              (j['year']   as num?)?.toInt() ?? 2026,
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
  }

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
}

class _Log {
  final DateTime date;
  final double percentage;

  const _Log({required this.date, required this.percentage});

  factory _Log.fromJson(Map<String, dynamic> j) => _Log(
        date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
        percentage: (j['percentage'] as num?)?.toDouble() ?? 0.0,
      );
}

class _ChartPoint {
  final int day;
  final double value;

  const _ChartPoint({required this.day, required this.value});

  factory _ChartPoint.fromJson(Map<String, dynamic> j) => _ChartPoint(
        day:   (j['day'] as num?)?.toInt() ?? 0,
        value: (j['value'] as num?)?.toDouble() ?? 0.0,
      );
}

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
    final root = j.containsKey('data') ? j['data'] as Map<String, dynamic> : j;
    final pred = root['prediction'] as Map<String, dynamic>?;
    return _AIPrediction(
      meterId: root['meterId']?.toString() ?? '',
      estimatedRechargeDate: pred?['estimatedRechargeDate']?.toString(),
      daysRemaining: (pred?['daysRemaining'] as num?)?.toInt(),
      estimatedConsumptionRate: pred?['estimatedConsumptionRate']?.toString(),
      confidenceScore: (pred?['confidenceScore'] as num?)?.toDouble(),
      message: root['message']?.toString(),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// Pantalla Principal
// ─────────────────────────────────────────────────────────────────────────────
class MeterHistoryScreen extends StatefulWidget {
  const MeterHistoryScreen({super.key});

  static const Color primaryBlue = Color(0xFF0052CC);
  static const Color lightBlue = Color(0xFF3B82E0);
  static const Color availableGreen = Color(0xFF7CB342);
  static const String _baseUrl = 'http://localhost:3000';

  @override
  State<MeterHistoryScreen> createState() => _MeterHistoryScreenState();
}

class _MeterHistoryScreenState extends State<MeterHistoryScreen> {
  late String _hardwareId;
  late String _alias;
  late double _capacityLiters;
  bool _paramsResolved = false;

  late int _selectedMonth;
  late int _selectedYear;

  bool _isLoading = true;
  String? _error;
  _MonthlyMetrics? _metrics;

  bool _aiLoading = false;
  String? _aiError;
  _AIPrediction? _aiPrediction;
  bool _aiRequested = false;

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
    final now = DateTime.now();
    _selectedMonth = now.month;
    _selectedYear = now.year;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _hardwareId = args['hardwareId']?.toString() ?? '';
      _alias = args['alias']?.toString() ?? 'Medidor';
      _capacityLiters = args['capacityLiters'] is num
          ? (args['capacityLiters'] as num).toDouble()
          : double.tryParse(args['capacityLiters']?.toString() ?? '') ?? 20.0;
    } else {
      _hardwareId = '';
      _alias = 'Medidor';
      _capacityLiters = 20.0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MANEJADOR DE CAMBIO DE FILTRO
  // ─────────────────────────────────────────────────────────────────────────
  void _onMonthChanged(int? newMonth) {
    if (newMonth == null || newMonth == _selectedMonth) return;

    setState(() {
      _selectedMonth = newMonth;
      _metrics = null;
      _isLoading = true;
      _error = null;
      // Al cambiar de mes, la predicción de IA anterior ya no es válida
      // para el periodo que se va a mostrar.
      _aiPrediction = null;
      _aiRequested = false;
      _aiError = null;
    });

    _fetchMonthly();
  }

  /// Único punto de verdad para decidir si el backend realmente
  /// trajo datos para el periodo solicitado. Usa las MISMAS claves
  /// (snake_case) que consume _MonthlyMetrics.fromJson, para que el
  /// gate y el parser nunca queden desincronizados.
 bool _huboDatosReales(Map<String, dynamic> dataRoot) {
    final chartData = dataRoot['chartData'] as List? ?? [];
    final logs = dataRoot['logs'] as List? ?? [];
    final totalConsumption = (dataRoot['totalConsumption'] as num?)?.toDouble() ?? 0;
    
    return chartData.isNotEmpty || logs.isNotEmpty || totalConsumption != 0;
  }

  Future<void> _fetchMonthly() async {
    if (!mounted) return;

    if (!_isLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final token = await SessionService.getToken();
      final url = Uri.parse('${MeterHistoryScreen._baseUrl}/logs/monthly');

      final body = jsonEncode({
        'meterId': _hardwareId,
        'month': _selectedMonth,
        'year': _selectedYear,
      });

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      // NestJS puede responder 200 o 201 en un POST exitoso.
      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final dataRoot = decoded.containsKey('data')
            ? decoded['data'] as Map<String, dynamic>
            : decoded;

        if (!_huboDatosReales(dataRoot)) {
          _limpiarDatosPorCompleto(mensaje: decoded['message']?.toString());
        } else {
          setState(() {
            _metrics = _MonthlyMetrics.fromJson(dataRoot);
            _isLoading = false;
          });
        }
      } else {
        _limpiarDatosPorCompleto();
      }
    } catch (e) {
      if (mounted) _limpiarDatosPorCompleto();
    }
  }

  void _limpiarDatosPorCompleto({String? mensaje}) {
    if (!mounted) return;
    setState(() {
      _error = null;
      _isLoading = false;
      _metrics = _MonthlyMetrics(
        month: _selectedMonth,
        year: _selectedYear,
        totalConsumption: 0.0,
        averagePercentage: 0.0,
        standardDeviation: 0.0,
        lowerBound: 0.0,
        upperBound: 0.0,
        activeDays: 0,
        logs: [],
        chartData: [],
        outliers: [],
        message: mensaje ?? 'Sin registros para este mes',
      );
    });
  }

  Future<void> _fetchAIPrediction() async {
    if (!mounted) return;
    setState(() {
      _aiLoading = true;
      _aiError = null;
      _aiRequested = true;
    });

    try {
      final token = await SessionService.getToken();
      final url = Uri.parse('${MeterHistoryScreen._baseUrl}/logs/ai');

      // Se manda el mismo periodo (mes/año) que se está mostrando en
      // pantalla, para que la predicción esté ligada a esos datos y no
      // sea una llamada desconectada del contexto visible.
      final body = jsonEncode({
        'meterId': _hardwareId,
        'month': _selectedMonth,
        'year': _selectedYear,
      });

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _aiPrediction = _AIPrediction.fromJson(decoded);
          _aiLoading = false;
        });
      } else {
        setState(() {
          _aiError = 'El servidor no pudo procesar la predicción actual.';
          _aiLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _aiError = 'Error de red al conectar con Gemini AI.';
        _aiLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortId =
        _hardwareId.length > 8 ? _hardwareId.substring(0, 8).toUpperCase() : _hardwareId.toUpperCase();

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

  Widget _buildHeader() => Container(
        width: double.infinity,
        color: MeterHistoryScreen.primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: const Center(
          child: Text(
            'Metri GAS',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      );

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
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text('$_alias · ID:$shortId', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh, color: Colors.white),
              onPressed: _isLoading ? null : _fetchMonthly,
            ),
          ],
        ),
      );

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMonthSelector(),
          const SizedBox(height: 20),
          const Text('HISTORIAL DE DISPERSIÓN MENSUAL',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8)),
          const SizedBox(height: 12),
          _buildBarChart(),
          const SizedBox(height: 20),
          _buildLiterCards(),
          const SizedBox(height: 28),
          const Text('LOGS DEL MES (DISPERSIÓN DE LECTURAS)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          const Text('Variaciones puntuales registradas directamente por el sensor.',
              style: TextStyle(fontSize: 11, color: Colors.black45)),
          const SizedBox(height: 12),
          _buildScatterChart(),
          const SizedBox(height: 28),
          _buildAIPredictionSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    final now = DateTime.now();
    final opciones = <int>[];
    for (int m = 1; m <= 12; m++) {
      if (_selectedYear < now.year || m <= now.month) opciones.add(m);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration:
              BoxDecoration(border: Border.all(color: const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(6)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedMonth,
              isDense: true,
              items: opciones
                  .map((m) => DropdownMenuItem(value: m, child: Text(_mesesNombres[m], style: const TextStyle(fontSize: 14))))
                  .toList(),
              onChanged: _onMonthChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBarChart() {
    final m = _metrics;
    if (m == null || m.chartData.isEmpty) {
      return _emptyChart(m?.message ?? 'Sin registros de consumo en este periodo.');
    }

    List<List<double>> semanasValores = [[], [], [], []];

    for (final log in m.logs) {
      final dia = log.date.day;
      if (dia >= 1 && dia <= 7) semanasValores[0].add(log.percentage);
      if (dia >= 8 && dia <= 14) semanasValores[1].add(log.percentage);
      if (dia >= 15 && dia <= 21) semanasValores[2].add(log.percentage);
      if (dia >= 22 && dia <= 31) semanasValores[3].add(log.percentage);
    }

    List<double> semanasPromedios = [0.0, 0.0, 0.0, 0.0];
    double ultimoValorValido = m.averagePercentage > 0 ? m.averagePercentage : 100.0;

    for (int i = 0; i < 4; i++) {
      if (semanasValores[i].isNotEmpty) {
        semanasPromedios[i] = semanasValores[i].reduce((a, b) => a + b) / semanasValores[i].length;
        ultimoValorValido = semanasPromedios[i];
      } else {
        semanasPromedios[i] = ultimoValorValido;
      }
    }

    const barMaxH = 120.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nivel de gas promedio semanal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const Text('Monitoreo macro — % promedio del tanque', style: TextStyle(fontSize: 11, color: Colors.black38)),
          const SizedBox(height: 16),
          SizedBox(
            height: barMaxH + 45,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(4, (index) {
                final porcentajeSemana = semanasPromedios[index];
                final barH = (barMaxH * (porcentajeSemana / 100.0)).clamp(6.0, barMaxH);

                bool hayDecremento = index > 0 && semanasPromedios[index] < semanasPromedios[index - 1];

                final Color barColor = (hayDecremento || porcentajeSemana < 25)
                    ? const Color(0xFFEF4444)
                    : porcentajeSemana >= 50
                        ? MeterHistoryScreen.availableGreen
                        : Colors.amber[600]!;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${porcentajeSemana.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 10,
                            color: barColor,
                            fontWeight: hayDecremento ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 5),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          height: barH,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sem ${index + 1}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                );
              }),
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
            Text(mensaje, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black38)),
          ],
        ),
      );

  Widget _buildLiterCards() {
    final m = _metrics;
    final double consumidoLt = m == null ? 0 : _capacityLiters * (m.totalConsumption / 100.0);
    final double restanteLt = m == null ? 0 : _capacityLiters * (m.averagePercentage / 100.0);

    return Row(
      children: [
        Expanded(child: _literCard(valor: '${consumidoLt.toStringAsFixed(1)} lt', label: 'Consumido', color: MeterHistoryScreen.primaryBlue)),
        const SizedBox(width: 12),
        Expanded(child: _literCard(valor: '${restanteLt.toStringAsFixed(1)} lt', label: 'Restante prom.', color: MeterHistoryScreen.primaryBlue)),
      ],
    );
  }

  Widget _literCard({required String valor, required String label, required Color color}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE0E0E0))),
        child: Column(
          children: [
            Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      );

  Widget _buildScatterChart() {
    final m = _metrics;
    if (m == null || m.logs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE0E0E0))),
        child: const Center(child: Text('Sin logs de lecturas disponibles.', style: TextStyle(color: Colors.black38, fontSize: 12))),
      );
    }

    final outlierDays = m.outliers.map((o) => o.date.day).toSet();

    return Container(
      height: 200,
      width: double.infinity,
      padding: const EdgeInsets.only(right: 20, top: 15, bottom: 20, left: 45),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: CustomPaint(
        painter: _ScatterPainter(
          logs: m.logs,
          outlierDays: outlierDays,
          lightBlue: MeterHistoryScreen.lightBlue,
        ),
      ),
    );
  }

  Widget _buildAIPredictionSection() {
    // Si todavía no hay métricas reales del mes, no tiene sentido
    // ofrecer "calcular predicción": no habría datos sobre los cuales
    // basarla. Esto deja explícito el vínculo entre lo que se ve en
    // pantalla y la disponibilidad de la IA.
    final hayDatosDelMes = _metrics != null && _metrics!.chartData.isNotEmpty;

    if (!hayDatosDelMes) {
      return Center(
        child: Text(
          'No hay datos suficientes en este mes para calcular una predicción.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black45, fontSize: 12),
        ),
      );
    }

    if (!_aiRequested) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: _fetchAIPrediction,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Calcular Predicción Inteligente'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }

    if (_aiLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: Color(0xFF1E3A8A))));
    }

    if (_aiError != null) {
      return Text(_aiError!, style: const TextStyle(color: Colors.red, fontSize: 13));
    }

    final pred = _aiPrediction;
    if (pred == null || !pred.hasPrediction) {
      return const Text('No se pudo generar una predicción con los datos actuales.', style: TextStyle(color: Colors.black45));
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.auto_awesome, color: Color(0xFF93C5FD), size: 16),
              ),
              const SizedBox(width: 8),
              const Text('PREDICCIÓN GEMINI AI', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 16),
          Text('PRÓXIMA RECARGA ESTIMADA: En ${pred.daysRemaining} días', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('CONSUMO CALCULADO: ${pred.estimatedConsumptionRate ?? "—"}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text('NIVEL DE CONFIANZA: ${((pred.confidenceScore ?? 0) * 100).toStringAsFixed(0)}%', style: TextStyle(color: Colors.blue[300], fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text(pred.message ?? 'Análisis predictivo completado con éxito basado en tus flujos de dispersión.', style: TextStyle(color: Colors.blue[100], fontSize: 11, height: 1.3)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pintor personalizado para los logs del mes
// ─────────────────────────────────────────────────────────────────────────────
class _ScatterPainter extends CustomPainter {
  final List<_Log> logs;
  final Set<int> outlierDays;
  final Color lightBlue;

  _ScatterPainter({
    required this.logs,
    required this.outlierDays,
    required this.lightBlue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      double y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${(100 - (i * 25))}%',
          style: const TextStyle(fontSize: 9, color: Colors.black45),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(-35, y - 6));
    }

    if (logs.isEmpty) return;

    for (final log in logs) {
      final int day = log.date.day;
      if (day < 1 || day > 31) continue;

      double xFraction = (day - 1) / 30;
      double yFraction = 1 - (log.percentage / 100);

      double posX = xFraction * size.width;
      double posY = yFraction * size.height;

      final isOutlier = outlierDays.contains(day);

      final dotPaint = Paint()
        ..color = isOutlier ? Colors.red : (log.percentage < 25 ? Colors.amber[700]! : lightBlue)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(posX, posY), isOutlier ? 6.0 : 4.5, dotPaint);

      if (day == 1 || day == 7 || day == 14 || day == 21 || day == 28 || day == 31) {
        final dayPainter = TextPainter(
          text: TextSpan(text: 'D$day', style: const TextStyle(fontSize: 8, color: Colors.black45)),
          textDirection: TextDirection.ltr,
        )..layout();
        dayPainter.paint(canvas, Offset(posX - 8, size.height + 6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScatterPainter oldDelegate) => oldDelegate.logs != logs;
}