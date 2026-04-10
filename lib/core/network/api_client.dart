import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../constants/app_constants.dart';
import '../errors/app_exceptions.dart';

/// Cliente HTTP para comunicación con la API
class ApiClient {
  final http.Client _client;
  String? _authToken;

  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  /// Establece el token de autenticación
  void setAuthToken(String token) {
    _authToken = token;
  }

  /// Limpia el token de autenticación
  void clearAuthToken() {
    _authToken = null;
  }

  /// Headers por defecto
  Map<String, String> get _headers {
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: ApiConstants.contentType,
      HttpHeaders.acceptHeader: ApiConstants.contentType,
    };

    if (_authToken != null) {
      headers[ApiConstants.authorization] = '${ApiConstants.bearer} $_authToken';
    }

    return headers;
  }

  /// Construye la URL completa
  Uri _buildUri(String endpoint, [Map<String, dynamic>? queryParams]) {
    final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
    if (queryParams != null && queryParams.isNotEmpty) {
      return uri.replace(queryParameters: queryParams.map(
        (key, value) => MapEntry(key, value.toString()),
      ));
    }
    return uri;
  }

  /// GET request
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParams,
  }) async {
    try {
      final response = await _client
          .get(_buildUri(endpoint, queryParams), headers: _headers)
          .timeout(AppConstants.connectionTimeout);

      return _handleResponse(response);
    } on SocketException {
      throw NetworkException(message: 'Sin conexión a internet');
    } on HttpException {
      throw NetworkException(message: 'Error de conexión');
    }
  }

  /// POST request
  Future<dynamic> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParams,
  }) async {
    try {
      final response = await _client
          .post(
            _buildUri(endpoint, queryParams),
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(AppConstants.connectionTimeout);

      return _handleResponse(response);
    } on SocketException {
      throw NetworkException(message: 'Sin conexión a internet');
    } on HttpException {
      throw NetworkException(message: 'Error de conexión');
    }
  }

  /// PUT request
  Future<dynamic> put(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParams,
  }) async {
    try {
      final response = await _client
          .put(
            _buildUri(endpoint, queryParams),
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(AppConstants.connectionTimeout);

      return _handleResponse(response);
    } on SocketException {
      throw NetworkException(message: 'Sin conexión a internet');
    } on HttpException {
      throw NetworkException(message: 'Error de conexión');
    }
  }

  /// DELETE request
  Future<dynamic> delete(
    String endpoint, {
    Map<String, dynamic>? queryParams,
  }) async {
    try {
      final response = await _client
          .delete(_buildUri(endpoint, queryParams), headers: _headers)
          .timeout(AppConstants.connectionTimeout);

      return _handleResponse(response);
    } on SocketException {
      throw NetworkException(message: 'Sin conexión a internet');
    } on HttpException {
      throw NetworkException(message: 'Error de conexión');
    }
  }

  /// Maneja la respuesta de la API
  dynamic _handleResponse(http.Response response) {
    final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;

    switch (response.statusCode) {
      case 200:
      case 201:
        return body;
      case 204:
        return null;
      case 400:
        throw ValidationException(
          message: body?['message'] ?? 'Solicitud inválida',
        );
      case 401:
        throw AuthException(message: body?['message'] ?? 'No autorizado');
      case 403:
        throw AuthException(message: body?['message'] ?? 'Acceso denegado');
      case 404:
        throw ServerException(
          message: body?['message'] ?? 'Recurso no encontrado',
          statusCode: 404,
        );
      case 500:
      default:
        throw ServerException(
          message: body?['message'] ?? 'Error del servidor',
          statusCode: response.statusCode,
        );
    }
  }

  /// Cierra el cliente
  void dispose() {
    _client.close();
  }
}
