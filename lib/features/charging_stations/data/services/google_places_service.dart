import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/charging_station.dart';
import '../../domain/models/connector.dart';
import '../../domain/enums/charging_enums.dart';

/// Servicio para obtener estaciones de carga desde Google Places API (New).
///
/// Documentación: https://developers.google.com/maps/documentation/places/web-service/nearby-search
/// Usa el endpoint v1 (Places API New) con el tipo `electric_vehicle_charging_station`.
class GooglePlacesService {
  static const String _baseUrl = 'https://places.googleapis.com/v1';
  // ignore: do_not_use_environment — la key se almacena aquí para esta versión MVP;
  // en producción debe moverse a variables de entorno o a un backend propio.
  static const String _apiKey = 'AIzaSyBVU6QK4kIl0A6-bEtT0OgUgtRW6abMO2c';
  static const String _sourcePrefix = 'gpl_';

  // Campos que pedimos a la API (FieldMask)
  static const String _fieldMask =
      'places.id,places.displayName,places.formattedAddress,'
      'places.location,places.businessStatus,places.evChargeOptions,'
      'places.nationalPhoneNumber,places.websiteUri';

  final http.Client _client;

  GooglePlacesService({http.Client? client}) : _client = client ?? http.Client();

  /// Obtiene estaciones EV cercanas usando la Places API (New).
  ///
  /// [radiusMeters]: Radio de búsqueda (máx. 50.000 m según la API).
  Future<List<ChargingStation>> getNearbyStations({
    required double latitude,
    required double longitude,
    int radiusMeters = 50000,
  }) async {
    try {
      final body = json.encode({
        'includedTypes': ['electric_vehicle_charging_station'],
        'maxResultCount': 20, // máximo permitido por la API
        'locationRestriction': {
          'circle': {
            'center': {'latitude': latitude, 'longitude': longitude},
            'radius': radiusMeters.toDouble(),
          },
        },
      });

      final response = await _client
          .post(
            Uri.parse('$_baseUrl/places:searchNearby'),
            headers: {
              HttpHeaders.contentTypeHeader: 'application/json',
              'X-Goog-Api-Key': _apiKey,
              'X-Goog-FieldMask': _fieldMask,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final places = data['places'] as List<dynamic>? ?? [];
        debugPrint('[WhereCargo] Google Places: ${places.length} resultados raw');
        return places
            .map((p) => _mapToChargingStation(
                  p as Map<String, dynamic>,
                  latitude,
                  longitude,
                ))
            .where((s) => s != null)
            .cast<ChargingStation>()
            .toList();
      }

      // No lanzar excepción — devolver lista vacía para que OCM/OSM sigan funcionando
      debugPrint('[WhereCargo] Google Places HTTP ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 300))}');
      return [];
    } on SocketException {
      throw Exception('Sin conexión a internet');
    } catch (_) {
      return [];
    }
  }

  ChargingStation? _mapToChargingStation(
    Map<String, dynamic> place,
    double userLat,
    double userLng,
  ) {
    try {
      final location = place['location'] as Map<String, dynamic>?;
      if (location == null) return null;

      final lat = (location['latitude'] as num).toDouble();
      final lng = (location['longitude'] as num).toDouble();

      final placeId = place['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString();
      final id = '$_sourcePrefix$placeId';

      final displayName = place['displayName'] as Map<String, dynamic>?;
      final name = displayName?['text'] as String? ?? 'Estación de carga';

      // Google devuelve la dirección formateada completa — usarla directamente
      final formattedAddress =
          place['formattedAddress'] as String? ?? 'Dirección no disponible';

      // Extraer ciudad y país del último segmento de la dirección formateada
      final cityAndCountry = _extractCityAndCountry(formattedAddress);

      final connectors = _parseEvChargeOptions(
        place['evChargeOptions'] as Map<String, dynamic>?,
        id,
      );

      final distanceKm = _calculateDistance(userLat, userLng, lat, lng);

      final businessStatus = place['businessStatus'] as String?;
      final isOperational = businessStatus != 'CLOSED_PERMANENTLY' &&
          businessStatus != 'CLOSED_TEMPORARILY';

      return ChargingStation(
        id: id,
        name: name,
        address: formattedAddress,
        city: cityAndCountry.$1,
        country: cityAndCountry.$2,
        latitude: lat,
        longitude: lng,
        connectors: connectors,
        status: isOperational ? StationStatus.available : StationStatus.offline,
        paymentType: PaymentType.paid,
        website: place['websiteUri'] as String?,
        phoneNumber: place['nationalPhoneNumber'] as String?,
        distanceKm: distanceKm,
      );
    } catch (_) {
      return null;
    }
  }

  /// Extrae ciudad y país del último segmento de la dirección formateada de Google.
  /// Formato típico: "Carrera 43, El Poblado, Medellín, Antioquia, Colombia"
  /// Retorna (ciudad, país).
  (String, String) _extractCityAndCountry(String address) {
    final parts = address.split(',').map((s) => s.trim()).toList();
    if (parts.isEmpty) return ('', '');

    // El último segmento siempre es el país
    final country = parts.last;

    // La ciudad suele estar 2 posiciones antes del país (índice length-2)
    // Ej: [..., 'Medellín', 'Antioquia', 'Colombia'] → ciudad = 'Antioquia' (dept)
    // pero OCM/Google a veces pone ciudad antes del departamento
    // Tomamos el penúltimo antes del país como ciudad
    final city = parts.length >= 2 ? parts[parts.length - 2] : country;

    return (city, country);
  }

  List<Connector> _parseEvChargeOptions(
    Map<String, dynamic>? evChargeOptions,
    String stationId,
  ) {
    final connectors = <Connector>[];
    int index = 0;

    if (evChargeOptions == null) {
      // Google no expuso datos de conectores: marcar como desconocido en lugar
      // de inventar un Type 2 22kW que engaña al usuario.
      connectors.add(Connector(
        id: '${stationId}_conn_0',
        type: ConnectorType.unknown,
        chargingType: ChargingType.ac,
        powerKw: 0,
        status: ConnectorStatus.available,
      ));
      return connectors;
    }

    final connectorList =
        evChargeOptions['connectors'] as List<dynamic>? ?? [];

    if (connectorList.isEmpty) {
      final count =
          (evChargeOptions['connectorCount'] as num?)?.toInt() ?? 1;
      for (int i = 0; i < count; i++) {
        connectors.add(Connector(
          id: '${stationId}_conn_${index++}',
          type: ConnectorType.unknown,
          chargingType: ChargingType.ac,
          powerKw: 0,
          status: ConnectorStatus.available,
        ));
      }
      return connectors;
    }

    for (final conn in connectorList) {
      final c = conn as Map<String, dynamic>;
      final typeStr = c['type'] as String? ?? '';
      final maxRate = (c['maxChargeRateKw'] as num?)?.toDouble() ?? 0;
      final count = (c['count'] as num?)?.toInt() ?? 1;
      final availableCount = (c['availableCount'] as num?)?.toInt() ?? count;

      final connType = _mapConnectorType(typeStr);
      final chargingType = _inferChargingType(connType, maxRate);
      final powerKw = maxRate > 0 ? maxRate : _defaultPowerKw(connType);

      for (int i = 0; i < count; i++) {
        connectors.add(Connector(
          id: '${stationId}_conn_${index++}',
          type: connType,
          chargingType: chargingType,
          powerKw: powerKw,
          status: i < availableCount
              ? ConnectorStatus.available
              : ConnectorStatus.occupied,
        ));
      }
    }

    if (connectors.isEmpty) {
      connectors.add(Connector(
        id: '${stationId}_conn_0',
        type: ConnectorType.unknown,
        chargingType: ChargingType.ac,
        powerKw: 0,
        status: ConnectorStatus.available,
      ));
    }

    return connectors;
  }

  ConnectorType _mapConnectorType(String typeStr) {
    switch (typeStr) {
      case 'EV_CONNECTOR_TYPE_J1772':
        return ConnectorType.type1;
      case 'EV_CONNECTOR_TYPE_TYPE_2':
        return ConnectorType.type2;
      case 'EV_CONNECTOR_TYPE_CHADEMO':
        return ConnectorType.chademo;
      case 'EV_CONNECTOR_TYPE_CCS_COMBO_1':
        return ConnectorType.ccs1;
      case 'EV_CONNECTOR_TYPE_CCS_COMBO_2':
        return ConnectorType.ccs2;
      case 'EV_CONNECTOR_TYPE_TESLA':
        return ConnectorType.tesla;
      default:
        return ConnectorType.unknown;
    }
  }

  ChargingType _inferChargingType(ConnectorType type, double powerKw) {
    switch (type) {
      case ConnectorType.ccs1:
      case ConnectorType.ccs2:
      case ConnectorType.chademo:
      case ConnectorType.tesla:
        return ChargingType.dc;
      default:
        return powerKw > 22 ? ChargingType.dc : ChargingType.ac;
    }
  }

  double _defaultPowerKw(ConnectorType type) {
    switch (type) {
      case ConnectorType.ccs1:
      case ConnectorType.ccs2:
      case ConnectorType.chademo:
        return 50;
      case ConnectorType.tesla:
        return 150;
      default:
        return 22;
    }
  }

  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _toRad(double deg) => deg * math.pi / 180;
}
