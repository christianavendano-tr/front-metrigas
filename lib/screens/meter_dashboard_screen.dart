import 'package:flutter/material.dart';
import 'package:front_metrigas/services/session_service.dart';
import 'dart:math' as math;
import '../services/meter_manager.dart';
import '../services/storage_service.dart';
import '../services/meter_telemetry_service.dart';
import '../services/socket_services.dart';
// Agregar esta línea (asumiendo que están en la misma carpeta screens):
import 'meter_history_screen.dart';

/// Dashboard individual de un medidor de gas.
///
/// Recibe argumentos de navegación como Map desde DashboardScreen:
/// {
///   'hardwareId'     : String  — UUID del medidor en Postgres / local
///   'alias'          : String  — metername legible
///   'capacityLiters' : double  — capacidad total del tanque en litros
///   'isPremiumActive': bool    — true SOLO si Premium && isActive == true
/// }
///
/// PAYWALL (regla de negocio obligatoria):
///   Historial BLOQUEADO  → usuario Invitado  O  Premium con isActive == false
///   Historial DESBLOQUEADO → Premium con isActive == true  ÚNICAMENTE
///
/// MOTOR DE CÁLCULO (fórmulas exactas del ticket):
///   Restante  = CapacidadTotal × (PorcentajeSensor / 100)
///   Consumido = CapacidadTotal − Restante
class MeterDashboardScreen extends StatefulWidget {
  final String hardwareId;
  final String alias;
  final double capacityLiters;
  final bool isPremiumActive;
  final MeterTelemetryService? telemetryService;

  const MeterDashboardScreen({
    super.key,
    this.hardwareId = '',
    this.alias = 'Medidor',
    this.capacityLiters = 20,
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

  // ── estado de telemetría ──────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isDeleting = false;
  double? _percentAvailable; // null = sin lectura todavía

  // ── parámetros resueltos desde la ruta ───────────────────────────────────
  late String _hardwareId;
  late String _alias;
  late double _capacityLiters;
  late bool _isPremiumActive;
  bool _paramsResolved = false;

  // ── paywall ───────────────────────────────────────────────────────────────
  // TODO: revertir a la lógica real cuando el endpoint GET /last-log esté listo.
  // Lógica real (descomentar cuando corresponda):
  //   bool get _historialDesbloqueado {
  //     final state = StorageService.userStateNotifier.value;
  //     return _isPremiumActive && state == UserState.premiumActive;
  //   }
  //
  // PROVISIONAL: siempre desbloqueado para poder desarrollar la pantalla
  // de historial sin depender del estado de suscripción.
  bool get _historialDesbloqueado => true;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _telemetryService = widget.telemetryService ?? MeterTelemetryService();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_paramsResolved) {
      _paramsResolved = true;
      _resolveRouteParams();
      _loadTelemetry();
    }
  }

