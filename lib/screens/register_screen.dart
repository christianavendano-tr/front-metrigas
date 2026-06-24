import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/registration_service.dart';
import '../widgets/auth_card_scaffold.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await RegistrationService.signUp(
        username: _nameController.text.trim(),
        email: _emailController.text.trim(),
        age: int.parse(_ageController.text.trim()),
        pwd: _passwordController.text,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final responseData = response.data;
        String successMessage = responseData['message'] ?? 'Usuario registrado con éxito.';

        RegistrationService.setTemporaryEmail(_emailController.text.trim());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(successMessage), backgroundColor: Colors.green),
          );
          Navigator.pushNamed(context, '/verify');
        }
      }
    } on DioException catch (e) {
      final errorMsg = e.response?.data['message'] ?? 'Error al registrar la cuenta.';
      _showError(errorMsg.toString());
    } catch (e) {
      _showError('No se pudo conectar con el servidor de Metrigas.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthCardScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false),
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
            const Center(
              child: Text(
                'Por favor llene todos los campos\npara completar su registro',
                textAlign: TextAlign.center,
                style: TextStyle(color: AuthCardScaffold.primaryBlue, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 20),
            _buildLabel('Nombre'),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(hintText: 'nombre', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? 'Campo requerido' : null,
            ),
            const SizedBox(height: 12),
            _buildLabel('Edad'),
            TextFormField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'edad', border: OutlineInputBorder()),
              validator: (v) {
                if (v!.isEmpty) return 'Campo requerido';
                if (int.tryParse(v) == null) return 'Ingrese una edad válida';
                return null;
              },
            ),
            const SizedBox(height: 12),
            _buildLabel('Correo Electrónico'),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'correoelectrónico@dominio.com', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty || !v.contains('@') ? 'Ingrese un correo válido' : null,
            ),
            const SizedBox(height: 12),
            _buildLabel('Contraseña'),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                hintText: 'contraseña',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) => v!.length < 6 ? 'Mínimo 6 caracteres' : null,
            ),
            const SizedBox(height: 12),
            _buildLabel('Confirmar Contraseña'),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              decoration: InputDecoration(
                hintText: 'repita contraseña',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ),
              validator: (v) {
                if (v!.isEmpty) return 'Confirme su contraseña';
                if (v != _passwordController.text) return 'Las contraseñas no coinciden';
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  disabledBackgroundColor: Colors.grey,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isLoading ? null : _submitRegister,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Confirmar', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}