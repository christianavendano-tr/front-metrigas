// lib/services/session_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart'; // <-- Importación indispensable

class SessionService {
  static const String _tokenKey = 'jwt_access_token';
  static String? _accessToken;

  /// Gets token from memory when starting app
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_tokenKey);
  }

  /// Saves the token
  static Future<void> saveToken(String token) async {
    _accessToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static String? getToken() {
    return _accessToken;
  }

  /// Verifies if current token is active
  static bool hasSession() {
    if (_accessToken == null || _accessToken!.isEmpty) return false;

    try {
      // If JwtDecoder says token is expired, returns false
      return !JwtDecoder.isExpired(_accessToken!);
    } catch (e) {
      // If token is corrupt also returns false
      return false;
    }
  }

  /// Deletes token from device
  static Future<void> clearSession() async {
    _accessToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}