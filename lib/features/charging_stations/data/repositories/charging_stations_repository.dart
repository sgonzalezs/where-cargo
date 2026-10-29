import 'dart:async';
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
/// Combina Open Charge Map, Google Places y OSM, y proporciona cache local.
/// Es un singleton para que Mapa, Listado y Detalle compartan el mismo cache.
class ChargingStationsRepository {
  final OpenChargeMapService _ocmService;
  final OsmService _osmService;
  final GooglePlacesService _googlePlacesService;

  // Cache local de estaciones
  List<ChargingStation>? _cachedStations;
  DateTime? _lastFetch;
  bool _lastFetchWasPartial = false;
  double? _lastLatitude;
  double? _lastLongitude;

  static const Duration _cacheExpiration = Duration(minutes: 10);
  // Si alguna fuente falló, reintentar antes (pero sin repetir en cada
  // apertura de pantalla, porque Google Places se factura por llamada)
  final Duration _partialCacheExpiration;
  static const double _locationThreshold = 0.01; // ~1km de diferencia

  // Identificadores de fuente (el prefijo del id de la estación indica cuál es)
  static const String _ocm = 'OCM';
  static const String _google = 'Google Places';
  static const String _osm = 'OSM';

  // Claves para cache persistente
  static const String _persistentCacheKey = 'station_cache_v6';
  static const String _persistentCacheLatKey = 'station_cache_lat_v6';
  static const String _persistentCacheLngKey = 'station_cache_lng_v6';
  static const String _persistentCacheTimeKey = 'station_cache_time_v6';
  static const Duration _persistentCacheMaxAge = Duration(hours: 24);

  // Datos encontrados al abrir el detalle de una estación (por id)
  static const String _enrichmentCacheKey = 'station_enrichment_v1';
  static const Duration _enrichmentMaxAge = Duration(days: 7);
  static const int _enrichmentMaxEntries = 300;
  final Map<String, _Enrichment> _enrichments = {};
  Future<void>? _enrichmentsLoaded;

  static final ChargingStationsRepository _instance =
      ChargingStationsRepository.withServices();

  /// Instancia compartida por toda la app.
  factory ChargingStationsRepository() => _instance;

  /// Crea una instancia independiente (útil para tests).
  ChargingStationsRepository.withServices({
    OpenChargeMapService? ocmService,
    OsmService? osmService,
    GooglePlacesService? googlePlacesService,
    Duration partialCacheExpiration = const Duration(minutes: 2),
  })  : _ocmService = ocmService ?? OpenChargeMapService(),
        _osmService = osmService ?? OsmService(),
        _googlePlacesService =
            googlePlacesService ?? GooglePlacesService(),
        _partialCacheExpiration = partialCacheExpiration;

  /// Obtiene estaciones cercanas a una ubicación (resultado final).
  ///
  /// Equivale a esperar la última emisión de [watchNearbyStations].
  Future<List<ChargingStation>> getNearbyStations({
    required double latitude,
    required double longitude,
    double radiusKm = 50,
    bool forceRefresh = false,
  }) {
    return watchNearbyStations(
      latitude: latitude,
      longitude: longitude,
      radiusKm: radiusKm,
      forceRefresh: forceRefresh,
    ).last;
  }

