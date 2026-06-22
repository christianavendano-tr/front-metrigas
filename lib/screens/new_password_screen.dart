import 'package:flutter/material.dart';
import '../widgets/auth_card_scaffold.dart';

class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _repeatPasswordController = TextEditingController();
  bool _isLoading = false;

  bool get _hasMinLength => _newPasswordController.text.length >= 8;
  bool get _hasUppercase => _newPasswordController.text.contains(RegExp(r'[A-Z]'));
  bool get _hasNumber => _newPasswordController.text.contains(RegExp(r'[0-9]'));

  Future<void> _handleConfirm() async {
    if (_newPasswordController.text != _repeatPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Las contraseñas no coinciden')),
      );
      return;
    }
    if (!_hasMinLength || !_hasUppercase || !_hasNumber) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La contraseña no cumple los requisitos')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // TODO: reemplazar por la llamada real a tu backend, por ejemplo:
    // final url = Uri.parse('http://localhost:3000/auth/reset-password');
    // await http.post(url,
    //   headers: {'Content-Type': 'application/json'},
    //   body: jsonEncode({'password': _newPasswordController.text}),
    // );
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contraseña actualizada correctamente')),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _repeatPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthCardScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Usuario verificado correctamente',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AuthCardScaffold.primaryBlue,
            ),
          ),
          const Text(
            'Escriba una nueva contraseña',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AuthCardScaffold.primaryBlue,
            ),
          ),
          const SizedBox(height: 18),
          const Text('Nueva contraseña', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          TextField(
            controller: _newPasswordController,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('La contraseña debe tener:', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          _Requisito(cumplido: _hasMinLength, texto: 'Mínimo 8 caracteres'),
          _Requisito(cumplido: _hasUppercase, texto: 'Al menos una mayúscula'),
          _Requisito(cumplido: _hasNumber, texto: 'Al menos un número'),
          const SizedBox(height: 20),
          SizedBox(
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

class _Requisito extends StatelessWidget {
  final bool cumplido;
  final String texto;
  const _Requisito({required this.cumplido, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
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