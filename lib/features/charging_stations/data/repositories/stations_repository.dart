import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/models/charging_station.dart';

/// Repositorio para estaciones de carga
class StationsRepository {
  final ApiClient _apiClient;

  StationsRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Obtiene todas las estaciones
  Future<List<ChargingStation>> getAllStations({
    int? limit,
    int? offset,
  }) async {
    final queryParams = <String, dynamic>{};
    if (limit != null) queryParams['limit'] = limit;
    if (offset != null) queryParams['offset'] = offset;

    final response = await _apiClient.get(
      ApiConstants.stations,
      queryParams: queryParams.isEmpty ? null : queryParams,
    );

    final List<dynamic> data = response['data'] ?? response;
    return data
        .map((json) => ChargingStation.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Obtiene una estación por ID
  Future<ChargingStation> getStationById(String id) async {
    final endpoint = ApiConstants.stationDetail.replaceAll('{id}', id);
    final response = await _apiClient.get(endpoint);

    return ChargingStation.fromJson(
      response['data'] ?? response as Map<String, dynamic>,
    );
  }

  /// Obtiene estaciones cercanas a una ubicación
  Future<List<ChargingStation>> getNearbyStations({
    required double latitude,
    required double longitude,
    double? radiusKm,
    int? limit,
  }) async {
    final queryParams = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
    };
    if (radiusKm != null) queryParams['radius_km'] = radiusKm;
    if (limit != null) queryParams['limit'] = limit;

    final response = await _apiClient.get(
      ApiConstants.nearbyStations,
      queryParams: queryParams,
    );

    final List<dynamic> data = response['data'] ?? response;
    return data
        .map((json) => ChargingStation.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Busca estaciones con filtros
  Future<List<ChargingStation>> searchStations({
    String? query,
    String? city,
    List<String>? connectorTypes,
    List<String>? chargingTypes,
    double? minPowerKw,
    double? maxPowerKw,
    bool? isFree,
    bool? isAvailable,
    bool? isOpenNow,
    double? latitude,
    double? longitude,
    double? radiusKm,
    String? sortBy,
    String? sortOrder,
    int? limit,
    int? offset,
  }) async {
    final queryParams = <String, dynamic>{};

    if (query != null && query.isNotEmpty) queryParams['q'] = query;
    if (city != null) queryParams['city'] = city;
    if (connectorTypes != null && connectorTypes.isNotEmpty) {
      queryParams['connector_types'] = connectorTypes.join(',');
    }
    if (chargingTypes != null && chargingTypes.isNotEmpty) {
      queryParams['charging_types'] = chargingTypes.join(',');
    }
    if (minPowerKw != null) queryParams['min_power_kw'] = minPowerKw;
    if (maxPowerKw != null) queryParams['max_power_kw'] = maxPowerKw;
    if (isFree != null) queryParams['is_free'] = isFree;
    if (isAvailable != null) queryParams['is_available'] = isAvailable;
    if (isOpenNow != null) queryParams['is_open_now'] = isOpenNow;
    if (latitude != null) queryParams['latitude'] = latitude;
    if (longitude != null) queryParams['longitude'] = longitude;
    if (radiusKm != null) queryParams['radius_km'] = radiusKm;
    if (sortBy != null) queryParams['sort_by'] = sortBy;
    if (sortOrder != null) queryParams['sort_order'] = sortOrder;
    if (limit != null) queryParams['limit'] = limit;
    if (offset != null) queryParams['offset'] = offset;

    final response = await _apiClient.get(
      ApiConstants.stations,
      queryParams: queryParams,
    );

    final List<dynamic> data = response['data'] ?? response;
    return data
        .map((json) => ChargingStation.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Obtiene estaciones por ciudad
  Future<List<ChargingStation>> getStationsByCity(String city) async {
    return searchStations(city: city);
  }
}
