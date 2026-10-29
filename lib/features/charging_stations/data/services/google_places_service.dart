import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/app_env.dart';
import '../../domain/models/charging_station.dart';
import '../../domain/models/connector.dart';
import '../../domain/models/operating_hours.dart';
import '../../domain/enums/charging_enums.dart';

/// Servicio para obtener estaciones de carga desde Google Places API (New).
///
/// Documentación: https://developers.google.com/maps/documentation/places/web-service/nearby-search
/// Usa el endpoint v1 (Places API New) con el tipo `electric_vehicle_charging_station`.
class GooglePlacesService {
  static const String _baseUrl = 'https://places.googleapis.com/v1';
  // La key se inyecta con --dart-define-from-file (ver AppEnv).
  // Cuando exista un backend propio, esta llamada debe moverse allí.
  static const String _apiKey = AppEnv.googlePlacesApiKey;
  static const String _sourcePrefix = 'gpl_';

  // Campos que pedimos a la API (FieldMask). `evChargeOptions` ya ubica la
  // consulta en la SKU Enterprise + Atmosphere, así que horario, calificación
  // y enlace de Maps no suben el costo.
  static const String _placeFields =
      'places.id,places.displayName,places.formattedAddress,'
      'places.location,places.businessStatus,places.evChargeOptions,'
      'places.nationalPhoneNumber,places.websiteUri,places.rating,'
      'places.userRatingCount,places.regularOpeningHours.periods,'
      'places.googleMapsUri';
  static const String _fieldMask = '$_placeFields,nextPageToken';

  /// Radio en que se busca el lugar de Google de una estación ya conocida.
  static const double _nearbyMatchRadiusMeters = 150;

  /// Text Search devuelve 20 resultados por página y hasta 3 páginas (60).
  /// Cada página se factura, por eso se limita aquí.
  static const int _maxPages = 3;

  final http.Client _client;

  GooglePlacesService({http.Client? client}) : _client = client ?? http.Client();

  /// Obtiene estaciones EV cercanas usando Text Search de la Places API (New).
  ///
  /// Se usa Text Search en lugar de Nearby Search porque permite paginar
  /// (Nearby está limitado a 20 resultados).
  /// [radiusMeters]: Radio de búsqueda; se convierte a un rectángulo.
  /// Lanza excepción si la API falla, para que el repositorio sepa que el
  /// resultado es parcial.
  Future<List<ChargingStation>> getNearbyStations({
    required double latitude,
    required double longitude,
    int radiusMeters = 50000,
  }) async {
    // Sin key es un error de compilación, no "cero estaciones": se reporta
    // como fallo para que la app no muestre "no hay estaciones cerca".
    if (_apiKey.isEmpty) {
      throw Exception('GOOGLE_PLACES_API_KEY no definida en la compilación');
    }

    // Text Search solo admite restricción por rectángulo
    final radiusKm = radiusMeters / 1000;
    final dLat = radiusKm / 111.32;
    final dLng = radiusKm / (111.32 * math.cos(_toRad(latitude)));
    final request = <String, dynamic>{
      'textQuery': 'estación de carga para vehículos eléctricos',
      'includedType': 'electric_vehicle_charging_station',
      'strictTypeFiltering': true,
      'pageSize': 20,
      'locationRestriction': {
        'rectangle': {
          'low': {'latitude': latitude - dLat, 'longitude': longitude - dLng},
          'high': {'latitude': latitude + dLat, 'longitude': longitude + dLng},
        },
      },
    };

    final stations = <ChargingStation>[];
    try {
      String? pageToken;
      for (var page = 0; page < _maxPages; page++) {
        final body = {...request, if (pageToken != null) 'pageToken': pageToken};
        final response = await _client
            .post(
              Uri.parse('$_baseUrl/places:searchText'),
              headers: {
                HttpHeaders.contentTypeHeader: 'application/json',
                'X-Goog-Api-Key': _apiKey,
                'X-Goog-FieldMask': _fieldMask,
              },
              body: json.encode(body),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          final snippet = response.body
              .substring(0, response.body.length.clamp(0, 300));
          // Si ya hay páginas cargadas, devolver lo obtenido
          if (stations.isNotEmpty) break;
          throw Exception('Google Places HTTP ${response.statusCode}: $snippet');
        }

        final data = json.decode(response.body) as Map<String, dynamic>;
        final places = data['places'] as List<dynamic>? ?? [];
        stations.addAll(places
            .map((p) => _mapToChargingStation(
                  p as Map<String, dynamic>,
                  latitude,
                  longitude,
                ))
            .whereType<ChargingStation>());

        pageToken = data['nextPageToken'] as String?;
        if (pageToken == null) break;
      }
      debugPrint('[WhereCargo] Google Places: ${stations.length} resultados');
      return stations;
    } on SocketException {
      throw Exception('Sin conexión a internet');
    } catch (e) {
      // Un timeout en la página 2 o 3 no debe descartar las anteriores
      if (stations.isNotEmpty) return stations;
      rethrow;
    }
  }

