import 'package:dio/dio.dart';
import 'package:front_metrigas/services/session_service.dart';

class RegistrationService {
  static final String baseUrl = SessionService.getURL();

  static const String premiumPriceId = 'price_1QJ45zRFZd5tQ6sqTU3fSPET';

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 3),
  ))
    ..interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true, // Para ver el JSON exacto en consola
      responseHeader: false,
      responseBody: true, // Para ver la respuesta de Nest.js
      error: true,
    ));

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

  /// 1. POST /auth/signup
  static Future<Response> signUp({
    required String username,
    required String email,
    required int age,
    required String pwd,
  }) async {
    return await _dio.post(
      '/auth/signup',
      data: {
        'email': email,
        'username': username,
        'age': age,
        'pwd': pwd,
      },
    );
  }

  /// 2. POST /auth/verify
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

  /// 3. POST /auth/paymethods
  static Future<Response> createSubscription({
    required String email,
  }) async {
    return await _dio.post(
      '/auth/paymethods',
      data: {
        'email': email,
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          if (_temporaryJwtToken != null)
            'Authorization': 'Bearer $_temporaryJwtToken',
        },
      ),
    );
  }
}