  /// Obtiene estaciones cercanas de forma progresiva.
  ///
  /// 1. Si hay cache persistente de la zona, lo emite de inmediato.
  /// 2. Consulta OCM, Google Places y OSM en paralelo y emite un resultado
  ///    fusionado cada vez que responde una fuente, sin esperar a la más lenta.
  /// 3. Mientras una fuente no ha respondido (o si falla), se usan sus
  ///    estaciones del cache para que no desaparezcan marcadores del mapa.
  ///
  /// Lanza error solo si todas las fuentes fallan y no hay ningún cache.
  Stream<List<ChargingStation>> watchNearbyStations({
    required double latitude,
    required double longitude,
    double radiusKm = 50,
    bool forceRefresh = false,
  }) async* {
    if (!forceRefresh && _canUseCache(latitude, longitude)) {
      yield _isSameLocation(latitude, longitude)
          ? _cachedStations!
          : _recalculateDistances(_cachedStations!, latitude, longitude);
      return;
    }

    await _loadEnrichments();

    // Cache de la zona: se muestra al instante y sirve de respaldo por fuente
    final stale = await _loadPersistentCache(
          latitude,
          longitude,
          maxCenterDistanceKm: radiusKm / 2,
        ) ??
        const <ChargingStation>[];
    var emitted = false;
    if (!forceRefresh && stale.isNotEmpty) {
      yield stale;
      emitted = true;
    }

    final fetchers = <String, Future<List<ChargingStation>> Function()>{
      _ocm: () => _ocmService.getNearbyStations(
            latitude: latitude,
            longitude: longitude,
            distanceKm: radiusKm,
            maxResults: 500,
          ),
      _google: () => _googlePlacesService.getNearbyStations(
            latitude: latitude,
            longitude: longitude,
            radiusMeters: (radiusKm * 1000).clamp(0, 50000).round(),
          ),
      _osm: () => _osmService.getNearbyStations(
            latitude: latitude,
            longitude: longitude,
            radiusMeters: (radiusKm * 1000).round(),
          ),
    };

    // Cada fuente avisa por este stream cuando termina (con éxito o error)
    final fresh = <String, List<ChargingStation>>{};
    final errors = <String, Object>{};
    final done = StreamController<bool>();
    var pending = fetchers.length;
    fetchers.forEach((source, fetch) {
      fetch().then((stations) {
        fresh[source] = stations;
        done.add(true);
      }, onError: (Object e) {
        debugPrint('[WhereCargo] Falló $source: $e');
        errors[source] = e;
        done.add(false);
      }).whenComplete(() {
        if (--pending == 0) done.close();
      });
    });

    List<ChargingStation>? merged;
    await for (final succeeded in done.stream) {
      if (!succeeded || fresh.isEmpty) continue;
      merged = _mergeSources(fresh, stale);
      yield merged;
      if (merged.isNotEmpty) emitted = true;
    }

    // Todas las fuentes fallaron, o solo respondió alguna vacía mientras las
    // demás fallaban (ej. compilación sin API keys): no es "no hay estaciones"
    if (merged == null || (merged.isEmpty && errors.isNotEmpty)) {
      if (emitted) return; // ya se mostró el cache de la zona
      if (_cachedStations != null) {
        yield _recalculateDistances(_cachedStations!, latitude, longitude);
        return;
      }
      final persisted = await _loadPersistentCache(latitude, longitude);
      if (persisted != null) {
        _cachedStations = persisted;
        yield persisted;
        return;
      }
      throw errors.values.first;
    }

    debugPrint('[WhereCargo] Fuentes — '
        '${fetchers.keys.map((s) => '$s: ${fresh[s]?.length ?? 'error'}').join(', ')}'
        ' → ${merged.length} estaciones '
        '(${merged.where((s) => s.hasCompleteData).length} con datos completos)');

    // Si alguna fuente falló el resultado es parcial: se usa en memoria con
    // una expiración corta y no se persiste, para no extender la vida del
    // cache viejo con el que se rellenó la fuente faltante.
    final isPartial = errors.isNotEmpty;
    _cachedStations = merged;
    _lastFetch = DateTime.now();
    _lastFetchWasPartial = isPartial;
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    if (!isPartial) {
      _savePersistentCache(merged, latitude, longitude); // fire-and-forget
    }
  }

  /// Fusiona las fuentes en orden de prioridad OCM → Google → OSM.
  /// Las fuentes que aún no respondieron (o fallaron) se rellenan con sus
  /// estaciones de [stale].
  List<ChargingStation> _mergeSources(
    Map<String, List<ChargingStation>> fresh,
    List<ChargingStation> stale,
  ) {
    List<ChargingStation> source(String name) =>
        fresh[name] ?? stale.where((s) => _sourceOf(s) == name).toList();

    final merged = _mergeStations(
      _mergeStations(source(_ocm), source(_google)),
      source(_osm),
    ).map(_withEnrichment).toList();
    merged.sort(
      (a, b) => (a.distanceKm ?? double.infinity).compareTo(
        b.distanceKm ?? double.infinity,
      ),
    );
    return merged;
  }

