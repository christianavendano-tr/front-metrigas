import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'meter_telemetry_service.dart';

/// Dashboard individual de un medidor de gas.
///
/// Implementa el ticket "[FRONT] Dashboard individual de medidor:
/// cálculos de consumo":
/// - Recibe `hardwareId`, `alias` y `capacityLiters` como parámetros de
///   navegación desde el Dashboard Principal (mismo nombre de campo
///   que pide el ticket). `hardwareId` es el mismo identificador que
///   el backend llama `meterId` en `POST /meters` y `medidor_id` en la
///   tabla `logs`; aquí se respeta el nombre `hardwareId` porque así
///   está especificado en la tarea de enrutamiento.
/// - Al montar la pantalla, consulta telemetría instantánea vía
///   [MeterTelemetryService]: primero intenta mDNS local
///   (http://metrigas-[hardwareId].local/api/status) y, si falla,
///   hace fallback al último log conocido en la nube.
/// - Convierte el porcentaje del sensor a litros con las fórmulas
///   exactas del ticket:
///     Restante  = capacityLiters * (percentSensor / 100)
///     Consumido = capacityLiters - Restante
/// - Bloquea el botón de "Historial de uso" (paywall) si el usuario es
///   Invitado o Premium con `isActive == false`.
class MeterDashboardScreen extends StatefulWidget {
  final String hardwareId;
  final String alias;
  final double capacityLiters;

  /// Estado de sesión del usuario actual. En la versión final estos
  /// dos valores vendrán de un provider/servicio de sesión real; aquí
  /// se reciben como parámetros para poder construir la pantalla y
  /// probar ambos estados del paywall sin esa pieza todavía resuelta.
  ///
  /// isPremiumActive == true  <=> usuario Premium && isActive == true
  /// isPremiumActive == false <=> Invitado, o Premium && isActive == false
  final bool isPremiumActive;

  /// Inyectable para pruebas; por defecto crea una instancia real.
  final MeterTelemetryService? telemetryService;

  const MeterDashboardScreen({
    super.key,
    this.hardwareId = '3bc8e162-4217-4934-bc2c-5645367b1201',
    this.alias = 'Cocina Principal',
    this.capacityLiters = 15,
    this.isPremiumActive = false,
    this.telemetryService,
  });

  static const Color primaryBlue = Color(0xFF0052CC);
  static const Color lightBlue = Color(0xFF3B82E0);
  static const Color availableGreen = Color(0xFF7CB342);

  @override
  State<MeterDashboardScreen> createState() => _MeterDashboardScreenState();
}

class _MeterDashboardScreenState extends State<MeterDashboardScreen> {
  late final MeterTelemetryService _telemetryService;

  bool _isLoading = true;

  /// Último porcentaje conocido del sensor. Empieza en `null` mientras
  /// no haya ninguna lectura (ni local ni de la nube) para no inventar
  /// un valor que no fue reportado por el dispositivo.
  double? _percentAvailable;

  /// Origen de la última lectura recibida (mDNS local vs. fallback en
  /// la nube). Se guarda pero todavía no se muestra en la UI; queda
  /// disponible para cuando se quiera, por ejemplo, distinguir
  /// visualmente "dato en vivo" de "última lectura conocida".
  TelemetrySource? _lastSource;

  @override
  void initState() {
    super.initState();
    _telemetryService = widget.telemetryService ?? MeterTelemetryService();
    _loadTelemetry();
  }

