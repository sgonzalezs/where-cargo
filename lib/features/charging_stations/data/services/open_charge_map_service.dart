import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../domain/models/charging_station.dart';
import '../../domain/models/connector.dart';
import '../../domain/enums/charging_enums.dart';

/// Servicio para consumir la API de Open Charge Map
/// Documentación: https://openchargemap.org/site/develop/api
class OpenChargeMapService {
  static const String _baseUrl = 'https://api.openchargemap.io/v3';
  static const String _apiKey = '03f371bb-67cf-4f3d-9caf-e2255d38cdd2';
  
  final http.Client _client;

  OpenChargeMapService({http.Client? client}) : _client = client ?? http.Client();

  /// Obtiene estaciones de carga cercanas a una ubicación
  /// 
  /// [latitude] y [longitude]: Coordenadas del centro de búsqueda
  /// [distanceKm]: Radio de búsqueda en kilómetros (default: 50)
  /// [maxResults]: Máximo número de resultados (default: 100)
  /// [countryCode]: Código ISO del país (default: CO para Colombia)
  Future<List<ChargingStation>> getNearbyStations({
    required double latitude,
    required double longitude,
    double distanceKm = 50,
    int maxResults = 100,
    String countryCode = 'CO',
  }) async {
    try {
      final queryParams = {
        'output': 'json',
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'distance': distanceKm.toString(),
        'distanceunit': 'KM',
        'maxresults': maxResults.toString(),
        'countrycode': countryCode,
        'compact': 'true',
        'verbose': 'false',
        'key': _apiKey,
      };

      final uri = Uri.parse('$_baseUrl/poi/').replace(queryParameters: queryParams);
      
      final response = await _client.get(
        uri,
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.userAgentHeader: 'WhereCargo/1.0 (Flutter App)',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data
            .map((item) => _mapToChargingStation(item as Map<String, dynamic>, latitude, longitude))
            .where((station) => station != null)
            .cast<ChargingStation>()
            .toList();
      } else {
        throw Exception('Error API OCM: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('Sin conexión a internet');
    } catch (e) {
      throw Exception('Error obteniendo estaciones: $e');
    }
  }

  /// Obtiene estaciones por ciudad colombiana
  Future<List<ChargingStation>> getStationsByCity(ColombianCity city) async {
    return getNearbyStations(
      latitude: city.latitude,
      longitude: city.longitude,
      distanceKm: 30,
      maxResults: 200,
    );
  }

  /// Busca estaciones por texto
  Future<List<ChargingStation>> searchStations({
    required String query,
    double? latitude,
    double? longitude,
    String countryCode = 'CO',
  }) async {
    try {
      final queryParams = <String, String>{
        'output': 'json',
        'countrycode': countryCode,
        'maxresults': '50',
        'compact': 'true',
      };

      // Búsqueda por nombre/dirección no es directamente soportada por OCM
      // Usamos latitude/longitude si están disponibles
      if (latitude != null && longitude != null) {
        queryParams['latitude'] = latitude.toString();
        queryParams['longitude'] = longitude.toString();
        queryParams['distance'] = '100';
        queryParams['distanceunit'] = 'KM';
      }

      if (_apiKey.isNotEmpty) {
        queryParams['key'] = _apiKey;
      }

      final uri = Uri.parse('$_baseUrl/poi/').replace(queryParameters: queryParams);
      
      final response = await _client.get(
        uri,
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        // Filtrar localmente por query
        return data
            .map((item) => _mapToChargingStation(
                item as Map<String, dynamic>, 
                latitude ?? 0, 
                longitude ?? 0,
              ))
            .where((station) => station != null)
            .cast<ChargingStation>()
            .where((station) => 
                station.name.toLowerCase().contains(query.toLowerCase()) ||
                station.address.toLowerCase().contains(query.toLowerCase()))
            .toList();
      } else {
        throw Exception('Error API OCM: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error buscando estaciones: $e');
    }
  }

  /// Convierte respuesta de OCM a nuestro modelo ChargingStation
  ChargingStation? _mapToChargingStation(
    Map<String, dynamic> data,
    double userLat,
    double userLng,
  ) {
    try {
      final addressInfo = data['AddressInfo'] as Map<String, dynamic>?;
      if (addressInfo == null) return null;

      final latitude = addressInfo['Latitude'] as num?;
      final longitude = addressInfo['Longitude'] as num?;
      if (latitude == null || longitude == null) return null;

      // Mapear conectores
      final connections = data['Connections'] as List<dynamic>? ?? [];
      final connectors = connections
          .map((conn) => _mapToConnector(conn as Map<String, dynamic>))
          .where((c) => c != null)
          .cast<Connector>()
          .toList();

      if (connectors.isEmpty) {
        // Crear conector por defecto si no hay información
        connectors.add(const Connector(
          id: 'default',
          type: ConnectorType.type2,
          chargingType: ChargingType.ac,
          powerKw: 22,
          status: ConnectorStatus.available,
        ));
      }

      // Calcular distancia
      final distanceKm = _calculateDistance(
        userLat, userLng,
        latitude.toDouble(), longitude.toDouble(),
      );

      // Obtener información del operador
      final operatorInfo = data['OperatorInfo'] as Map<String, dynamic>?;
      final networkName = operatorInfo?['Title'] as String?;
      final website = operatorInfo?['WebsiteURL'] as String?;

      // Determinar estado
      final statusType = data['StatusType'] as Map<String, dynamic>?;
      final isOperational = statusType?['IsOperational'] as bool? ?? true;

      // Información de uso/pago
      final usageType = data['UsageType'] as Map<String, dynamic>?;
      final isFree = usageType?['IsPayAtLocation'] == false && 
                     usageType?['IsMembershipRequired'] == false;

      return ChargingStation(
        id: data['ID']?.toString() ?? '',
        name: addressInfo['Title'] as String? ?? 
              '${networkName ?? 'Estación'} - ${addressInfo['Town'] ?? ''}',
        description: data['GeneralComments'] as String?,
        address: _buildAddress(addressInfo),
        city: addressInfo['Town'] as String? ?? 'Desconocida',
        state: addressInfo['StateOrProvince'] as String?,
        country: addressInfo['Country']?['Title'] as String? ?? 'Colombia',
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        connectors: connectors,
        status: isOperational ? StationStatus.available : StationStatus.offline,
        paymentType: isFree ? PaymentType.free : PaymentType.paid,
        networkName: networkName,
        website: website,
        phoneNumber: addressInfo['ContactTelephone1'] as String?,
        rating: (data['UserComments'] as List?)?.isNotEmpty == true ? 4.0 : null,
        distanceKm: distanceKm,
        lastUpdated: _parseDate(data['DateLastStatusUpdate'] as String?),
      );
    } catch (e) {
      // Si hay error mapeando, retornar null y filtrar luego
      return null;
    }
  }

  /// Mapea un conector de OCM a nuestro modelo
  Connector? _mapToConnector(Map<String, dynamic> conn) {
    try {
      final connectionTypeId = conn['ConnectionTypeID'] as int?;
      final powerKw = (conn['PowerKW'] as num?)?.toDouble() ?? 0;
      
      // Determinar tipo de conector basado en ConnectionTypeID de OCM
      final connectorType = _mapConnectionType(connectionTypeId);
      final chargingType = _getChargingType(connectionTypeId, powerKw);

      // Estado del conector
      final statusTypeId = conn['StatusTypeID'] as int?;
      final connectorStatus = _mapConnectorStatus(statusTypeId);

      return Connector(
        id: conn['ID']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        type: connectorType,
        chargingType: chargingType,
        powerKw: powerKw > 0 ? powerKw : (chargingType == ChargingType.dc ? 50 : 22),
        status: connectorStatus,
      );
    } catch (e) {
      return null;
    }
  }

  /// Mapea ConnectionTypeID de OCM a nuestro ConnectorType
  ConnectorType _mapConnectionType(int? typeId) {
    // https://openchargemap.org/site/develop/api#reference-data
    switch (typeId) {
      case 1:  // Type 1 (J1772)
        return ConnectorType.type1;
      case 2:  // CHAdeMO
        return ConnectorType.chademo;
      case 25: // Type 2 (Socket Only)
      case 1036: // Type 2 (Tethered Connector)
        return ConnectorType.type2;
      case 27: // Tesla Supercharger
      case 30: // Tesla (Model S/X)
      case 8:  // Tesla (Roadster)
        return ConnectorType.tesla;
      case 32: // CCS (Type 1)
        return ConnectorType.ccs1;
      case 33: // CCS (Type 2)
        return ConnectorType.ccs2;
      case 3:  // Type 1 + Type 2 combo
        return ConnectorType.type2;
      default:
        return ConnectorType.type2;
    }
  }

  /// Determina si es AC o DC basado en el tipo y potencia
  ChargingType _getChargingType(int? typeId, double powerKw) {
    // CHAdeMO, CCS, Tesla Supercharger son DC
    if (typeId == 2 || typeId == 32 || typeId == 33 || typeId == 27) {
      return ChargingType.dc;
    }
    // Si la potencia es alta (>22kW), probablemente es DC
    if (powerKw > 22) {
      return ChargingType.dc;
    }
    return ChargingType.ac;
  }

  /// Mapea StatusTypeID de OCM a ConnectorStatus
  ConnectorStatus _mapConnectorStatus(int? statusId) {
    // https://openchargemap.org/site/develop/api#reference-data
    switch (statusId) {
      case 50: // Operational
      case 0:  // Unknown but assume available
        return ConnectorStatus.available;
      case 30: // Temporarily Unavailable
      case 75: // Partly Operational
        return ConnectorStatus.occupied;
      case 100: // Not Operational
      case 150: // Planned For Future
      case 200: // Removed
        return ConnectorStatus.unavailable;
      default:
        return ConnectorStatus.available;
    }
  }

  /// Construye dirección legible
  String _buildAddress(Map<String, dynamic> addressInfo) {
    final parts = <String>[];
    
    final addressLine1 = addressInfo['AddressLine1'] as String?;
    final addressLine2 = addressInfo['AddressLine2'] as String?;
    final town = addressInfo['Town'] as String?;
    
    if (addressLine1?.isNotEmpty == true) parts.add(addressLine1!);
    if (addressLine2?.isNotEmpty == true) parts.add(addressLine2!);
    if (parts.isEmpty && town?.isNotEmpty == true) parts.add(town!);
    
    return parts.isNotEmpty ? parts.join(', ') : 'Dirección no disponible';
  }

  /// Calcula distancia entre dos puntos usando Haversine
  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371; // km
    
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Parsea fecha ISO
  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      return null;
    }
  }

  /// Obtiene una estación específica por su ID
  /// Útil para refrescar datos de una estación
  Future<ChargingStation?> getStationById({
    required String stationId,
    double? userLat,
    double? userLng,
  }) async {
    try {
      final queryParams = {
        'output': 'json',
        'chargepointid': stationId,
        'compact': 'true',
        'verbose': 'false',
        'key': _apiKey,
      };

      final uri = Uri.parse('$_baseUrl/poi/').replace(queryParameters: queryParams);
      
      final response = await _client.get(
        uri,
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.userAgentHeader: 'WhereCargo/1.0 (Flutter App)',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isEmpty) return null;
        
        return _mapToChargingStation(
          data.first as Map<String, dynamic>,
          userLat ?? 0,
          userLng ?? 0,
        );
      } else {
        throw Exception('Error API OCM: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('Sin conexión a internet');
    } catch (e) {
      throw Exception('Error obteniendo estación: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}