  static String _sourceOf(ChargingStation station) {
    if (station.id.startsWith('osm_')) return _osm;
    if (station.id.startsWith('gpl_')) return _google;
    return _ocm;
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

  /// Completa la información de una estación consultando las demás fuentes
  /// alrededor de su ubicación (se llama al abrir su detalle).
  ///
  /// En paralelo:
  /// - OCM: si la estación es de OCM se vuelve a pedir (disponibilidad en
  ///   tiempo real); si no, se busca en un radio de 200 m.
  /// - Google Places: búsqueda por nombre a 150 m (salvo estaciones de Google,
  ///   que ya traen todo lo que Google tiene).
  /// - OSM: radio de 150 m, solo si aún faltan conectores.
  ///
  /// Lo encontrado se guarda 7 días para no repetir consultas facturadas, y
  /// se aplica también a las cargas del mapa. Nunca lanza: ante errores
  /// devuelve lo que se haya podido completar.
  Future<ChargingStation> enrichStation(
    ChargingStation station, {
    bool forceRefresh = false,
  }) async {
    await _loadEnrichments();
    final source = _sourceOf(station);
    final cached = forceRefresh ? null : _enrichments[station.id];

    final errors = <Object>[];
    Future<List<ChargingStation>> attempt(
      String name,
      Future<List<ChargingStation>> Function() lookup,
    ) async {
      try {
        return await lookup();
      } catch (e) {
        debugPrint('[WhereCargo] Detalle: falló $name: $e');
        errors.add(e);
        return const [];
      }
    }

    Future<List<ChargingStation>> skip() async => const [];

    // OCM es gratis y da disponibilidad en vivo: se consulta siempre
    final ocmLookup = source == _ocm
        ? attempt(_ocm, () async {
            final refreshed = await _ocmService.getStationById(
              stationId: station.id,
              userLat: _lastLatitude ?? station.latitude,
              userLng: _lastLongitude ?? station.longitude,
            );
            return [if (refreshed != null) refreshed];
          })
        : cached != null
        ? skip()
        : attempt(
            _ocm,
            () => _ocmService.getNearbyStations(
              latitude: station.latitude,
              longitude: station.longitude,
              distanceKm: 0.2,
              maxResults: 5,
            ),
          );
    final googleLookup = cached != null || source == _google
        ? skip()
        : attempt(
            _google,
            () => _googlePlacesService.findStationsNear(
              name: _genericNames.contains(station.name)
                  ? 'estación de carga'
                  : station.name,
              latitude: station.latitude,
              longitude: station.longitude,
            ),
          );
    final osmLookup =
        cached != null || source == _osm || station.hasCompleteData
        ? skip()
        : attempt(
            _osm,
            () => _osmService.getNearbyStations(
              latitude: station.latitude,
              longitude: station.longitude,
              radiusMeters: 150,
            ),
          );

    final results = await Future.wait([ocmLookup, googleLookup, osmLookup]);
    final ocmResults = results[0];

    var enriched = station;
    if (source == _ocm && ocmResults.isNotEmpty) {
      // Datos frescos de OCM primero; lo demás que ya tenía la estación
      // (ej. conectores tomados de Google al fusionar) se conserva.
      enriched = _combine(ocmResults.first, station);
    }

    final twins =
        cached?.twins ??
        [
          if (source != _ocm) ...ocmResults,
          ...results[1],
          ...results[2],
        ].where((s) => s.id != station.id && _isSameStation(station, s)).toList();
    enriched = twins
        .fold(enriched, _combine)
        .copyWith(distanceKm: station.distanceKm);

    if (cached == null && errors.isEmpty) {
      // Se guarda aunque no se haya encontrado nada: así no se vuelve a
      // pagar la búsqueda en cada apertura del detalle.
      _enrichments[station.id] = _Enrichment(DateTime.now(), twins);
      _saveEnrichments();
    }

    final index = _cachedStations?.indexWhere((s) => s.id == station.id) ?? -1;
    if (index != -1) {
      _cachedStations![index] = enriched.copyWith(
        distanceKm: _cachedStations![index].distanceKm,
      );
    }

    debugPrint(
      '[WhereCargo] Detalle ${station.id}: ${twins.length} coincidencias'
      '${cached != null ? ' (cache)' : ''}, '
      'datos completos: ${enriched.hasCompleteData}',
    );
    return enriched;
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
        // Precio desconocido va al final, no como si fuera gratis
        .map((connector) => connector.pricePerKwh ?? double.infinity)
        .toList();
    if (prices.isEmpty) return double.infinity;
    return prices.reduce(math.min);
  }

  /// Verifica si el cache es válido para usar
  bool _canUseCache(double latitude, double longitude) {
    if (_cachedStations == null || _lastFetch == null) return false;
    if (_lastLatitude == null || _lastLongitude == null) return false;

    // Verificar expiración
    final expiration =
        _lastFetchWasPartial ? _partialCacheExpiration : _cacheExpiration;
    if (DateTime.now().difference(_lastFetch!) >= expiration) {
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
  ///
  /// Con [maxCenterDistanceKm] solo se usa si el cache se guardó cerca de
  /// la ubicación pedida (para no mostrar estaciones de otra ciudad).
  Future<List<ChargingStation>?> _loadPersistentCache(
    double lat,
    double lng, {
    double? maxCenterDistanceKm,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_persistentCacheKey);
      if (jsonString == null) return null;

      // Verificar edad del cache
      final cacheTime = prefs.getInt(_persistentCacheTimeKey) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - cacheTime;
      if (age > _persistentCacheMaxAge.inMilliseconds) return null;

      if (maxCenterDistanceKm != null) {
        final cacheLat = prefs.getDouble(_persistentCacheLatKey);
        final cacheLng = prefs.getDouble(_persistentCacheLngKey);
        if (cacheLat == null || cacheLng == null) return null;
        if (_calculateDistance(lat, lng, cacheLat, cacheLng) >
            maxCenterDistanceKm) {
          return null;
        }
      }

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
  // Cache de datos del detalle
  // ---------------------------------------------------------------------------

  Future<void> _loadEnrichments() => _enrichmentsLoaded ??= _readEnrichments();

  Future<void> _readEnrichments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_enrichmentCacheKey);
      if (jsonString == null) return;
      final now = DateTime.now();
      (jsonDecode(jsonString) as Map<String, dynamic>).forEach((id, json) {
        final entry = _Enrichment.fromJson(json as Map<String, dynamic>);
        if (now.difference(entry.time) < _enrichmentMaxAge) {
          _enrichments.putIfAbsent(id, () => entry);
        }
      });
    } catch (e) {
      debugPrint('Error cargando datos de detalle: $e');
    }
  }

  void _saveEnrichments() async {
    try {
      // Se conservan solo las más recientes para acotar el tamaño
      final entries = _enrichments.entries.toList()
        ..sort((a, b) => b.value.time.compareTo(a.value.time));
      final kept = Map.fromEntries(entries.take(_enrichmentMaxEntries));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _enrichmentCacheKey,
        jsonEncode(kept.map((id, e) => MapEntry(id, e.toJson()))),
      );
    } catch (e) {
      debugPrint('Error guardando datos de detalle: $e');
    }
  }