  /// Cumple el criterio de "Resiliencia de Conexión": si tanto el mDNS
  /// local como el fallback en la nube fallan, la pantalla no lanza
  /// ninguna excepción visible; simplemente conserva la última lectura
  /// que ya tenía (o se queda en un estado vacío neutro si nunca tuvo
  /// ninguna).
  Future<void> _loadTelemetry() async {
    setState(() => _isLoading = true);

    try {
      final reading = await _telemetryService.fetchLatestReading(widget.hardwareId);
      if (!mounted) return;

      if (reading != null) {
        setState(() {
          _percentAvailable = reading.percentAvailable;
          _lastSource = reading.source;
        });
      }
      // Si `reading` es null, intencionalmente no se toca
      // `_percentAvailable`: se conserva la última lectura visible en
      // pantalla en vez de mostrar un error.
    } catch (_) {
      // Defensa adicional: aunque el servicio ya atrapa sus propios
      // errores y regresa null, cualquier excepción inesperada aquí
      // tampoco debe tirar la pantalla.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------
  // Motor de cálculo: fórmulas exactas del ticket, sin atajos que
  // introduzcan error de redondeo antes de mostrar el valor final.
  //   Restante  = Capacidad_Total * (Porcentaje_Sensor / 100)
  //   Consumido = Capacidad_Total - Restante
  // ---------------------------------------------------------------------
  double _calculateRemaining(double capacityTotal, double percentSensor) {
    return capacityTotal * (percentSensor / 100);
  }

  double _calculateConsumed(double capacityTotal, double remaining) {
    return capacityTotal - remaining;
  }

  @override
  Widget build(BuildContext context) {
    // Mientras no haya ninguna lectura todavía (primer load en curso y
    // sin valor previo), no se asume un porcentaje arbitrario: se usa
    // 0 solo para poder pintar el layout, y la UI lo señala con el
    // indicador de carga superpuesto.
    final double percentSensor = _percentAvailable ?? 0;
    final double remaining = _calculateRemaining(widget.capacityLiters, percentSensor);
    final double consumed = _calculateConsumed(widget.capacityLiters, remaining);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            _buildSubHeader(context),
            Expanded(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Column(
                      children: [
                        _buildGaugeWithLegend(remaining, consumed, percentSensor),
                        const SizedBox(height: 22),
                        _buildLitersSummary(remaining, consumed),
                        const SizedBox(height: 20),
                        _buildAlertBanner(percentSensor),
                        const SizedBox(height: 28),
                        _buildActionRow(context),
                      ],
                    ),
                  ),
                  if (_isLoading && _percentAvailable == null)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x33FFFFFF),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Header: "Metri GAS" + avatar de usuario
  // ---------------------------------------------------------------------
  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      color: MeterDashboardScreen.primaryBlue,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const SizedBox(width: 36), // balancea el avatar para centrar el título
          const Expanded(
            child: Text(
              'Metri GAS',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white,
            child: Icon(Icons.person, color: MeterDashboardScreen.primaryBlue, size: 18),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Sub-header: flecha de regreso + alias del medidor + hardwareId (corto)
  // ---------------------------------------------------------------------
  Widget _buildSubHeader(BuildContext context) {
    final shortId = widget.hardwareId.length > 8
        ? widget.hardwareId.substring(0, 8).toUpperCase()
        : widget.hardwareId.toUpperCase();

    return Container(
      width: double.infinity,
      color: MeterDashboardScreen.lightBlue,
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
                  widget.alias,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // El hardwareId real es un UUID largo; se muestra solo
                  // su prefijo como referencia corta, igual que en el
                  // mock visual original (ID:MED-001).
                  'ID:$shortId',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Actualizar telemetría',
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isLoading ? null : _loadTelemetry,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Dona circular de nivel + leyenda
  // ---------------------------------------------------------------------
  Widget _buildGaugeWithLegend(double remaining, double consumed, double percentSensor) {
    return Column(
      children: [
        SizedBox(
          width: 220,
          height: 220,
          child: CustomPaint(
            painter: _GaugePainter(
              percentAvailable: percentSensor,
              availableColor: MeterDashboardScreen.availableGreen,
              consumedColor: MeterDashboardScreen.lightBlue,
            ),
            child: Center(
              child: Container(
                width: 130,
                height: 130,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F1F1),
                  shape: BoxShape.circle,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${percentSensor.round()}%',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const Text(
                      'disponible',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendDot(MeterDashboardScreen.availableGreen, 'Disponible'),
            const SizedBox(width: 28),
            _legendDot(MeterDashboardScreen.lightBlue, 'Consumido'),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Colors.black87),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Tarjetas de litros disponibles / consumidos
  // ---------------------------------------------------------------------
  Widget _buildLitersSummary(double remaining, double consumed) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _literCard(
          value: remaining,
          label: 'Disponible',
          valueColor: MeterDashboardScreen.availableGreen,
        ),
        const SizedBox(width: 16),
        _literCard(
          value: consumed,
          label: 'Consumido',
          valueColor: Colors.black87,
        ),
      ],
    );
  }

  Widget _literCard({
    required double value,
    required String label,
    required Color valueColor,
  }) {
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        children: [
          Text(
            '${value.toStringAsFixed(0)} lt',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Banner de alerta de nivel bajo
  // ---------------------------------------------------------------------
  Widget _buildAlertBanner(double percentSensor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFD9FB)),
      ),
      child: Text(
        'El nivel de Calentador está al ${percentSensor.round()}%. Recarga Pronto.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          color: MeterDashboardScreen.primaryBlue,
          height: 1.3,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Fila de acciones: actualizar info de red / historial de uso / eliminar
  // ---------------------------------------------------------------------
  Widget _buildActionRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ActionButton(
          icon: Icons.wifi,
          label: 'Actualizar\ninfo de red',
          backgroundColor: MeterDashboardScreen.lightBlue,
          onTap: _isLoading ? null : _loadTelemetry,
        ),
        _buildHistorialButton(context, widget.isPremiumActive),
        _ActionButton(
          icon: Icons.delete_outline,
          label: 'Eliminar\nmedidor',
          backgroundColor: MeterDashboardScreen.lightBlue,
          onTap: () {
            // TODO: confirmar y eliminar medidor
          },
        ),
      ],
    );
  }

  /// === COMPONENTE VISUAL DEL BOTÓN DE HISTORIAL CON PAYWALL ===
  /// Misma firma y misma regla de negocio que el placeholder del
  /// ticket: si `isPremiumActive` es falso (Invitado o Premium con
  /// `isActive == false`), el botón se renderiza opaco, con ícono de
  /// candado, y `onPressed` queda en `null` para que Flutter lo
  /// deshabilite de forma nativa (sin necesidad de lógica adicional
  /// para bloquear el tap).
  Widget _buildHistorialButton(BuildContext context, bool isPremiumActive) {
    return _ActionButton(
      icon: isPremiumActive ? Icons.history : Icons.lock,
      label: 'Historial\nde uso',
      backgroundColor: const Color(0xFF0B2F6B),
      isLocked: !isPremiumActive,
      onTap: isPremiumActive
          ? () => Navigator.pushNamed(context, '/meter-history', arguments: widget.hardwareId)
          : null,
    );
  }
}

/// Botón circular de acción usado en la fila inferior del dashboard.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback? onTap;
  final bool isLocked;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.onTap,
    this.isLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isLocked ? 0.5 : 1.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: backgroundColor,
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: MeterDashboardScreen.primaryBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pinta la dona de progreso circular (disponible en verde, consumido en
/// azul) replicando el estilo de la captura: dos arcos con espacio entre
/// ellos y extremos redondeados.
///
/// Nota: el ticket sugiere `fl_chart` como librería de gráficos; se
/// optó por un `CustomPainter` propio para tener control exacto sobre
/// el gap entre arcos y el grosor, igual al mock visual de referencia.
/// Si el equipo prefiere estandarizar en `fl_chart` (p. ej. para
/// reusar tooltips o animaciones ya resueltas por la librería en otras
/// pantallas), este painter se puede sustituir por un
/// `PieChart`/`RadialBarChart` sin afectar el resto de la pantalla.
class _GaugePainter extends CustomPainter {
  final double percentAvailable;
  final Color availableColor;
  final Color consumedColor;

  _GaugePainter({
    required this.percentAvailable,
    required this.availableColor,
    required this.consumedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;
    const strokeWidth = 16.0;
    const gapDegrees = 10.0;

    final availableFraction = (percentAvailable.clamp(0, 100)) / 100;
    final totalSweep = 360 - gapDegrees * 2;
    final availableSweep = totalSweep * availableFraction;
    final consumedSweep = totalSweep * (1 - availableFraction);

    final startAngle = _toRad(-90 + gapDegrees / 2);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Arco "disponible" (verde)
    paint.color = availableColor;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      _toRad(availableSweep),
      false,
      paint,
    );

    // Arco "consumido" (azul), inicia tras el gap posterior al verde
    paint.color = consumedColor;
    final consumedStart = startAngle + _toRad(availableSweep + gapDegrees);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      consumedStart,
      _toRad(consumedSweep),
      false,
      paint,
    );
  }

  double _toRad(double degrees) => degrees * math.pi / 180;

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.percentAvailable != percentAvailable ||
        oldDelegate.availableColor != availableColor ||
        oldDelegate.consumedColor != consumedColor;
  }
}
