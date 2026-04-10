import 'package:flutter/services.dart';

/// Servicio para integración con apps de navegación
class NavigationService {
  /// Abre Google Maps con la ruta hacia las coordenadas especificadas
  Future<bool> openGoogleMaps({
    required double destinationLat,
    required double destinationLng,
    String? destinationName,
    double? originLat,
    double? originLng,
  }) async {
    final String url;
    
    if (originLat != null && originLng != null) {
      url = 'https://www.google.com/maps/dir/'
          '$originLat,$originLng/'
          '$destinationLat,$destinationLng';
    } else {
      url = 'https://www.google.com/maps/dir/?api=1'
          '&destination=$destinationLat,$destinationLng';
    }
    
    return _launchUrl(url);
  }

  /// Abre Waze con la ruta hacia las coordenadas especificadas
  Future<bool> openWaze({
    required double destinationLat,
    required double destinationLng,
  }) async {
    final url = 'https://waze.com/ul?ll=$destinationLat,$destinationLng&navigate=yes';
    return _launchUrl(url);
  }

  /// Abre Apple Maps (solo iOS)
  Future<bool> openAppleMaps({
    required double destinationLat,
    required double destinationLng,
    String? destinationName,
  }) async {
    final query = destinationName != null 
        ? '&q=${Uri.encodeComponent(destinationName)}'
        : '';
    final url = 'https://maps.apple.com/?daddr=$destinationLat,$destinationLng$query';
    return _launchUrl(url);
  }

  /// Genera opciones de navegación disponibles
  List<NavigationOption> getNavigationOptions({
    required double destinationLat,
    required double destinationLng,
    String? destinationName,
  }) {
    return [
      NavigationOption(
        name: 'Google Maps',
        icon: 'google_maps',
        onTap: () => openGoogleMaps(
          destinationLat: destinationLat,
          destinationLng: destinationLng,
          destinationName: destinationName,
        ),
      ),
      NavigationOption(
        name: 'Waze',
        icon: 'waze',
        onTap: () => openWaze(
          destinationLat: destinationLat,
          destinationLng: destinationLng,
        ),
      ),
      NavigationOption(
        name: 'Apple Maps',
        icon: 'apple_maps',
        onTap: () => openAppleMaps(
          destinationLat: destinationLat,
          destinationLng: destinationLng,
          destinationName: destinationName,
        ),
      ),
    ];
  }

  /// Abre el mapa predeterminado del sistema
  Future<bool> openDefaultMap({
    required double destinationLat,
    required double destinationLng,
    String? destinationName,
  }) async {
    // Intentar primero con la app de mapas del sistema
    final geoUrl = 'geo:$destinationLat,$destinationLng';
    
    if (!await _launchUrl(geoUrl)) {
      // Fallback a Google Maps web
      return openGoogleMaps(
        destinationLat: destinationLat,
        destinationLng: destinationLng,
        destinationName: destinationName,
      );
    }
    
    return true;
  }

  /// Copia las coordenadas al portapapeles
  Future<void> copyCoordinates({
    required double lat,
    required double lng,
  }) async {
    await Clipboard.setData(ClipboardData(text: '$lat, $lng'));
  }

  /// Genera un enlace compartible
  String generateShareLink({
    required double lat,
    required double lng,
    String? name,
  }) {
    final encodedName = name != null ? Uri.encodeComponent(name) : '';
    return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng${name != null ? "&query_place_id=$encodedName" : ""}';
  }

  Future<bool> _launchUrl(String url) async {
    // TODO: Implementar usando url_launcher package
    // Por ahora retornamos false ya que necesitamos agregar la dependencia
    // return await launchUrl(Uri.parse(url));
    return false;
  }
}

/// Modelo para opciones de navegación
class NavigationOption {
  final String name;
  final String icon;
  final Future<bool> Function() onTap;

  const NavigationOption({
    required this.name,
    required this.icon,
    required this.onTap,
  });
}
