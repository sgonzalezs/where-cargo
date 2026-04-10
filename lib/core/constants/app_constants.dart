/// Constantes generales de la aplicación
class AppConstants {
  AppConstants._();

  static const String appName = 'Where Cargo';
  static const String appVersion = '1.0.0';
  
  // Configuración de mapa
  static const double defaultLatitude = 4.7110; // Bogotá, Colombia
  static const double defaultLongitude = -74.0721;
  static const double defaultZoom = 12.0;
  
  // Configuración de búsqueda
  static const double defaultSearchRadiusKm = 10.0;
  static const int maxSearchResults = 50;
  
  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  
  // Cache
  static const Duration cacheValidDuration = Duration(hours: 1);
}
