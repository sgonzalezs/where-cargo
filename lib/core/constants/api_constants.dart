/// Constantes de la API
class ApiConstants {
  ApiConstants._();

  // Base URL - cambiar según el ambiente
  static const String baseUrl = 'http://localhost:3000/api';
  static const String apiVersion = 'v1';
  
  // Endpoints
  static const String stations = '/stations';
  static const String stationDetail = '/stations/{id}';
  static const String nearbyStations = '/stations/nearby';
  static const String auth = '/auth';
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String user = '/user';
  static const String favorites = '/favorites';
  static const String vehicles = '/vehicles';
  
  // Headers
  static const String contentType = 'application/json';
  static const String authorization = 'Authorization';
  static const String bearer = 'Bearer';
}
