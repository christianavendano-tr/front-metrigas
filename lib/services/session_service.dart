// lib/services/session_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart'; // <-- Importación indispensable

class SessionService {
  static const String _tokenKey = 'jwt_access_token';
  static String? _accessToken;

  /// Carga el token guardado del disco a la memoria RAM al arrancar la app
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_tokenKey);
  }

  /// Guarda el token de forma persistente
  static Future<void> saveToken(String token) async {
    _accessToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static String? getToken() {
    return _accessToken;
  }

  /// Verifica de forma segura si el token actual sigue vigente
  static bool hasSession() {
    if (_accessToken == null || _accessToken!.isEmpty) return false;

    try {
      // Si JwtDecoder dice que está expirado, retorna false
      return !JwtDecoder.isExpired(_accessToken!);
    } catch (e) {
      // Si el token está corrupto o mal formado, lo toma como sesión no válida
      return false;
    }
  }

  /// Borra el token por completo del teléfono
  static Future<void> clearSession() async {
    _accessToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}