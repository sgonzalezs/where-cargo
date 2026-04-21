import 'dart:math' as math;

import '../../domain/models/charging_station.dart';
import '../../domain/enums/charging_enums.dart';
import '../../../filters/domain/models/station_filters.dart';
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

  ChargingStationsRepository({OpenChargeMapService? ocmService})
    : _ocmService = ocmService ?? OpenChargeMapService();

  /// Obtiene estaciones cercanas a una ubicación
  ///
  /// Usa cache si la ubicación es similar y no ha expirado
  /// Si forceRefresh es true, siempre recarga del API
  /// Si recalculateDistances es true, recalcula las distancias con la nueva ubicación
  Future<List<ChargingStation>> getNearbyStations({
    required double latitude,
    required double longitude,
    double radiusKm = 50,
    bool forceRefresh = false,
  }) async {
    // Verificar si la ubicación cambió significativamente
    final locationChanged = !_isSameLocation(latitude, longitude);

    // Verificar si podemos usar cache (si la ubicación no cambió mucho y no expiró)
    if (!forceRefresh && _canUseCache(latitude, longitude)) {
      // Si la ubicación cambió un poco pero tenemos cache válido,
      // recalcular distancias con la nueva ubicación
      if (locationChanged && _cachedStations != null) {
        return _recalculateDistances(_cachedStations!, latitude, longitude);
      }
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
      stations.sort(
        (a, b) => (a.distanceKm ?? double.infinity).compareTo(
          b.distanceKm ?? double.infinity,
        ),
      );

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
      final localResults = _cachedStations!
          .where((station) => _matchesSearchQuery(station, query))
          .toList();

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

  /// Obtiene una estación por ID (primero cache, luego API)
  Future<ChargingStation?> getStationById(String id) async {
    // Buscar en cache primero
    if (_cachedStations != null) {
      final cached = _cachedStations!.where((s) => s.id == id).firstOrNull;
      if (cached != null) return cached;
    }

    // Si no está en cache, obtener del API
    return _ocmService.getStationById(
      stationId: id,
      userLat: _lastLatitude,
      userLng: _lastLongitude,
    );
  }

  /// Refresca los datos de una estación desde el API
  /// Útil para obtener información actualizada de disponibilidad
  Future<ChargingStation?> refreshStation(ChargingStation station) async {
    try {
      final refreshed = await _ocmService.getStationById(
        stationId: station.id,
        userLat: _lastLatitude ?? station.latitude,
        userLng: _lastLongitude ?? station.longitude,
      );

      if (refreshed != null) {
        // Actualizar en cache si existe
        if (_cachedStations != null) {
          final index = _cachedStations!.indexWhere((s) => s.id == station.id);
          if (index != -1) {
            _cachedStations![index] = refreshed;
          }
        }
        return refreshed;
      }

      return station; // Devolver original si no se pudo refrescar
    } catch (e) {
      // Si hay error, devolver la estación original
      return station;
    }
  }

  /// Filtra estaciones según criterios
  List<ChargingStation> filterStations(
    List<ChargingStation> stations, {
    String? query,
    Set<ConnectorType>? connectorTypes,
    Set<ChargingType>? chargingTypes,
    Set<ChargingSpeed>? chargingSpeeds,
    ChargingSpeed? minSpeed,
    double? minPowerKw,
    double? maxPowerKw,
    bool? onlyAvailable,
    bool? onlyFree,
    bool? onlyOpenNow,
    double? maxDistanceKm,
    String? networkName,
    SortOption sortBy = SortOption.distance,
  }) {
    final filtered = stations.where((station) {
      if (query != null && query.trim().isNotEmpty) {
        if (!_matchesSearchQuery(station, query)) {
          return false;
        }
      }

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

      if (chargingSpeeds != null && chargingSpeeds.isNotEmpty) {
        if (!station.connectors.any(
          (connector) => chargingSpeeds.contains(connector.chargingSpeed),
        )) {
          return false;
        }
      }

      // Filtro por velocidad mínima
      if (minSpeed != null) {
        if (station.maxPowerKw < minSpeed.minPowerKw) {
          return false;
        }
      }

      if (minPowerKw != null) {
        if (!station.connectors.any(
          (connector) => connector.powerKw >= minPowerKw,
        )) {
          return false;
        }
      }

      if (maxPowerKw != null) {
        if (!station.connectors.any(
          (connector) => connector.powerKw <= maxPowerKw,
        )) {
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

      if (onlyOpenNow == true && !station.isOpen) {
        return false;
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

    _sortStations(filtered, sortBy);
    return filtered;
  }

  bool _matchesSearchQuery(ChargingStation station, String query) {
    final normalizedQuery = _normalizeForSearch(query);
    if (normalizedQuery.isEmpty) return true;

    final tokens = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return true;

    final searchTerms = <String>[
      station.name,
      station.address,
      station.city,
      station.country,
      if (station.state != null) station.state!,
      if (station.description != null) station.description!,
      if (station.networkName != null) station.networkName!,
      station.status.displayName,
      station.status.apiValue,
      station.paymentType.displayName,
      station.paymentType.apiValue,
      if (station.isFree) 'gratis free sin costo',
      if (station.hasAvailableConnectors) 'disponible available',
      if (station.hasDcCharging) 'dc carga rapida carga rápida fast',
      if (station.hasAcCharging) 'ac carga normal lenta',
      if (station.amenities != null) ...station.amenities!,
      ...station.connectors.expand(
        (connector) => [
          connector.type.displayName,
          connector.type.apiValue,
          connector.type.name,
          connector.chargingType.displayName,
          connector.chargingType.apiValue,
          connector.chargingType.name,
          connector.chargingSpeed.displayName,
          connector.chargingSpeed.apiValue,
          connector.chargingSpeed.name,
          connector.status.displayName,
          connector.status.apiValue,
          '${connector.powerKw.toStringAsFixed(connector.powerKw.truncateToDouble() == connector.powerKw ? 0 : 1)} kw',
          '${connector.powerKw.toInt()} kw',
        ],
      ),
    ];

    final haystack = _normalizeForSearch(searchTerms.join(' '));
    return tokens.every(haystack.contains);
  }

  String _normalizeForSearch(String value) {
    const replacements = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };

    var normalized = value.toLowerCase();
    replacements.forEach((source, target) {
      normalized = normalized.replaceAll(source, target);
    });
    return normalized;
  }

  void _sortStations(List<ChargingStation> stations, SortOption sortBy) {
    switch (sortBy) {
      case SortOption.distance:
        stations.sort(
          (a, b) => (a.distanceKm ?? double.infinity).compareTo(
            b.distanceKm ?? double.infinity,
          ),
        );
        break;
      case SortOption.rating:
        stations.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
        break;
      case SortOption.power:
        stations.sort((a, b) => b.maxPowerKw.compareTo(a.maxPowerKw));
        break;
      case SortOption.availability:
        stations.sort(
          (a, b) =>
              b.availableConnectorCount.compareTo(a.availableConnectorCount),
        );
        break;
      case SortOption.price:
        stations.sort(
          (a, b) => _lowestPricePerKwh(a).compareTo(_lowestPricePerKwh(b)),
        );
        break;
    }
  }

  double _lowestPricePerKwh(ChargingStation station) {
    final prices = station.connectors
        .map((connector) => connector.pricePerKwh ?? 0)
        .toList();
    if (prices.isEmpty) return double.infinity;
    return prices.reduce(math.min);
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

  /// Verifica si la ubicación es exactamente la misma
  bool _isSameLocation(double latitude, double longitude) {
    if (_lastLatitude == null || _lastLongitude == null) return false;
    return latitude == _lastLatitude && longitude == _lastLongitude;
  }

  /// Recalcula las distancias de las estaciones desde una nueva ubicación
  List<ChargingStation> _recalculateDistances(
    List<ChargingStation> stations,
    double userLat,
    double userLng,
  ) {
    return stations.map((station) {
      final newDistance = _calculateDistance(
        userLat,
        userLng,
        station.latitude,
        station.longitude,
      );
      return station.copyWith(distanceKm: newDistance);
    }).toList()..sort(
      (a, b) => (a.distanceKm ?? double.infinity).compareTo(
        b.distanceKm ?? double.infinity,
      ),
    );
  }

  /// Recalcula distancias de estaciones existentes con nueva ubicación
  /// Método público para recalcular desde fuera
  List<ChargingStation> recalculateDistancesFrom({
    required List<ChargingStation> stations,
    required double latitude,
    required double longitude,
  }) {
    return _recalculateDistances(stations, latitude, longitude);
  }

  /// Calcula distancia entre dos puntos usando Haversine
  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadius = 6371; // km

    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  void dispose() {
    _ocmService.dispose();
  }
}
