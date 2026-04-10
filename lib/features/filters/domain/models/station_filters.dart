import '../../../charging_stations/domain/enums/charging_enums.dart';

/// Modelo de filtros para búsqueda de estaciones
class StationFilters {
  final String? searchQuery;
  final String? city;
  final Set<ConnectorType> connectorTypes;
  final Set<ChargingType> chargingTypes;
  final Set<ChargingSpeed> chargingSpeeds;
  final double? minPowerKw;
  final double? maxPowerKw;
  final bool? isFree;
  final bool? isAvailable;
  final bool? isOpenNow;
  final double? maxDistanceKm;
  final SortOption sortBy;

  const StationFilters({
    this.searchQuery,
    this.city,
    this.connectorTypes = const {},
    this.chargingTypes = const {},
    this.chargingSpeeds = const {},
    this.minPowerKw,
    this.maxPowerKw,
    this.isFree,
    this.isAvailable,
    this.isOpenNow,
    this.maxDistanceKm,
    this.sortBy = SortOption.distance,
  });

  bool get hasActiveFilters =>
      searchQuery?.isNotEmpty == true ||
      city != null ||
      connectorTypes.isNotEmpty ||
      chargingTypes.isNotEmpty ||
      chargingSpeeds.isNotEmpty ||
      minPowerKw != null ||
      maxPowerKw != null ||
      isFree != null ||
      isAvailable != null ||
      isOpenNow != null ||
      maxDistanceKm != null;

  int get activeFilterCount {
    int count = 0;
    if (searchQuery?.isNotEmpty == true) count++;
    if (city != null) count++;
    count += connectorTypes.length;
    count += chargingTypes.length;
    count += chargingSpeeds.length;
    if (minPowerKw != null || maxPowerKw != null) count++;
    if (isFree != null) count++;
    if (isAvailable != null) count++;
    if (isOpenNow != null) count++;
    if (maxDistanceKm != null) count++;
    return count;
  }

  StationFilters copyWith({
    String? searchQuery,
    String? city,
    Set<ConnectorType>? connectorTypes,
    Set<ChargingType>? chargingTypes,
    Set<ChargingSpeed>? chargingSpeeds,
    double? minPowerKw,
    double? maxPowerKw,
    bool? isFree,
    bool? isAvailable,
    bool? isOpenNow,
    double? maxDistanceKm,
    SortOption? sortBy,
    bool clearCity = false,
    bool clearMinPower = false,
    bool clearMaxPower = false,
    bool clearIsFree = false,
    bool clearIsAvailable = false,
    bool clearIsOpenNow = false,
    bool clearMaxDistance = false,
  }) {
    return StationFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      city: clearCity ? null : (city ?? this.city),
      connectorTypes: connectorTypes ?? this.connectorTypes,
      chargingTypes: chargingTypes ?? this.chargingTypes,
      chargingSpeeds: chargingSpeeds ?? this.chargingSpeeds,
      minPowerKw: clearMinPower ? null : (minPowerKw ?? this.minPowerKw),
      maxPowerKw: clearMaxPower ? null : (maxPowerKw ?? this.maxPowerKw),
      isFree: clearIsFree ? null : (isFree ?? this.isFree),
      isAvailable: clearIsAvailable ? null : (isAvailable ?? this.isAvailable),
      isOpenNow: clearIsOpenNow ? null : (isOpenNow ?? this.isOpenNow),
      maxDistanceKm: clearMaxDistance ? null : (maxDistanceKm ?? this.maxDistanceKm),
      sortBy: sortBy ?? this.sortBy,
    );
  }

  /// Limpia todos los filtros
  StationFilters clear() {
    return const StationFilters();
  }

  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{};

    if (searchQuery?.isNotEmpty == true) params['q'] = searchQuery;
    if (city != null) params['city'] = city;
    if (connectorTypes.isNotEmpty) {
      params['connector_types'] = connectorTypes.map((t) => t.apiValue).join(',');
    }
    if (chargingTypes.isNotEmpty) {
      params['charging_types'] = chargingTypes.map((t) => t.apiValue).join(',');
    }
    if (minPowerKw != null) params['min_power_kw'] = minPowerKw;
    if (maxPowerKw != null) params['max_power_kw'] = maxPowerKw;
    if (isFree != null) params['is_free'] = isFree;
    if (isAvailable != null) params['is_available'] = isAvailable;
    if (isOpenNow != null) params['is_open_now'] = isOpenNow;
    if (maxDistanceKm != null) params['max_distance_km'] = maxDistanceKm;
    params['sort_by'] = sortBy.apiValue;

    return params;
  }
}

/// Opciones de ordenamiento
enum SortOption {
  distance('Distancia', 'distance'),
  rating('Calificación', 'rating'),
  power('Potencia', 'power'),
  availability('Disponibilidad', 'availability'),
  price('Precio', 'price');

  final String displayName;
  final String apiValue;

  const SortOption(this.displayName, this.apiValue);
}