  /// Extrae los argumentos de la ruta; si faltan usa defaults del constructor.
  void _resolveRouteParams() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _hardwareId = args['hardwareId']?.toString() ?? widget.hardwareId;
      _alias = args['alias']?.toString() ?? widget.alias;
      _isPremiumActive =
          args['isPremiumActive'] as bool? ?? widget.isPremiumActive;
      _capacityLiters = switch (args['capacityLiters']) {
        final num n => n.toDouble(),
        final Object o =>
          double.tryParse(o.toString()) ?? widget.capacityLiters,
        _ => widget.capacityLiters,
      };
    } else {
      _hardwareId = widget.hardwareId;
      _alias = widget.alias;
      _capacityLiters = widget.capacityLiters;
      _isPremiumActive = widget.isPremiumActive;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Telemetría
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadTelemetry() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final socketPercent = await _requestSocketPercentage();
      if (!mounted) return;

      if (socketPercent != null) {
        setState(() => _percentAvailable = socketPercent);
        return;
      }

      final logsPercent =
          await MeterManager.obtenerPorcentajeDesdeLogs(_hardwareId);
      if (!mounted) return;

      if (logsPercent != null) {
        setState(() => _percentAvailable = logsPercent);
        return;
      }

      final reading = await _telemetryService.fetchLatestReading(_hardwareId);
      if (!mounted) return;
      if (reading != null) {
        setState(() => _percentAvailable = reading.percentAvailable);
      }
    } catch (_) {
      try {
        final reading = await _telemetryService.fetchLatestReading(_hardwareId);
        if (!mounted) return;
        if (reading != null) {
          setState(() => _percentAvailable = reading.percentAvailable);
        }
      } catch (_) {
        // Error silencioso: conserva la última lectura visible.
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<double?> _requestSocketPercentage() async {
    final mdnsName = _alias.trim().isNotEmpty ? _alias : _hardwareId;

    if (mdnsName.isEmpty) {
      return null;
    }

    final response = await SocketLcgService.sendCommand(
      mdnsName: mdnsName,
      commandJson: {'action': 'get_percentage'},
    );

    return SocketLcgService.parsePercentageFromResponse(response);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Motor de cálculo — fórmulas exactas del ticket
  //   Restante  = CapacidadTotal × (PorcentajeSensor / 100)
  //   Consumido = CapacidadTotal − Restante
  // ─────────────────────────────────────────────────────────────────────────
  double _litrosRestantes(double capacityTotal, double percentSensor) =>
      capacityTotal * (percentSensor / 100.0);

  double _litrosConsumidos(double capacityTotal, double restantes) =>
      capacityTotal - restantes;

  // ─────────────────────────────────────────────────────────────────────────
  // Eliminar medidor
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _confirmarEliminar() async {
    // 1. Diálogo de confirmación
    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Eliminar medidor',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
                fontSize: 14, color: Colors.black87, height: 1.4),
            children: [
              const TextSpan(text: '¿Deseas eliminar '),
              TextSpan(
                text: '"$_alias"',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const TextSpan(
                  text:
                      '?\n\nEsta acción no se puede deshacer y eliminará todos los datos asociados.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, eliminar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    // 2. Intentar reset por socket antes de cualquier borrado
    setState(() => _isDeleting = true);

    try {
      final response = await SocketLcgService.sendCommand(
        mdnsName: _alias.trim().isNotEmpty ? _alias : _hardwareId,
        commandJson: {'action': 'reset'},
      );

      final resetOk = SocketLcgService.isResetConfirmed(response);
      if (!resetOk) {
        if (!mounted) return;
        setState(() => _isDeleting = false);
        _showResetBlockedSnack();
        return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      _showResetBlockedSnack();
      return;
    }

    bool ok = true;
    final token = SessionService.getToken();

    if (token != null && token.isNotEmpty) {
      ok = await MeterManager.eliminarMedidorRemoto(_hardwareId);
    }

    if (ok) {
      ok = await MeterManager.eliminarMedidorSoloLocal(_hardwareId);
    }

    if (!mounted) return;
    setState(() => _isDeleting = false);

    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo eliminar el medidor. Intenta de nuevo.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final double percentSensor = _percentAvailable ?? 0;
    final bool sinLectura = _percentAvailable == null;

    final double restantes = _litrosRestantes(_capacityLiters, percentSensor);
    final double consumidos = _litrosConsumidos(_capacityLiters, restantes);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                _buildSubHeader(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                    child: Column(
                      children: [
                        // ── Dona circular ────────────────────────────
                        _buildGaugeWithLegend(percentSensor, sinLectura),
                        const SizedBox(height: 22),

                        // ── Tarjetas de litros (motor de cálculo) ────
                        _buildLitersSummary(restantes, consumidos, sinLectura),
                        const SizedBox(height: 20),

                        // ── Banner de alerta ─────────────────────────
                        _buildAlertBanner(percentSensor, sinLectura),
                        const SizedBox(height: 28),

                        // ── Fila de acciones ─────────────────────────
                        ValueListenableBuilder<UserState>(
                          valueListenable: StorageService.userStateNotifier,
                          builder: (_, __, ___) => _buildActionRow(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Overlay de carga inicial (sin lectura previa)
            if (_isLoading && sinLectura)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x55FFFFFF),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),

            // Overlay de eliminación
            if (_isDeleting)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x88000000),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        'Eliminando medidor…',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Header azul: "Metri GAS" (Limpio, sin avatar de perfil)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: MeterDashboardScreen.primaryBlue,
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
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sub-header: flecha + alias + shortId + refresh
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSubHeader(BuildContext context) {
    final shortId = _hardwareId.length > 8
        ? _hardwareId.substring(0, 8).toUpperCase()
        : _hardwareId.toUpperCase();

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
                  _alias,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ID: $shortId',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isLoading ? null : _loadTelemetry,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dona circular
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildGaugeWithLegend(double percentSensor, bool sinLectura) {
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
                child: sinLectura
                    ? const Center(
                        child: Text(
                          'Sin\nlectura',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.black45),
                        ),
                      )
                    : Column(
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
                            style:
                                TextStyle(fontSize: 13, color: Colors.black54),
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

  Widget _legendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ],
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Tarjetas de litros
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLitersSummary(
      double restantes, double consumidos, bool sinLectura) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _literCard(
          titulo: sinLectura ? '-- lt' : '${restantes.toStringAsFixed(1)} lt',
          subtitulo: 'Disponible',
          formula: sinLectura
              ? '-- × (-- / 100)'
              : '${_capacityLiters.toStringAsFixed(0)} × (${(_percentAvailable ?? 0).toStringAsFixed(0)} / 100)',
          valueColor: MeterDashboardScreen.availableGreen,
        ),
        const SizedBox(width: 16),
        _literCard(
          titulo: sinLectura ? '-- lt' : '${consumidos.toStringAsFixed(1)} lt',
          subtitulo: 'Consumido',
          formula: sinLectura
              ? '-- − --'
              : '${_capacityLiters.toStringAsFixed(0)} − ${restantes.toStringAsFixed(1)}',
          valueColor: Colors.black87,
        ),
      ],
    );
  }

  Widget _literCard({
    required String titulo,
    required String subtitulo,
    required String formula,
    required Color valueColor,
  }) {
    return Container(
      width: 145,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        children: [
          Text(
            titulo,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: valueColor),
          ),
          const SizedBox(height: 2),
          Text(subtitulo,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(
            formula,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Colors.black38),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Banner de alerta
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildAlertBanner(double percentSensor, bool sinLectura) {
    if (sinLectura) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: const Text(
          'Sin datos de telemetría. Pulsa "Actualizar info de red" para obtener la lectura del sensor.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.black45, height: 1.3),
        ),
      );
    }

    final bool critico = percentSensor < 15;
    final bool bajo = percentSensor >= 15 && percentSensor < 30;

    final Color bgColor = critico
        ? const Color(0xFFFFEBEE)
        : bajo
            ? const Color(0xFFFFF3E0)
            : const Color(0xFFEFF6FF);
    final Color borderColor = critico
        ? const Color(0xFFEF9A9A)
        : bajo
            ? const Color(0xFFFFB74D)
            : const Color(0xFFBFD9FB);
    final Color textColor = critico
        ? Colors.red[800]!
        : bajo
            ? Colors.orange[800]!
            : MeterDashboardScreen.primaryBlue;
    final String icono = critico
        ? '🚨'
        : bajo
            ? '⚠️'
            : 'ℹ️';
    final String mensaje = critico
        ? '$icono Nivel crítico en "$_alias": ${percentSensor.round()}%. ¡Recarga inmediatamente!'
        : bajo
            ? '$icono Nivel bajo en "$_alias": ${percentSensor.round()}%. Recarga pronto.'
            : '$icono "$_alias" al ${percentSensor.round()}% de capacidad.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        mensaje,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: textColor, height: 1.3),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Fila de acciones
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildActionRow(BuildContext context) {
    final bool desbloqueado = _historialDesbloqueado;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Botón 1: Actualizar red
        _ActionButton(
          icon: Icons.wifi,
          label: 'Actualizar\ninfo de red',
          backgroundColor: MeterDashboardScreen.lightBlue,
          onTap: _isLoading || _isDeleting ? null : _loadTelemetry,
        ),

        // Botón 2: Historial (con paywall)
        _ActionButton(
          icon: desbloqueado ? Icons.history : Icons.lock,
          label: 'Historial\nde uso',
          backgroundColor: const Color(0xFF0B2F6B),
          isLocked: !desbloqueado,
          onTap: desbloqueado
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MeterHistoryScreen(),
                      settings: RouteSettings(
                        arguments: {
                          'hardwareId': _hardwareId,
                          'alias': _alias,
                          'capacityLiters': _capacityLiters,
                        },
                      ),
                    ),
                  )
              : () => _mostrarPaywallSnack(context),
        ),

        // Botón 3: Eliminar medidor
        _ActionButton(
          icon: Icons.delete_outline,
          label: 'Eliminar\nmedidor',
          backgroundColor: Colors.red[700]!,
          onTap: _isDeleting ? null : _confirmarEliminar,
        ),
      ],
    );
  }

  void _mostrarPaywallSnack(BuildContext context) {
    final state = StorageService.userStateNotifier.value;
    final String mensaje = state == UserState.guest
        ? 'Hazte Premium para acceder al historial de consumo.'
        : 'Tu suscripción no está activa. Paga el mes para desbloquear el historial.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: const Color(0xFF0B2F6B),
        behavior: SnackBarBehavior.floating,
        action: state == UserState.guest
            ? SnackBarAction(
                label: 'Ir a login',
                textColor: Colors.white,
                onPressed: () => Navigator.pushNamed(context, '/login'),
              )
            : SnackBarAction(
                label: 'Pagar',
                textColor: Colors.white,
                onPressed: () => Navigator.pushNamed(context, '/subscription'),
              ),
      ),
    );
  }

  void _showResetBlockedSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No se pudo confirmar el reset del medidor. Asegúrate de estar en la misma red del medidor para eliminarlo.',
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Botón circular de acción
// ─────────────────────────────────────────────────────────────────────────────
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
      opacity: (onTap == null && !isLocked) ? 0.4 : 1.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: isLocked
                        ? backgroundColor.withOpacity(0.45)
                        : backgroundColor,
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  if (isLocked)
                    Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock,
                        size: 11,
                        color: Color(0xFF0B2F6B),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isLocked
                      ? Colors.black38
                      : MeterDashboardScreen.primaryBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainter de la dona
// ─────────────────────────────────────────────────────────────────────────────
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

    final availableFraction = (percentAvailable.clamp(0.0, 100.0)) / 100.0;
    final totalSweep = 360.0 - gapDegrees * 2;
    final availableSweep = totalSweep * availableFraction;
    final consumedSweep = totalSweep * (1.0 - availableFraction);
    final startAngle = _toRad(-90.0 + gapDegrees / 2);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    paint.color = availableColor;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      _toRad(availableSweep),
      false,
      paint,
    );

    paint.color = consumedColor;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + _toRad(availableSweep + gapDegrees),
      _toRad(consumedSweep),
      false,
      paint,
    );
  }

  double _toRad(double deg) => deg * math.pi / 180.0;

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.percentAvailable != percentAvailable ||
      old.availableColor != availableColor ||
      old.consumedColor != consumedColor;
}
