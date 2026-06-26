// lib/services/storage_service.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_service.dart';

enum UserState { guest, premiumActive, premiumInactive }

class StorageService {
  static const String _firstTimeKey = 'is_first_time_app';
  static const String _userStateKey = 'persisted_user_state';
  static const String _userNameKey = 'persisted_user_name';
  static const String _userEmailKey = 'persisted_user_email';

  static bool _isFirstTime = true;
  static String? _userName;
  static String? _userEmail;

  static final ValueNotifier<UserState> userStateNotifier = ValueNotifier<UserState>(UserState.guest);

  /// Restaura todo el estado del usuario al arrancar la app
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Recuperar Flag de Bienvenida
    _isFirstTime = prefs.getBool(_firstTimeKey) ?? true;
    
    // 2. Recuperar Datos del Perfil
    _userName = prefs.getString(_userNameKey);
    _userEmail = prefs.getString(_userEmailKey);
    
    // 3. Recuperar Estado de Suscripción
    final savedStateStr = prefs.getString(_userStateKey);
    UserState estadoRecuperado = UserState.guest;

    if (savedStateStr != null) {
      estadoRecuperado = UserState.values.firstWhere(
        (e) => e.toString() == savedStateStr,
        orElse: () => UserState.guest,
      );
    }

    // =======================================================================
    // 🚨 CONTROL DE EXPIRACIÓN INTERNO Y SEGURO:
    // Si el usuario supuestamente estaba logueado pero el token ya caducó,
    // borramos la sesión en el disco inmediatamente y lo volvemos invitado.
    // =======================================================================
    if (estadoRecuperado != UserState.guest && !SessionService.hasSession()) {
      _userName = null;
      _userEmail = null;
      estadoRecuperado = UserState.guest;
      
      await prefs.remove(_userStateKey);
      await prefs.remove(_userNameKey);
      await prefs.remove(_userEmailKey);
      await SessionService.clearSession();
    }

    // Asignamos el valor final verificado al notificador
    userStateNotifier.value = estadoRecuperado;
  }

  static bool get isFirstTime => _isFirstTime;
  static String? get userName => _userName;
  static String? get userEmail => _userEmail; 
  static UserState get currentUserState => userStateNotifier.value;
  
  static Future<void> setFirstTimeCompleted() async {
    _isFirstTime = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstTimeKey, false);
  }

  static Future<void> setMockState(UserState state, {String? name, String? email}) async {
    _userName = name ?? _userName;
    if (email != null) _userEmail = email;
    userStateNotifier.value = state;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userStateKey, state.toString());
    if (_userName != null) await prefs.setString(_userNameKey, _userName!);
    if (_userEmail != null) await prefs.setString(_userEmailKey, _userEmail!);
  }

  static Future<void> clearSession() async {
    _userName = null;
    _userEmail = null;
    userStateNotifier.value = UserState.guest;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userStateKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userEmailKey);
    
    await SessionService.clearSession();
  }
}