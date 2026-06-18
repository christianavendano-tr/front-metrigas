// lib/services/session_service.dart

class SessionService {
  // Variable en memoria privada para almacenar el token JWT
  static String? _accessToken;

  // Método para guardar el token desde la pantalla de Login
  static void saveToken(String token) {
    _accessToken = token;
  }

  // Método para obtener el token desde cualquier parte de la app
  static String? getToken() {
    return _accessToken;
  }

  // Método para verificar si el usuario tiene una sesión activa
  static bool hasSession() {
    return _accessToken != null;
  }

  // Método para cerrar sesión borrando la memoria
  static void clearSession() {
    _accessToken = null;
  }
}