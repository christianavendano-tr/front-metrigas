import 'package:flutter/material.dart';
import '../widgets/auth_card_scaffold.dart';

class VerifyTokenScreen extends StatefulWidget {
  /// Permite pasar el correo directamente al construir el widget.
  /// Si no se pasa, se intenta leer desde los argumentos de la ruta
  /// (Navigator.pushNamed(context, '/verify-token', arguments: email)).
  final String? email;
  const VerifyTokenScreen({super.key, this.email});

  @override
  State<VerifyTokenScreen> createState() => _VerifyTokenScreenState();
}

class _VerifyTokenScreenState extends State<VerifyTokenScreen> {
  final List<TextEditingController> _controllers =
      List.generate(5, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(5, (_) => FocusNode());
  bool _isLoading = false;

  String get _email {
    if (widget.email != null && widget.email!.isNotEmpty) return widget.email!;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args.isNotEmpty) return args;
    return 'usuario@ejemplo.com';
  }

  Future<void> _handleConfirm() async {
    final token = _controllers.map((c) => c.text).join();
    if (token.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa los 5 dígitos del token')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // TODO: reemplazar por la llamada real a tu backend, por ejemplo:
    // final url = Uri.parse('http://localhost:3000/auth/verify-token');
    // await http.post(url,
    //   headers: {'Content-Type': 'application/json'},
    //   body: jsonEncode({'email': _email, 'token': token}),
    // );
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pushNamed(context, '/new-password');
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthCardScaffold(
      child: Column(
        children: [
          const Text(
            'Escriba su token de verificacion',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AuthCardScaffold.primaryBlue,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Enviamos un código de 5 dígitos a\n$_email',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AuthCardScaffold.primaryBlue),
          ),
          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Token:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (index) {
              return SizedBox(
                width: 48,
                height: 52,
                child: TextField(
                  controller: _controllers[index],
                  focusNode: _focusNodes[index],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  decoration: InputDecoration(
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (value) {
                    if (value.isNotEmpty && index < 4) {
                      _focusNodes[index + 1].requestFocus();
                    } else if (value.isEmpty && index > 0) {
                      _focusNodes[index - 1].requestFocus();
                    }
                  },
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isLoading ? null : _handleConfirm,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Confirmar'),
            ),
          ),
        ],
      ),
    );
  }
}