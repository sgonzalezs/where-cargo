/// Excepciones personalizadas de la aplicación
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  AppException({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  String toString() => 'AppException: $message (code: $code)';
}

/// Excepción de red
class NetworkException extends AppException {
  NetworkException({
    required super.message,
    super.code,
    super.originalError,
  });
}

/// Excepción de servidor
class ServerException extends AppException {
  final int? statusCode;

  ServerException({
    required super.message,
    super.code,
    super.originalError,
    this.statusCode,
  });
}

/// Excepción de autenticación
class AuthException extends AppException {
  AuthException({
    required super.message,
    super.code,
    super.originalError,
  });
}

/// Excepción de caché
class CacheException extends AppException {
  CacheException({
    required super.message,
    super.code,
    super.originalError,
  });
}

/// Excepción de ubicación
class LocationException extends AppException {
  LocationException({
    required super.message,
    super.code,
    super.originalError,
  });
}

/// Excepción de validación
class ValidationException extends AppException {
  final Map<String, String>? fieldErrors;

  ValidationException({
    required super.message,
    super.code,
    super.originalError,
    this.fieldErrors,
  });
}
