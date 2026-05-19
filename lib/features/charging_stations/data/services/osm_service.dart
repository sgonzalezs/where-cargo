import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../domain/models/charging_station.dart';
import '../../domain/models/connector.dart';
import '../../domain/enums/charging_enums.dart';

/// Servicio para obtener estaciones de carga desde OpenStreetMap vía Overpass API.
///
/// Completamente gratuito, sin API key. Complementa los datos de Open Charge Map.
/// Documentación: https://wiki.openstreetmap.org/wiki/Tag:amenity%3Dcharging_station
class OsmService {
  // Dos endpoints públicos de Overpass para redundancia
  static const List<String> _overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  static const String _sourcePrefix = 'osm_';

  final http.Client _client;

  OsmService({http.Client? client}) : _client = client ?? http.Client();

  /// Obtiene estaciones de carga cercanas usando la Overpass API.
  ///
  /// [radiusMeters]: Radio de búsqueda en metros (default: 50.000 = 50km)
  Future<List<ChargingStation>> getNearbyStations({
    required double latitude,
    required double longitude,
    int radiusMeters = 50000,
  }) async {
    // Query Overpass QL: nodos y vías con amenity=charging_station en el radio
    final query = '''
[out:json][timeout:25];
(
  node["amenity"="charging_station"](around:$radiusMeters,$latitude,$longitude);
  way["amenity"="charging_station"](around:$radiusMeters,$latitude,$longitude);
);
out center tags;
''';

    for (final endpoint in _overpassEndpoints) {
      try {
        final response = await _client
            .post(
              Uri.parse(endpoint),
              headers: {
                HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
                HttpHeaders.userAgentHeader: 'WhereCargo/1.0 (Flutter App)',
              },
              body: 'data=${Uri.encodeComponent(query)}',
            )
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final elements = data['elements'] as List<dynamic>? ?? [];
          return elements
              .map((e) => _mapToChargingStation(
                    e as Map<String, dynamic>,
                    latitude,
                    longitude,
                  ))
              .where((s) => s != null)
              .cast<ChargingStation>()
              .toList();
        }
      } on SocketException {
        // Sin internet — no reintentar con otro endpoint
        throw Exception('Sin conexión a internet');
      } catch (_) {
        // Falló este endpoint, intentar con el siguiente
        continue;
      }
    }

