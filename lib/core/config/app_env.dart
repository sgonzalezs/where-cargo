/// Variables de entorno inyectadas en tiempo de compilación.
///
/// Se definen en `config/env.json` (no versionado) y se pasan con:
/// `flutter run --dart-define-from-file=config/env.json`
/// Ver `config/env.example.json` para las claves esperadas.
class AppEnv {
  AppEnv._();

  /// API key de Google Places API (New) para buscar estaciones.
  static const String googlePlacesApiKey =
      String.fromEnvironment('GOOGLE_PLACES_API_KEY');

  /// API key de Open Charge Map.
  static const String ocmApiKey = String.fromEnvironment('OCM_API_KEY');

  /// Claves que faltan en esta compilación. Si no está vacía, la app se
  /// compiló sin `--dart-define-from-file=config/env.json`.
  static List<String> get missingKeys => [
        if (googlePlacesApiKey.isEmpty) 'GOOGLE_PLACES_API_KEY',
        if (ocmApiKey.isEmpty) 'OCM_API_KEY',
      ];
}