  /// Busca en Google la estación ubicada en [latitude], [longitude].
  ///
  /// Se usa al abrir el detalle de una estación de OCM u OSM: la búsqueda por
  /// nombre alrededor del punto encuentra lugares que la carga por zona no
  /// trajo (Text Search devuelve máximo 60 por zona). El repositorio decide
  /// cuál de los resultados es la misma estación.
  Future<List<ChargingStation>> findStationsNear({
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('GOOGLE_PLACES_API_KEY no definida en la compilación');
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/places:searchText'),
            headers: {
              HttpHeaders.contentTypeHeader: 'application/json',
              'X-Goog-Api-Key': _apiKey,
              'X-Goog-FieldMask': _placeFields,
            },
            body: json.encode({
              'textQuery': name,
              'includedType': 'electric_vehicle_charging_station',
              'pageSize': 5,
              'locationBias': {
                'circle': {
                  'center': {'latitude': latitude, 'longitude': longitude},
                  'radius': _nearbyMatchRadiusMeters,
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Google Places HTTP ${response.statusCode}');
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      return (data['places'] as List<dynamic>? ?? [])
          .map((p) => _mapToChargingStation(
                p as Map<String, dynamic>,
                latitude,
                longitude,
              ))
          .whereType<ChargingStation>()
          .toList();
    } on SocketException {
      throw Exception('Sin conexión a internet');
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
        rating: (place['rating'] as num?)?.toDouble(),
        reviewCount: (place['userRatingCount'] as num?)?.toInt(),
        googleMapsUri: place['googleMapsUri'] as String?,
        operatingSchedule: parseOpeningHours(
          place['regularOpeningHours'] as Map<String, dynamic>?,
        ),
        distanceKm: distanceKm,
      );
    } catch (_) {
      return null;
    }
  }

  /// Convierte `regularOpeningHours.periods` de Google en un horario semanal.
  ///
  /// Google usa día 0 = domingo y omite `close` cuando abre 24/7. Si un día
  /// tiene varios turnos se toma desde el primero hasta el último, y un turno
  /// que pasa de medianoche se muestra hasta las 23:59.
  @visibleForTesting
  static OperatingSchedule? parseOpeningHours(Map<String, dynamic>? hours) {
    final periods = hours?['periods'] as List<dynamic>?;
    if (periods == null || periods.isEmpty) return null;

    String time(Map<String, dynamic> point) =>
        '${(point['hour'] as num? ?? 0).toString().padLeft(2, '0')}:'
        '${(point['minute'] as num? ?? 0).toString().padLeft(2, '0')}';

    final opens = <int, String>{};
    final closes = <int, String>{};
    for (final raw in periods) {
      final open = (raw as Map<String, dynamic>)['open'] as Map<String, dynamic>?;
      if (open == null) continue;
      final close = raw['close'] as Map<String, dynamic>?;
      if (close == null) return OperatingSchedule.default24x7();

      final googleDay = (open['day'] as num?)?.toInt() ?? 0;
      final day = googleDay == 0 ? 7 : googleDay;
      final openTime = time(open);
      final closeTime = (close['day'] as num?)?.toInt() == googleDay
          ? time(close)
          : '23:59';
      if (opens[day] == null || openTime.compareTo(opens[day]!) < 0) {
        opens[day] = openTime;
      }
      if (closes[day] == null || closeTime.compareTo(closes[day]!) > 0) {
        closes[day] = closeTime;
      }
    }
    if (opens.isEmpty) return null;

    return OperatingSchedule(
      hours: List.generate(7, (i) {
        final day = i + 1;
        final open = opens[day];
        if (open == null) {
          return OperatingHours(
            dayOfWeek: day,
            openTime: '00:00',
            closeTime: '00:00',
            isClosed: true,
          );
        }
        final close = closes[day]!;
        return OperatingHours(
          dayOfWeek: day,
          openTime: open,
          closeTime: close,
          is24Hours: open == '00:00' && close == '23:59',
        );
      }),
    );
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

    // La API (New) devuelve los conectores agrupados en `connectorAggregation`
    final connectorList =
        evChargeOptions['connectorAggregation'] as List<dynamic>? ?? [];

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
      // Disponibilidad en tiempo real: solo existe para algunas redes
      final availableCount = (c['availableCount'] as num?)?.toInt();
      final outOfService = (c['outOfServiceCount'] as num?)?.toInt() ?? 0;

      // Tomacorrientes domésticos no sirven como punto de carga EV
      if (typeStr == 'EV_CONNECTOR_TYPE_UNSPECIFIED_WALL_OUTLET') continue;

      final connType = _mapConnectorType(typeStr, maxRate);
      final chargingType = _inferChargingType(connType, maxRate);
      final powerKw = maxRate > 0 ? maxRate : _defaultPowerKw(connType);

      for (int i = 0; i < count; i++) {
        final ConnectorStatus status;
        if (availableCount == null) {
          status = ConnectorStatus.available;
        } else if (i < availableCount) {
          status = ConnectorStatus.available;
        } else if (i < availableCount + outOfService) {
          status = ConnectorStatus.unavailable;
        } else {
          status = ConnectorStatus.occupied;
        }
        connectors.add(Connector(
          id: '${stationId}_conn_${index++}',
          type: connType,
          chargingType: chargingType,
          powerKw: powerKw,
          status: status,
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

  ConnectorType _mapConnectorType(String typeStr, double maxRateKw) {
    switch (typeStr) {
      case 'EV_CONNECTOR_TYPE_NACS':
        return ConnectorType.tesla;
      case 'EV_CONNECTOR_TYPE_UNSPECIFIED_GB_T':
        return maxRateKw > 22 ? ConnectorType.gbtDc : ConnectorType.gbtAc;
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
      case ConnectorType.gbtDc:
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
