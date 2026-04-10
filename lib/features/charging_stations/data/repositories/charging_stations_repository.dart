import '../../domain/models/charging_station.dart';
import '../../domain/enums/charging_enums.dart';
import '../services/open_charge_map_service.dart';

/// Repositorio para gestionar estaciones de carga
/// 
/// Maneja la obtención de datos desde Open Charge Map API
/// y proporciona cache local para mejor performance.
class ChargingStationsRepository {
  final OpenChargeMapService _ocmService;
  
  // Cache local de estaciones
  List<ChargingStation>? _cachedStations;
  DateTime? _lastFetch;
  double? _lastLatitude;
  double? _lastLongitude;
  
  static const Duration _cacheExpiration = Duration(minutes: 10);
  static const double _locationThreshold = 0.01; // ~1km de diferencia

  ChargingStationsRepository({
    OpenChargeMapService? ocmService,
  }) : _ocmService = ocmService ?? OpenChargeMapService();

  /// Obtiene estaciones cercanas a una ubicación
  /// 
  /// Usa cache si la ubicación es similar y no ha expirado
  Future<List<ChargingStation>> getNearbyStations({
    required double latitude,
    required double longitude,
    double radiusKm = 50,
    bool forceRefresh = false,
  }) async {
    // Verificar si podemos usar cache
    if (!forceRefresh && _canUseCache(latitude, longitude)) {
      return _cachedStations!;
    }

    try {
      final stations = await _ocmService.getNearbyStations(
        latitude: latitude,
        longitude: longitude,
        distanceKm: radiusKm,
        maxResults: 100,
      );

      // Ordenar por distancia
      stations.sort((a, b) => 
          (a.distanceKm ?? double.infinity)
              .compareTo(b.distanceKm ?? double.infinity));

      // Actualizar cache
      _cachedStations = stations;
      _lastFetch = DateTime.now();
      _lastLatitude = latitude;
      _lastLongitude = longitude;

      return stations;
    } catch (e) {
      // Si hay error y tenemos cache, retornar cache
      if (_cachedStations != null) {
        return _cachedStations!;
      }
      rethrow;
    }
  }

  /// Obtiene estaciones por ciudad colombiana
  Future<List<ChargingStation>> getStationsByCity(
    ColombianCity city, {
    bool forceRefresh = false,
  }) async {
    return getNearbyStations(
      latitude: city.latitude,
      longitude: city.longitude,
      radiusKm: 30,
      forceRefresh: forceRefresh,
    );
  }

  /// Busca estaciones por texto
  Future<List<ChargingStation>> searchStations({
    required String query,
    double? latitude,
    double? longitude,
  }) async {
    // Si tenemos cache, buscar localmente primero
    if (_cachedStations != null && _cachedStations!.isNotEmpty) {
      final localResults = _cachedStations!.where((station) =>
          station.name.toLowerCase().contains(query.toLowerCase()) ||
          station.address.toLowerCase().contains(query.toLowerCase()) ||
          (station.networkName?.toLowerCase().contains(query.toLowerCase()) ?? false)
      ).toList();

      if (localResults.isNotEmpty) {
        return localResults;
      }
    }

    // Si no hay resultados locales, buscar en API
    return _ocmService.searchStations(
      query: query,
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Obtiene una estación por ID
  Future<ChargingStation?> getStationById(String id) async {
    // Buscar en cache primero
    if (_cachedStations != null) {
      final cached = _cachedStations!.where((s) => s.id == id).firstOrNull;
      if (cached != null) return cached;
    }

    // TODO: Implementar llamada a API para obtener estación individual
    return null;
  }

  /// Filtra estaciones según criterios
  List<ChargingStation> filterStations(
    List<ChargingStation> stations, {
    Set<ConnectorType>? connectorTypes,
    Set<ChargingType>? chargingTypes,
    ChargingSpeed? minSpeed,
    bool? onlyAvailable,
    bool? onlyFree,
    double? maxDistanceKm,
    String? networkName,
  }) {
    return stations.where((station) {
      // Filtro por tipos de conector
      if (connectorTypes != null && connectorTypes.isNotEmpty) {
        if (!station.connectorTypes.any((t) => connectorTypes.contains(t))) {
          return false;
        }
      }

      // Filtro por tipo de carga (AC/DC)
      if (chargingTypes != null && chargingTypes.isNotEmpty) {
        if (!station.chargingTypes.any((t) => chargingTypes.contains(t))) {
          return false;
        }
      }

      // Filtro por velocidad mínima
      if (minSpeed != null) {
        if (station.maxPowerKw < minSpeed.minPowerKw) {
          return false;
        }
      }

      // Filtro solo disponibles
      if (onlyAvailable == true) {
        if (!station.hasAvailableConnectors) {
          return false;
        }
      }

      // Filtro solo gratuitos
      if (onlyFree == true) {
        if (!station.isFree) {
          return false;
        }
      }

      // Filtro por distancia máxima
      if (maxDistanceKm != null && station.distanceKm != null) {
        if (station.distanceKm! > maxDistanceKm) {
          return false;
        }
      }

      // Filtro por red/operador
      if (networkName != null && networkName.isNotEmpty) {
        if (station.networkName?.toLowerCase() != networkName.toLowerCase()) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// Verifica si el cache es válido para usar
  bool _canUseCache(double latitude, double longitude) {
    if (_cachedStations == null || _lastFetch == null) return false;
    if (_lastLatitude == null || _lastLongitude == null) return false;

    // Verificar expiración
    if (DateTime.now().difference(_lastFetch!) > _cacheExpiration) {
      return false;
    }

    // Verificar si la ubicación es similar
    final latDiff = (latitude - _lastLatitude!).abs();
    final lngDiff = (longitude - _lastLongitude!).abs();
    
    return latDiff < _locationThreshold && lngDiff < _locationThreshold;
  }

  /// Limpia el cache
  void clearCache() {
    _cachedStations = null;
    _lastFetch = null;
    _lastLatitude = null;
    _lastLongitude = null;
  }

  /// Obtiene las redes/operadores disponibles
  Set<String> getAvailableNetworks() {
    if (_cachedStations == null) return {};
    return _cachedStations!
        .map((s) => s.networkName)
        .where((n) => n != null && n.isNotEmpty)
        .cast<String>()
        .toSet();
  }

  void dispose() {
    _ocmService.dispose();
  }
}
