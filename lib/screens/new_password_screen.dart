import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../widgets/auth_card_scaffold.dart';

class NewPasswordScreen extends StatefulWidget {
  final String email;
  final String code;
  const NewPasswordScreen({super.key, required this.email, required this.code});

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _repeatPasswordController = TextEditingController();
  bool _isLoading = false;

  // Variables de estado explícitas en vez de getters.
  // Esto garantiza que se actualicen exactamente cuando llamamos
  // a _validatePassword() y evita cualquier ambigüedad sobre cuándo
  // Flutter reconstruye el widget.
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasNumber = false;

  static final RegExp _uppercaseRegExp = RegExp(r'[A-Z]');
  static final RegExp _numberRegExp = RegExp(r'[0-9]');

  @override
  void initState() {
    super.initState();
    // Escucha cambios en el controller directamente, en vez de depender
    // solo del onChanged del TextField (más robusto ante autofill, paste, etc.)
    _newPasswordController.addListener(_validatePassword);
  }

  void _validatePassword() {
    final text = _newPasswordController.text;
    final newHasMinLength = text.length >= 8;
    final newHasUppercase = _uppercaseRegExp.hasMatch(text);
    final newHasNumber = _numberRegExp.hasMatch(text);

    // Solo llamamos setState si algo realmente cambió, para evitar
    // rebuilds innecesarios en cada tecla presionada.
    if (newHasMinLength != _hasMinLength ||
        newHasUppercase != _hasUppercase ||
        newHasNumber != _hasNumber) {
      setState(() {
        _hasMinLength = newHasMinLength;
        _hasUppercase = newHasUppercase;
        _hasNumber = newHasNumber;
      });
    }
  }

  // POST /auth/checkemailpwd
  // Body: { email, code, pwd }
  Future<void> _handleConfirm() async {
    if (_newPasswordController.text != _repeatPasswordController.text) {
      _showErrorDialog('Las contraseñas no coinciden.');
      return;
    }
    if (!_hasMinLength || !_hasUppercase || !_hasNumber) {
      _showErrorDialog('La contraseña no cumple los requisitos mínimos.');
      return;
    }

    setState(() => _isLoading = true);
    final url = Uri.parse('http://localhost:3000/auth/checkemailpwd');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': widget.email,
          'code': widget.code,
          'pwd': _newPasswordController.text,
        }),
      );

      if (!mounted) return;

      // El backend puede responder 200 o 201 según la implementación;
      // ambos indican que la contraseña se actualizó correctamente.
      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada con éxito')),
        );
        // Regresa al Login limpiando todo el stack de navegación
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      } else if (response.statusCode == 400) {
        String msg = 'Código incorrecto o expirado. Solicita un nuevo código.';
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data['message'] != null) msg = data['message'].toString();
        } catch (_) {}
        _showErrorDialog(msg);
      } else {
        _showErrorDialog('Error en el servidor. Código: ${response.statusCode}');
      }
    } catch (_) {
      _showErrorDialog('No se pudo conectar al servidor. Verifica tu red y el backend.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _newPasswordController.removeListener(_validatePassword);
    _newPasswordController.dispose();
    _repeatPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthCardScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Botón de regreso a la pantalla de token
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_ios, size: 14, color: AuthCardScaffold.primaryBlue),
                  SizedBox(width: 4),
                  Text(
                    'Volver',
                    style: TextStyle(
                      color: AuthCardScaffold.primaryBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Usuario verificado correctamente',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AuthCardScaffold.primaryBlue,
            ),
          ),
          const Text(
            'Escriba una nueva contraseña',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AuthCardScaffold.primaryBlue,
            ),
          ),
          const SizedBox(height: 20),
          const Text('Nueva contraseña', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          TextField(
            controller: _newPasswordController,
            obscureText: true,
            decoration: InputDecoration(
              hintText: '**********',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Repita la nueva contraseña', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          TextField(
            controller: _repeatPasswordController,
            obscureText: true,
            decoration: InputDecoration(
              hintText: '**********',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'La contraseña debe tener:',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          _Requisito(cumplido: _hasMinLength, texto: 'Mínimo 8 caracteres'),
          _Requisito(cumplido: _hasUppercase, texto: 'Al menos una mayúscula'),
          _Requisito(cumplido: _hasNumber, texto: 'Al menos un número'),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isLoading ? null : _handleConfirm,
              child: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Confirmar', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Requisito extends StatelessWidget {
  final bool cumplido;
  final String texto;
  const _Requisito({required this.cumplido, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            cumplido ? Icons.check_circle : Icons.circle_outlined,
            size: 14,
            color: cumplido ? Colors.green : Colors.black38,
          ),
          const SizedBox(width: 6),
          Text(texto, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}