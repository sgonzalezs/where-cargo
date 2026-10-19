import 'package:flutter/foundation.dart';

import '../../features/charging_stations/domain/models/charging_station.dart';

/// Servicio singleton para compartir estaciones entre Mapa y Listado
/// Evita cargar estaciones dos veces y mantiene sincronización
class StationsService extends ChangeNotifier {
  static final StationsService _instance = StationsService._internal();
  factory StationsService() => _instance;
  StationsService._internal();

  // Lista de estaciones cargadas
  List<ChargingStation> _stations = [];
  bool _isLoading = false;

  // Getters
  List<ChargingStation> get stations => _stations;
  bool get isLoading => _isLoading;
  bool get hasStations => _stations.isNotEmpty;

  /// Actualiza la lista de estaciones
  void setStations(List<ChargingStation> stations) {
    _stations = stations;
    notifyListeners();
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