  /// Aplica a [station] lo encontrado en una apertura anterior de su detalle.
  ChargingStation _withEnrichment(ChargingStation station) {
    final entry = _enrichments[station.id];
    if (entry == null) return station;
    return entry.twins.fold(station, _combine);
  }

  // ---------------------------------------------------------------------------
  // Fusión de fuentes
  // ---------------------------------------------------------------------------

  /// Combina dos fuentes eliminando duplicados y completando datos.
  ///
  /// Una estación de [secondary] se considera la misma que una de [primary]
  /// si están a menos de 50 m, o a menos de 150 m con nombre u operador en
  /// común (las coordenadas de cada fuente suelen diferir algunos metros).
  /// En un duplicado se conserva la de [primary], pero los datos que le
  /// falten (conectores, teléfono, operador, dirección…) se toman de la otra.
  List<ChargingStation> _mergeStations(
    List<ChargingStation> primary,
    List<ChargingStation> secondary,
  ) {
    final merged = List<ChargingStation>.from(primary);

    for (final candidate in secondary) {
      final index = merged.indexWhere((e) => _isSameStation(e, candidate));
      if (index == -1) {
        merged.add(candidate);
      } else {
        merged[index] = _combine(merged[index], candidate);
      }
    }

    return merged;
  }

  static const double _sameStationKm = 0.05;
  static const double _sameStationByNameKm = 0.15;

