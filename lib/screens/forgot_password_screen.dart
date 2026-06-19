import 'package:flutter/material.dart';
import '../widgets/auth_card_scaffold.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleSendLink() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // TODO: reemplazar por la llamada real a tu backend, por ejemplo:
    // final url = Uri.parse('http://localhost:3000/auth/forgot-password');
    // await http.post(url,
    //   headers: {'Content-Type': 'application/json'},
    //   body: jsonEncode({'email': _emailController.text.trim()}),
    // );
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pushNamed(
        context,
        '/verify-token',
        arguments: _emailController.text.trim(),
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthCardScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Recuperar contraseña',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AuthCardScaffold.primaryBlue,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Para recuperar tu contraseña enviaremos un código de '
              'verificación al correo asociado a tu cuenta. Esto nos '
              'ayudará a verificar tu identidad',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AuthCardScaffold.primaryBlue),
            ),
            const SizedBox(height: 20),
            const Text('Correo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'correoelectrónico@dominio.com',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'El correo no puede estar vacío';
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isLoading ? null : _handleSendLink,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Enviar enlace de recuperación'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}