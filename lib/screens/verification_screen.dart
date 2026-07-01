import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/registration_service.dart';
import '../widgets/auth_card_scaffold.dart';
import 'new_password_screen.dart';

class VerificationScreen extends StatefulWidget {
  /// Mail were the code was sent. if provided, this screen takes
  /// for granted that the user comes from "forgot passweord screen and only validates the code
  /// and passes it to NewPasswordScreen, where the new psw is defined.
  /// If omitted, it follows the original register flux (POST /auth/verify)
  /// using RegistrationService.temporaryEmail.
  final String? email;

  const VerificationScreen({super.key, this.email});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;

  // true => forgot pwd flux
  // false => register user flux
  bool get _isPasswordRecovery => widget.email != null;

  String? get _targetEmail => widget.email ?? RegistrationService.temporaryEmail;

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyToken() async {
    if (_isLoading) return;

    final pin = _controllers.map((c) => c.text).join();

    if (pin.length < 6) {
      _showSnackBar('Por favor complete el código de 6 caracteres.', Colors.orange);
      return;
    }

    final email = _targetEmail;
    if (email == null) {
      _showSnackBar('Falta referencia del correo electrónico.', Colors.red);
      return;
    }

    if (_isPasswordRecovery) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NewPasswordScreen(email: email, code: pin),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _verifyForRegistration(email: email, pin: pin);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Register flux: POST /auth/verify
  /// Validates de code, if its incorrect the backend deletes the user
  /// from de database
  Future<void> _verifyForRegistration({required String email, required String pin}) async {
    try {
      final response = await RegistrationService.verifyCode(email: email, code: pin);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          _showSnackBar('¡Cuenta verificada con éxito!', Colors.green);
          Navigator.pushNamedAndRemoveUntil(context, '/subscription', (route) => false);
        }
      }
    } on DioException catch (e) {
      final errorData = e.response?.data;

      if (errorData != null && errorData['message'] == "La cuenta ya está verificada") {
        if (mounted) {
          _showSnackBar('¡Cuenta lista! Procediendo...', Colors.green);
          Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        }
        return;
      }

      final errorMsg = errorData?['message'] ?? 'Código incorrecto o expirado.';
      _showSnackBar(errorMsg.toString(), Colors.red);
    } catch (_) {
      _showSnackBar('Error de conexión con el servidor de Metrigas.', Colors.red);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final targetEmail = _targetEmail ?? 'tu correo registrado';

    return AuthCardScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Escriba su token de verificación', style: TextStyle(color: AuthCardScaffold.primaryBlue, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Text(
            'Enviamos un código de 6 caracteres a\n$targetEmail',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF0044CC), fontSize: 14, height: 1.3),
          ),
          const SizedBox(height: 25),
          const Align(alignment: Alignment.centerLeft, child: Text('Token:', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(6, (index) {
              return SizedBox(
                width: 42,
                height: 50,
                child: TextField(
                  controller: _controllers[index],
                  focusNode: _focusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  decoration: const InputDecoration(
                    counterText: "",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (value) {
                    if (value.isNotEmpty && index < 5) {
                      FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
                    } else if (value.isEmpty && index > 0) {
                      FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
                    }
                  },
                ),
              );
            }),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                disabledBackgroundColor: Colors.grey,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isLoading ? null : _verifyToken,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Confirmar', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}