  bool _isSameStation(ChargingStation a, ChargingStation b) {
    final dist =
        _calculateDistance(a.latitude, a.longitude, b.latitude, b.longitude);
    if (dist < _sameStationKm) return true;
    if (dist >= _sameStationByNameKm) return false;
    final tokensA = _nameTokens(a);
    return _nameTokens(b).any(tokensA.contains);
  }

  // Palabras que aparecen en casi todos los nombres y no identifican nada
  static const Set<String> _genericWords = {
    'estacion', 'carga', 'cargador', 'cargadores', 'electrica', 'electrico',
    'electricos', 'vehiculos', 'charging', 'station', 'charger', 'point',
    'para', 'del', 'los', 'las', 'osm',
  };

  Set<String> _nameTokens(ChargingStation s) {
    return _normalizeForSearch('${s.name} ${s.networkName ?? ''}')
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length >= 3 && !_genericWords.contains(t))
        .toSet();
  }

  // Nombres que ponen las fuentes cuando la estación no tiene uno propio
  static const Set<String> _genericNames = {
    'Estación OSM',
    'Estación de carga',
    'Electric Vehicle Charging Station',
  };

  /// Completa [base] con los datos que tenga [extra] y a [base] le falten.
  ChargingStation _combine(ChargingStation base, ChargingStation extra) {
    const unavailableAddress = 'Dirección no disponible';

    final useExtraConnectors = !base.hasCompleteData && extra.hasCompleteData;

    return base.copyWith(
      name:
          _genericNames.contains(base.name) &&
              !_genericNames.contains(extra.name)
          ? extra.name
          : null,
      connectors: useExtraConnectors ? extra.connectors : null,
      address: base.address == unavailableAddress &&
              extra.address != unavailableAddress
          ? extra.address
          : null,
      city: base.city.isEmpty ? extra.city : null,
      state: base.state ?? extra.state,
      description: base.description ?? extra.description,
      networkName: base.networkName ?? extra.networkName,
      phoneNumber: base.phoneNumber ?? extra.phoneNumber,
      website: base.website ?? extra.website,
      operatingSchedule: base.operatingSchedule ?? extra.operatingSchedule,
      rating: base.rating ?? extra.rating,
      reviewCount: base.rating == null ? extra.reviewCount : null,
      googleMapsUri: base.googleMapsUri ?? extra.googleMapsUri,
      amenities: base.amenities ?? extra.amenities,
      images: base.images ?? extra.images,
      // Si los conectores vienen de la otra fuente, su precio también
      paymentType: useExtraConnectors && extra.paymentType == PaymentType.free
          ? PaymentType.free
          : null,
    );
  }
}

/// Estaciones de otras fuentes que corresponden a una estación, encontradas
/// al abrir su detalle.
class _Enrichment {
  _Enrichment(this.time, this.twins);

  final DateTime time;
  final List<ChargingStation> twins;

  factory _Enrichment.fromJson(Map<String, dynamic> json) => _Enrichment(
    DateTime.fromMillisecondsSinceEpoch(json['time'] as int),
    (json['twins'] as List<dynamic>)
        .map((t) => ChargingStation.fromJson(t as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'time': time.millisecondsSinceEpoch,
    'twins': twins.map((t) => t.toJson()).toList(),
  };
}
