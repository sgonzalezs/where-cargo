/// Constantes generales de la aplicación
class AppConstants {
  AppConstants._();

  static const String appName = 'Where Cargo';
  // La versión de la app se define solo en pubspec.yaml

  // Publicada con GitHub Pages desde docs/privacy-policy.html
  static const String privacyPolicyUrl =
      'https://sgonzalezs.github.io/where-cargo/privacy-policy.html';

  // Configuración de mapa: ubicación por defecto Medellín, Colombia
  static const String defaultLocationLabel = 'Medellín (por defecto)';
  static const double defaultLatitude = 6.2442;
  static const double defaultLongitude = -75.5812;
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
