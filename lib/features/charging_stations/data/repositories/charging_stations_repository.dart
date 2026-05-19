import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/charging_station.dart';
import '../../domain/enums/charging_enums.dart';
import '../../../filters/domain/models/station_filters.dart';
import '../services/open_charge_map_service.dart';
import '../services/osm_service.dart';
import '../services/google_places_service.dart';

/// Repositorio para gestionar estaciones de carga
///
/// Maneja la obtención de datos desde Open Charge Map API
/// y proporciona cache local para mejor performance.
class ChargingStationsRepository {
  final OpenChargeMapService _ocmService;
  final OsmService _osmService;
  final GooglePlacesService _googlePlacesService;

  // Cache local de estaciones
  List<ChargingStation>? _cachedStations;
  DateTime? _lastFetch;
  double? _lastLatitude;
  double? _lastLongitude;

  static const Duration _cacheExpiration = Duration(minutes: 10);
  static const double _locationThreshold = 0.01; // ~1km de diferencia

  // Claves para cache persistente
  static const String _persistentCacheKey = 'station_cache_v5';
  static const String _persistentCacheLatKey = 'station_cache_lat_v5';
  static const String _persistentCacheLngKey = 'station_cache_lng_v5';
  static const String _persistentCacheTimeKey = 'station_cache_time_v5';
  static const Duration _persistentCacheMaxAge = Duration(hours: 24);

  ChargingStationsRepository({
    OpenChargeMapService? ocmService,
    OsmService? osmService,
    GooglePlacesService? googlePlacesService,
  })  : _ocmService = ocmService ?? OpenChargeMapService(),
        _osmService = osmService ?? OsmService(),
        _googlePlacesService =
            googlePlacesService ?? GooglePlacesService();

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
      // Consultar OCM, OSM y Google Places en paralelo
      final results = await Future.wait([
        _ocmService.getNearbyStations(
          latitude: latitude,
          longitude: longitude,
          distanceKm: radiusKm,
          maxResults: 500,
        ),
        _osmService.getNearbyStations(
          latitude: latitude,
          longitude: longitude,
          radiusMeters: (radiusKm * 1000).round(),
        ),
        _googlePlacesService.getNearbyStations(
          latitude: latitude,
          longitude: longitude,
          radiusMeters: (radiusKm * 1000).clamp(0, 50000).round(),
        ),
      ]);

      final ocmStations = results[0];
      final osmStations = results[1];
      final googleStations = results[2];

      // Mantenemos TODAS las estaciones de las 3 fuentes. Aquellas que vienen
      // de Google/OSM sin metadatos de conector se marcan con `hasCompleteData = false`
      // y la UI las muestra con un indicador "Datos limitados" para que el
      // usuario al menos sepa que hay un punto de carga en esa ubicación.
      final completeFromOsm =
          osmStations.where((s) => s.hasCompleteData).length;
      final completeFromGoogle =
          googleStations.where((s) => s.hasCompleteData).length;

      debugPrint(
          '[WhereCargo] Fuentes — OCM: ${ocmStations.length}, '
          'Google: ${googleStations.length} (con datos: $completeFromGoogle), '
          'OSM: ${osmStations.length} (con datos: $completeFromOsm)');

      // Prioridad: OCM (más completo) → Google Places → OSM (fallback)
      final withGoogle = _mergeStations(ocmStations, googleStations);
      final merged = _mergeStations(withGoogle, osmStations);

      debugPrint('[WhereCargo] Total después de fusionar: ${merged.length}');

      // Ordenar por distancia
      merged.sort(
        (a, b) => (a.distanceKm ?? double.infinity).compareTo(
          b.distanceKm ?? double.infinity,
        ),
      );

      // Actualizar cache
      _cachedStations = merged;
      _lastFetch = DateTime.now();
      _lastLatitude = latitude;
      _lastLongitude = longitude;
      _savePersistentCache(merged, latitude, longitude); // fire-and-forget

      return merged;
    } catch (e) {
      // Si hay error y tenemos cache en memoria, retornar cache
      if (_cachedStations != null) {
        return _cachedStations!;
      }
      // Intentar con cache persistente (sobrevive reinicios de la app)
      final persisted = await _loadPersistentCache(latitude, longitude);
      if (persisted != null) {
        _cachedStations = persisted;
        return persisted;
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
    // OCM solo acepta IDs numéricos. Si la estación viene de OSM (osm_*) o
    // Google Places (gpl_*) no podemos refrescar — devolver la original tal cual.
    if (int.tryParse(station.id) == null) {
      return station;
    }
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

  /// Limpia el cache en memoria (el persistente se mantiene para uso offline).
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

  // ---------------------------------------------------------------------------
  // Cache persistente
  // ---------------------------------------------------------------------------

  /// Guarda las estaciones en SharedPreferences de forma asíncrona.
  void _savePersistentCache(
    List<ChargingStation> stations,
    double lat,
    double lng,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = stations.map((s) => s.toJson()).toList();
      await prefs.setString(_persistentCacheKey, jsonEncode(jsonList));
      await prefs.setDouble(_persistentCacheLatKey, lat);
      await prefs.setDouble(_persistentCacheLngKey, lng);
      await prefs.setInt(
        _persistentCacheTimeKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('Error guardando cache persistente: $e');
    }
  }

  /// Carga estaciones desde SharedPreferences si el cache no ha expirado.
  Future<List<ChargingStation>?> _loadPersistentCache(
    double lat,
    double lng,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_persistentCacheKey);
      if (jsonString == null) return null;

      // Verificar edad del cache
      final cacheTime = prefs.getInt(_persistentCacheTimeKey) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - cacheTime;
      if (age > _persistentCacheMaxAge.inMilliseconds) return null;

      final List<dynamic> jsonList = jsonDecode(jsonString);
      final stations = jsonList
          .map((j) => ChargingStation.fromJson(j as Map<String, dynamic>))
          .toList();

      // Recalcular distancias con la ubicación actual
      return _recalculateDistances(stations, lat, lng);
    } catch (e) {
      debugPrint('Error cargando cache persistente: $e');
      return null;
    }
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

  // ---------------------------------------------------------------------------
  // Fusión de fuentes
  // ---------------------------------------------------------------------------

  /// Combina estaciones de OCM y OSM eliminando duplicados.
  ///
  /// Se considera duplicado cualquier par de estaciones cuyo centro
  /// esté a menos de [thresholdKm] km (por defecto 0.05 = 50 m).
  /// En caso de duplicado siempre se prioriza la estación de OCM,
  /// que generalmente tiene información más completa.
  List<ChargingStation> _mergeStations(
    List<ChargingStation> ocm,
    List<ChargingStation> osm, {
    double thresholdKm = 0.05,
  }) {
    final merged = List<ChargingStation>.from(ocm);

    for (final osmStation in osm) {
      final isDuplicate = merged.any((existing) {
        final dist = _calculateDistance(
          existing.latitude,
          existing.longitude,
          osmStation.latitude,
          osmStation.longitude,
        );
        return dist < thresholdKm;
      });

      if (!isDuplicate) {
        merged.add(osmStation);
      }
    }

    return merged;
  }

  void dispose() {
    _ocmService.dispose();
  }
}