    // Ambos endpoints fallaron — devolver lista vacía en lugar de lanzar excepción
    // para que OCM siga funcionando normalmente
    return [];
  }

  ChargingStation? _mapToChargingStation(
    Map<String, dynamic> element,
    double userLat,
    double userLng,
  ) {
    try {
      // Para nodos: lat/lon directos. Para vías: usar el centroide calculado por Overpass
      final lat = (element['lat'] ?? element['center']?['lat']) as num?;
      final lon = (element['lon'] ?? element['center']?['lon']) as num?;
      if (lat == null || lon == null) return null;

      final tags = element['tags'] as Map<String, dynamic>? ?? {};
      final osmId = element['id']?.toString() ?? '';
      final type = element['type'] as String? ?? 'node';
      final id = '$_sourcePrefix${type}_$osmId';

      final name = tags['name'] as String? ??
          tags['operator'] as String? ??
          tags['brand'] as String? ??
          'Estación OSM';

      final address = _buildAddress(tags);
      final city = tags['addr:city'] as String? ?? tags['addr:town'] as String? ?? '';
      final country = tags['addr:country'] as String? ?? '';

      final connectors = _parseConnectors(tags, id);
      final distanceKm = _calculateDistance(
        userLat, userLng, lat.toDouble(), lon.toDouble(),
      );

      // Determinar si es gratuito
      final fee = tags['fee'] as String?;
      final paymentType =
          (fee == 'no') ? PaymentType.free : PaymentType.paid;

      // Operador / red
      final networkName = tags['operator'] as String? ?? tags['brand'] as String?;
      final website = tags['contact:website'] as String? ?? tags['website'] as String?;
      final phone = tags['contact:phone'] as String? ?? tags['phone'] as String?;

      return ChargingStation(
        id: id,
        name: name,
        address: address,
        city: city,
        country: country,
        latitude: lat.toDouble(),
        longitude: lon.toDouble(),
        connectors: connectors,
        status: StationStatus.available,
        paymentType: paymentType,
        networkName: networkName,
        website: website,
        phoneNumber: phone,
        distanceKm: distanceKm,
        lastUpdated: null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Construye la dirección a partir de los tags OSM
  String _buildAddress(Map<String, dynamic> tags) {
    final parts = <String>[];
    final street = tags['addr:street'] as String?;
    final number = tags['addr:housenumber'] as String?;
    if (street != null) {
      parts.add(number != null ? '$street $number' : street);
    }
    final city = tags['addr:city'] as String?;
    if (city != null) parts.add(city);
    return parts.isNotEmpty ? parts.join(', ') : 'Dirección no disponible';
  }

  /// Parsea conectores desde los tags OSM.
  ///
  /// OSM usa tags como: socket:type2, socket:ccs, socket:chademo, socket:type2_cable
  List<Connector> _parseConnectors(Map<String, dynamic> tags, String stationId) {
    final connectors = <Connector>[];
    int index = 0;

    void addConnector(ConnectorType type, ChargingType chargingType, double defaultPowerKw) {
      // Algunos mappers ponen el número de tomas como valor del tag
      final countStr = tags['socket:${_osmSocketKey(type)}'] as String?;
      final count = int.tryParse(countStr ?? '1') ?? 1;
      final powerKw = double.tryParse(
            (tags['socket:${_osmSocketKey(type)}:output'] as String?)
                    ?.replaceAll(' kW', '')
                    .replaceAll('kW', '') ??
                '',
          ) ??
          defaultPowerKw;
      for (int i = 0; i < count; i++) {
        connectors.add(Connector(
          id: '${stationId}_conn_${index++}',
          type: type,
          chargingType: chargingType,
          powerKw: powerKw,
          status: ConnectorStatus.available,
        ));
      }
    }

    if (tags.containsKey('socket:type2') || tags.containsKey('socket:type2_cable')) {
      addConnector(ConnectorType.type2, ChargingType.ac, 22);
    }
    if (tags.containsKey('socket:type1')) {
      addConnector(ConnectorType.type1, ChargingType.ac, 7.4);
    }
    if (tags.containsKey('socket:ccs')) {
      addConnector(ConnectorType.ccs2, ChargingType.dc, 50);
    }
    if (tags.containsKey('socket:ccs2')) {
      addConnector(ConnectorType.ccs2, ChargingType.dc, 50);
    }
    if (tags.containsKey('socket:chademo')) {
      addConnector(ConnectorType.chademo, ChargingType.dc, 50);
    }
    if (tags.containsKey('socket:tesla_supercharger')) {
      addConnector(ConnectorType.tesla, ChargingType.dc, 150);
    }
    if (tags.containsKey('socket:tesla_destination')) {
      addConnector(ConnectorType.teslaDestination, ChargingType.ac, 11);
    }

    // Si no se pudo determinar ningún conector específico, no fabricar
    // un Type 2 "ficticio" — marcamos un único conector como "desconocido"
    // con la capacidad declarada (si la hay) y potencia 0 para que la UI
    // muestre "Información no disponible" en lugar de inventar datos.
    if (connectors.isEmpty) {
      final capacity = int.tryParse(tags['capacity'] as String? ?? '1') ?? 1;
      for (int i = 0; i < capacity; i++) {
        connectors.add(Connector(
          id: '${stationId}_conn_${index++}',
          type: ConnectorType.unknown,
          chargingType: ChargingType.ac,
          powerKw: 0,
          status: ConnectorStatus.available,
        ));
      }
    }

    return connectors;
  }

  String _osmSocketKey(ConnectorType type) {
    switch (type) {
      case ConnectorType.type1:
        return 'type1';
      case ConnectorType.type2:
        return 'type2';
      case ConnectorType.ccs1:
        return 'ccs';
      case ConnectorType.ccs2:
        return 'ccs2';
      case ConnectorType.chademo:
        return 'chademo';
      case ConnectorType.tesla:
        return 'tesla_supercharger';
      case ConnectorType.teslaDestination:
        return 'tesla_destination';
      default:
        return 'type2';
    }
  }

  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRad(double deg) => deg * math.pi / 180;
}
