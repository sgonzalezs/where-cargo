import 'package:flutter/foundation.dart';

import '../../features/charging_stations/data/repositories/charging_stations_repository.dart';
import '../../features/charging_stations/domain/models/charging_station.dart';
import 'location_service.dart';
import 'proximity_notification_service.dart';

/// Servicio singleton para compartir estaciones entre Mapa y Listado
/// Evita cargar estaciones dos veces y mantiene sincronización
class StationsService extends ChangeNotifier {
  static final StationsService _instance = StationsService._internal();
  factory StationsService() => _instance;
  StationsService._internal();

  /// Radio de búsqueda usado por toda la app.
  static const double searchRadiusKm = 30;

  final ChargingStationsRepository _repository = ChargingStationsRepository();
  final LocationService _locationService = LocationService();

  // Lista de estaciones cargadas
  List<ChargingStation> _stations = [];
  bool _isLoading = false;
  Object? _lastError;

  // Carga en curso: si Mapa y Listado piden lo mismo a la vez, comparten
  // la misma petición en lugar de lanzar dos.
  Future<List<ChargingStation>>? _inflight;
  String? _inflightKey;

  // Getters
  List<ChargingStation> get stations => _stations;
  bool get isLoading => _isLoading;
  bool get hasStations => _stations.isNotEmpty;

  /// Error de la última carga, o `null` si fue exitosa.
  Object? get lastError => _lastError;

  /// Carga las estaciones cercanas a la ubicación actual del [LocationService].
  ///
  /// Lanza la excepción si falló y no había cache disponible.
  Future<List<ChargingStation>> loadForCurrentLocation({
    bool forceRefresh = false,
  }) {
    final lat = _locationService.latitude;
    final lng = _locationService.longitude;
    // Redondeo a ~1 km: si el GPS ajusta unos metros la posición mientras hay
    // una carga en curso, se reutiliza en lugar de repetir las llamadas.
    final key =
        '${lat.toStringAsFixed(2)},${lng.toStringAsFixed(2)},$forceRefresh';

    if (_inflight != null && _inflightKey == key) {
      // Misma zona: esperar la carga en curso y ajustar distancias a la
      // posición más reciente
      return _inflight!.then((stations) {
        if (lat == _locationService.latitude &&
            lng == _locationService.longitude &&
            identical(stations, _stations)) {
          final updated = _repository.recalculateDistancesFrom(
            stations: stations,
            latitude: lat,
            longitude: lng,
          );
          setStations(updated);
          return updated;
        }
        return stations;
      });
    }

    final future = _load(lat, lng, forceRefresh);
    _inflight = future;
    _inflightKey = key;
    return future.whenComplete(() {
      if (identical(_inflight, future)) {
        _inflight = null;
        _inflightKey = null;
      }
    });
  }

  Future<List<ChargingStation>> _load(
    double lat,
    double lng,
    bool forceRefresh,
  ) async {
    if (forceRefresh) _repository.clearCache();
    setLoading(true);
    try {
      // Cada emisión (cache, luego cada fuente que responde) se publica de
      // inmediato para que el mapa pinte marcadores sin esperar a todas.
      var stations = _stations;
      await for (final update in _repository.watchNearbyStations(
        latitude: lat,
        longitude: lng,
        radiusKm: searchRadiusKm,
        forceRefresh: forceRefresh,
      )) {
        stations = update;
        setStations(update);
      }
      _lastError = null;
      return stations;
    } catch (e) {
      _lastError = e;
      rethrow;
    } finally {
      setLoading(false);
    }
  }

  /// Actualiza la lista de estaciones
  void setStations(List<ChargingStation> stations) {
    _stations = stations;
    ProximityNotificationService().updateStations(stations);
    notifyListeners();
  }

  /// Reemplaza una estación ya cargada (ej. tras completar sus datos en el
  /// detalle) para que el mapa y el listado muestren la versión nueva.
  void replaceStation(ChargingStation station) {
    final index = _stations.indexWhere((s) => s.id == station.id);
    if (index == -1) return;
    setStations(List.of(_stations)
      ..[index] = station.copyWith(distanceKm: _stations[index].distanceKm));
  }

  /// Establece el estado de carga
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Limpia las estaciones
  void clearStations() {
    _stations = [];
    notifyListeners();
  }
}
