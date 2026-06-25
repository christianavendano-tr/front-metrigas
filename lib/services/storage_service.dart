// lib/services/storage_service.dart
import 'package:flutter/material.dart';

enum UserState { guest, premiumActive, premiumInactive }

class StorageService {
  static bool _isFirstTime = true;
  static String? _userName;

  // ValueNotifier notificará automáticamente a las pantallas cuando el estado cambie
  static final ValueNotifier<UserState> userStateNotifier = ValueNotifier<UserState>(UserState.guest);

  static Future<void> init() async {
    // Aquí leerías las SharedPreferences reales en el futuro
  }

  static bool get isFirstTime => _isFirstTime;
  
  static Future<void> setFirstTimeCompleted() async {
    _isFirstTime = false;
  }

  static UserState get currentUserState => userStateNotifier.value;
  static String? get userName => _userName;

  static void setMockState(UserState state, {String? name}) {
    _userName = name;
    userStateNotifier.value = state; // Dispara la actualización reactiva en la UI
  }

  static Future<void> clearSession() async {
    _userName = null;
    userStateNotifier.value = UserState.guest; // Devuelve la app a modo invitado al instante
    // AQUÍ: Tus devs limpian las llaves de seguridad locales (JWT, caché, etc.)
  }
}