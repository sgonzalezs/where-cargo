import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/constants/app_constants.dart';

/// Servicio singleton para gestionar la ubicación del usuario
/// Compartido entre todas las páginas de la app
class LocationService extends ChangeNotifier {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Ubicación actual
  double? _latitude;
  double? _longitude;
  String _locationLabel = AppConstants.defaultLocationLabel;
  bool _isLocating = false;
  bool _hasCustomLocation = false;

  // Ubicación por defecto (ver AppConstants)
  static const double defaultLatitude = AppConstants.defaultLatitude;
  static const double defaultLongitude = AppConstants.defaultLongitude;

  // Getters
  double get latitude => _latitude ?? defaultLatitude;
  double get longitude => _longitude ?? defaultLongitude;
  String get locationLabel => _locationLabel;
  bool get isLocating => _isLocating;
  bool get hasCustomLocation => _hasCustomLocation;
  bool get hasLocation => _latitude != null && _longitude != null;

  /// Antigüedad máxima para confiar en la última posición conocida.
  static const Duration _lastKnownMaxAge = Duration(hours: 2);

  /// Usa la última posición conocida del dispositivo, que está disponible al
  /// instante (no enciende el GPS). Sirve para empezar a cargar estaciones
  /// mientras se obtiene la posición precisa con [getCurrentLocation].
  ///
  /// No pide permisos: si aún no se otorgaron, retorna `false`.
  Future<bool> useLastKnownLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return false;
      if (DateTime.now().difference(position.timestamp) > _lastKnownMaxAge) {
        return false;
      }

      _latitude = position.latitude;
      _longitude = position.longitude;
      _locationLabel = 'Mi ubicación';
      _hasCustomLocation = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Sin última ubicación conocida: $e');
      return false;
    }
  }

  /// Obtiene la ubicación actual del dispositivo
  Future<bool> getCurrentLocation() async {
    _isLocating = true;
    notifyListeners();

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _isLocating = false;
        notifyListeners();
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _isLocating = false;
          notifyListeners();
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _isLocating = false;
        notifyListeners();
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      _latitude = position.latitude;
      _longitude = position.longitude;
      _locationLabel = 'Mi ubicación';
      _hasCustomLocation = true;
      _isLocating = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error obteniendo ubicación: $e');
      _isLocating = false;
      notifyListeners();
      return false;
    }
  }

  /// Establece una ubicación manualmente (desde el mapa o selección de ciudad)
  void setLocation({
    required double latitude,
    required double longitude,
    String? label,
  }) {
    _latitude = latitude;
    _longitude = longitude;
    _locationLabel = label ?? 'Ubicación personalizada';
    _hasCustomLocation = true;
    notifyListeners();
  }

  /// Establece una ciudad predefinida
  void setCity(String cityName, double lat, double lng) {
    _latitude = lat;
    _longitude = lng;
    _locationLabel = cityName;
    _hasCustomLocation = true;
    notifyListeners();
  }

  /// Resetea a la ubicación por defecto
  void resetToDefault() {
    _latitude = defaultLatitude;
    _longitude = defaultLongitude;
    _locationLabel = AppConstants.defaultLocationLabel;
    _hasCustomLocation = false;
    notifyListeners();
  }

  /// Crea un Position object para compatibilidad
  Position? toPosition() {
    if (_latitude == null || _longitude == null) return null;
    return Position(
      latitude: _latitude!,
      longitude: _longitude!,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}
