import 'package:dio/dio.dart';

class RegistrationService {
  static const String baseUrl = 'http://localhost:3000';
  
  // MODIFICADO: Formato alfanumérico válido para saltar el class-validator de Nest.js
  static const String premiumPriceId = 'price_1QJ45zRFZd5tQ6sqTU3fSPET';

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 3),
  ))..interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true, // Para ver el JSON exacto en consola
      responseHeader: false,
      responseBody: true, // Para ver la respuesta de Nest.js
      error: true,
    ));

  // Estado transicional en memoria RAM
  static String? _temporaryEmail;
  static String? _temporaryJwtToken;

  static String? get temporaryEmail => _temporaryEmail;
  static String? get temporaryJwtToken => _temporaryJwtToken;

  static void setTemporaryEmail(String email) => _temporaryEmail = email;
  static void setTemporaryJwtToken(String token) => _temporaryJwtToken = token;
  
  static void clearRegistrationState() {
    _temporaryEmail = null;
    _temporaryJwtToken = null;
  }

  /// 1. POST /auth/signup - ¡ENDPOINT CORREGIDO AQUÍ!
  static Future<Response> signUp({
    required String username,
    required String email,
    required int age,
    required String pwd,
  }) async {
    return await _dio.post(
      '/auth/signup', // Antes decía '/signup'
      data: {
        'email': email,
        'username': username,
        'age': age,
        'pwd': pwd,
      },
    );
  }

  /// 2. POST /auth/verify - Validación OTP
  static Future<Response> verifyCode({
    required String email,
    required String code,
  }) async {
    return await _dio.post(
      '/auth/verify',
      data: {
        'email': email,
        'code': code,
      },
    );
  }
  
  /// 3. POST /auth/paymethods - Endpoint de suscripción mapeado con Stripe Checkout
  static Future<Response> createSubscription({
    required String email,
    required String priceId,
  }) async {
    return await _dio.post(
      '/auth/paymethods', 
      data: {
        'userEmail': email,
        'priceId': priceId,
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          if (_temporaryJwtToken != null) 'Authorization': 'Bearer $_temporaryJwtToken',
        },
      ),
    );
  }
}