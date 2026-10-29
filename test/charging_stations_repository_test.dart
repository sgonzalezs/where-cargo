import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:where_cargo/features/charging_stations/data/repositories/charging_stations_repository.dart';
import 'package:where_cargo/features/charging_stations/data/services/google_places_service.dart';
import 'package:where_cargo/features/charging_stations/data/services/open_charge_map_service.dart';
import 'package:where_cargo/features/charging_stations/data/services/osm_service.dart';
import 'package:where_cargo/features/charging_stations/domain/enums/charging_enums.dart';
import 'package:where_cargo/features/charging_stations/domain/models/charging_station.dart';
import 'package:where_cargo/features/charging_stations/domain/models/connector.dart';
import 'package:where_cargo/features/charging_stations/domain/models/operating_hours.dart';

ChargingStation _station(
  String id, {
  double lat = 6.2442,
  double lng = -75.5812,
  List<Connector>? connectors,
  PaymentType paymentType = PaymentType.paid,
}) {
  return ChargingStation(
    id: id,
    name: 'Estación $id',
    address: 'Calle 1',
    city: 'Medellín',
    latitude: lat,
    longitude: lng,
    connectors: connectors ??
        const [
          Connector(
            id: 'c1',
            type: ConnectorType.type2,
            chargingType: ChargingType.ac,
            powerKw: 22,
            status: ConnectorStatus.available,
          ),
        ],
    status: StationStatus.available,
    paymentType: paymentType,
  );
}

class _FakeOcm extends OpenChargeMapService {
  _FakeOcm(this.result, [this.byId]);
  final Future<List<ChargingStation>> Function() result;
  final Future<ChargingStation?> Function()? byId;

  @override
  Future<ChargingStation?> getStationById({
    required String stationId,
    double? userLat,
    double? userLng,
  }) => byId?.call() ?? Future.value(null);

  @override
  Future<List<ChargingStation>> getNearbyStations({
    required double latitude,
    required double longitude,
    double distanceKm = 50,
    int maxResults = 500,
  }) => result();
}

class _FakeOsm extends OsmService {
  _FakeOsm(this.result);
  final Future<List<ChargingStation>> Function() result;

  @override
  Future<List<ChargingStation>> getNearbyStations({
    required double latitude,
    required double longitude,
    int radiusMeters = 50000,
  }) => result();
}

class _FakeGoogle extends GooglePlacesService {
  _FakeGoogle(this.result, [this.near]);
  final Future<List<ChargingStation>> Function() result;
  final Future<List<ChargingStation>> Function()? near;

  @override
  Future<List<ChargingStation>> findStationsNear({
    required String name,
    required double latitude,
    required double longitude,
  }) => near?.call() ?? Future.value(const []);

  @override
  Future<List<ChargingStation>> getNearbyStations({
    required double latitude,
    required double longitude,
    int radiusMeters = 50000,
  }) => result();
}

ChargingStationsRepository _repo({
  Future<List<ChargingStation>> Function()? ocm,
  Future<List<ChargingStation>> Function()? osm,
  Future<List<ChargingStation>> Function()? google,
  Future<List<ChargingStation>> Function()? googleNear,
  Future<ChargingStation?> Function()? ocmById,
  Duration partialCacheExpiration = const Duration(minutes: 2),
}) {
  Future<List<ChargingStation>> empty() async => [];
  return ChargingStationsRepository.withServices(
    ocmService: _FakeOcm(ocm ?? empty, ocmById),
    osmService: _FakeOsm(osm ?? empty),
    googlePlacesService: _FakeGoogle(google ?? empty, googleNear),
    partialCacheExpiration: partialCacheExpiration,
  );
}

const _unknownConnector = [
  Connector(
    id: 'u',
    type: ConnectorType.unknown,
    chargingType: ChargingType.ac,
    powerKw: 0,
    status: ConnectorStatus.available,
  ),
];

/// Simula el cache persistente que dejó una carga anterior en Medellín.
void _seedPersistentCache(List<ChargingStation> stations) {
  SharedPreferences.setMockInitialValues({
    'station_cache_v6': jsonEncode(stations.map((s) => s.toJson()).toList()),
    'station_cache_lat_v6': 6.2442,
    'station_cache_lng_v6': -75.5812,
    'station_cache_time_v6': DateTime.now().millisecondsSinceEpoch,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('getNearbyStations', () {
    test('si OCM falla, conserva los resultados de OSM y Google', () async {
      final repo = _repo(
        ocm: () async => throw Exception('OCM caído'),
        osm: () async => [_station('osm_1', lat: 6.20)],
        google: () async => [_station('gpl_1', lat: 6.30)],
      );

      final result =
          await repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      expect(result.map((s) => s.id), containsAll(['osm_1', 'gpl_1']));
    });

    test('vacío porque las demás fuentes fallaron cuenta como error', () async {
      final repo = _repo(
        ocm: () async => throw Exception('OCM_API_KEY no definida'),
        osm: () async => throw Exception('Overpass caído'),
        google: () async => [],
      );

      expect(
        repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812),
        throwsException,
      );
    });

    test('si todas las fuentes fallan y no hay cache, lanza error', () async {
      final repo = _repo(
        ocm: () async => throw Exception('a'),
        osm: () async => throw Exception('b'),
        google: () async => throw Exception('c'),
      );

      expect(
        repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812),
        throwsException,
      );
    });

    test('elimina duplicados a menos de 50 m priorizando OCM', () async {
      final repo = _repo(
        ocm: () async => [_station('1')],
        // ~10 m de distancia de la estación OCM
        osm: () async => [_station('osm_1', lat: 6.2443)],
      );

      final result =
          await repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      expect(result.map((s) => s.id), ['1']);
    });

    test('un resultado parcial expira antes que uno completo', () async {
      var ocmCalls = 0;
      final repo = _repo(
        partialCacheExpiration: Duration.zero,
        osm: () async => [_station('osm_1', lat: 6.30)],
        ocm: () async {
          ocmCalls++;
          if (ocmCalls == 1) throw Exception('OCM caído');
          return [_station('1')];
        },
      );

      await repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812);
      final second =
          await repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      expect(ocmCalls, 2);
      expect(second.map((s) => s.id), ['1', 'osm_1']);
    });

    test('un resultado completo se reutiliza sin volver a consultar', () async {
      var ocmCalls = 0;
      final repo = _repo(ocm: () async {
        ocmCalls++;
        return [_station('1')];
      });

      await repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812);
      await repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      expect(ocmCalls, 1);
    });
  });

  group('watchNearbyStations (carga progresiva)', () {
    test('emite cada fuente apenas responde, sin esperar a la más lenta',
        () async {
      final osmGate = Completer<List<ChargingStation>>();
      final repo = _repo(
        ocm: () async => [_station('1')],
        osm: () => osmGate.future,
      );

      final emissions = <List<String>>[];
      final subscription = repo
          .watchNearbyStations(latitude: 6.2442, longitude: -75.5812)
          .listen((s) => emissions.add(s.map((e) => e.id).toList()));

      // OSM sigue sin responder, pero OCM ya está en pantalla
      await pumpEventQueue();
      expect(emissions, isNotEmpty);
      expect(emissions.last, ['1']);

      osmGate.complete([_station('osm_9', lat: 6.30)]);
      await subscription.asFuture<void>();
      expect(emissions.last, ['1', 'osm_9']);
    });

    test('muestra el cache de la zona antes de consultar las fuentes',
        () async {
      _seedPersistentCache([_station('osm_cache', lat: 6.25)]);
      final ocmGate = Completer<List<ChargingStation>>();
      final repo = _repo(ocm: () => ocmGate.future);

      final first = await repo
          .watchNearbyStations(latitude: 6.2442, longitude: -75.5812)
          .first;

      expect(first.map((s) => s.id), ['osm_cache']);
      ocmGate.complete([]);
    });

    test('si una fuente falla, conserva sus estaciones del cache', () async {
      _seedPersistentCache([
        _station('1'),
        _station('osm_cache', lat: 6.30),
      ]);
      final repo = _repo(
        ocm: () async => [_station('1')],
        osm: () async => throw Exception('Overpass saturado'),
      );

      final result =
          await repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      expect(result.map((s) => s.id), containsAll(['1', 'osm_cache']));
    });

    test('no muestra el cache si se guardó en otra ciudad', () async {
      _seedPersistentCache([_station('osm_medellin', lat: 6.25)]);
      final repo = _repo(ocm: () async => [_station('bogota', lat: 4.71)]);

      // Bogotá
      final first = await repo
          .watchNearbyStations(latitude: 4.7110, longitude: -74.0721)
          .first;

      expect(first.map((s) => s.id), ['bogota']);
    });
  });

  group('fusión de fuentes', () {
    test('una estación OSM sin conectores toma los de Google', () async {
      final repo = _repo(
        google: () async => [
          _station('gpl_1').copyWith(name: 'Celsia Charging Station'),
        ],
        // ~100 m de distancia, mismo operador en el nombre
        osm: () async => [
          _station('osm_1', lat: 6.2451, connectors: _unknownConnector)
              .copyWith(name: 'Celsia', phoneNumber: '+57 300'),
        ],
      );

      final result =
          await repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      final station = result.single;
      expect(station.id, 'gpl_1');
      expect(station.hasCompleteData, isTrue);
      expect(station.phoneNumber, '+57 300'); // dato que solo tenía OSM
    });

    test('la estación principal sin datos se completa con la secundaria',
        () async {
      final repo = _repo(
        google: () async =>
            [_station('gpl_1', connectors: _unknownConnector)],
        osm: () async => [_station('osm_1', lat: 6.2443)],
      );

      final result =
          await repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      expect(result.single.id, 'gpl_1');
      expect(result.single.connectorTypes, {ConnectorType.type2});
    });

    test('a 100 m con nombres distintos son estaciones diferentes', () async {
      final repo = _repo(
        google: () async => [_station('gpl_1').copyWith(name: 'EPM Laureles')],
        osm: () async => [
          _station('osm_1', lat: 6.2451).copyWith(name: 'Terpel Voltex'),
        ],
      );

      final result =
          await repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      expect(result, hasLength(2));
    });
  });

  group('enrichStation (detalle)', () {
    test('una estación de Google sin conectores los toma de OSM cercano',
        () async {
      final repo = _repo(
        osm: () async => [
          _station('osm_1', lat: 6.2443),
          // A 1 km: es otra estación
          _station('osm_2', lat: 6.2532).copyWith(phoneNumber: '+57 999'),
        ],
      );
      final station = _station('gpl_1', connectors: _unknownConnector);

      final enriched = await repo.enrichStation(station);

      expect(enriched.id, 'gpl_1');
      expect(enriched.hasCompleteData, isTrue);
      expect(enriched.phoneNumber, isNull);
    });

    test('una estación de OSM toma horario y calificación de Google',
        () async {
      final repo = _repo(
        googleNear: () async => [
          _station('gpl_1', lat: 6.2443).copyWith(
            rating: 4.5,
            reviewCount: 12,
            operatingSchedule: OperatingSchedule.default24x7(),
            googleMapsUri: 'https://maps.google.com/?cid=1',
          ),
        ],
      );

      final enriched = await repo.enrichStation(
        _station('osm_1', connectors: _unknownConnector),
      );

      expect(enriched.hasCompleteData, isTrue);
      expect(enriched.rating, 4.5);
      expect(enriched.reviewCount, 12);
      expect(enriched.operatingSchedule?.is24x7, isTrue);
      expect(enriched.googleMapsUri, 'https://maps.google.com/?cid=1');
    });

    test('no repite la búsqueda facturada y aplica lo encontrado al mapa',
        () async {
      var googleCalls = 0;
      final repo = _repo(
        ocm: () async => [_station('1', connectors: _unknownConnector)],
        googleNear: () async {
          googleCalls++;
          return [_station('gpl_1', lat: 6.2443)];
        },
      );
      final loaded =
          await repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812);
      expect(loaded.single.hasCompleteData, isFalse);

      await repo.enrichStation(loaded.single);
      final again = await repo.enrichStation(loaded.single);
      expect(googleCalls, 1);
      expect(again.hasCompleteData, isTrue);

      // Una carga nueva (sin cache en memoria) ya trae la estación completa
      repo.clearCache();
      final reloaded =
          await repo.getNearbyStations(latitude: 6.2442, longitude: -75.5812);
      expect(reloaded.single.hasCompleteData, isTrue);
    });

    test('si una fuente falla no guarda el resultado y reintenta', () async {
      var googleCalls = 0;
      final repo = _repo(
        googleNear: () async {
          googleCalls++;
          throw Exception('timeout');
        },
      );
      final station = _station('osm_1', connectors: _unknownConnector);

      final enriched = await repo.enrichStation(station);
      await repo.enrichStation(station);

      expect(enriched.id, 'osm_1');
      expect(googleCalls, 2);
    });

    test('una estación de OCM se refresca sin perder lo fusionado', () async {
      final repo = _repo(
        ocmById: () async => _station('1', connectors: const [
          Connector(
            id: 'c1',
            type: ConnectorType.ccs2,
            chargingType: ChargingType.dc,
            powerKw: 60,
            status: ConnectorStatus.occupied,
          ),
        ]),
      );
      final station =
          _station('1').copyWith(phoneNumber: '+57 300', distanceKm: 2.5);

      final enriched = await repo.enrichStation(station);

      expect(enriched.connectors.single.status, ConnectorStatus.occupied);
      expect(enriched.phoneNumber, '+57 300');
      expect(enriched.distanceKm, 2.5);
    });
  });

  group('GooglePlacesService.parseOpeningHours', () {
    test('un periodo sin cierre es 24/7', () {
      final schedule = GooglePlacesService.parseOpeningHours({
        'periods': [
          {
            'open': {'day': 0, 'hour': 0, 'minute': 0},
          },
        ],
      });
      expect(schedule?.is24x7, isTrue);
    });

    test('convierte días de Google (0 = domingo) y marca los cerrados', () {
      final schedule = GooglePlacesService.parseOpeningHours({
        'periods': [
          {
            'open': {'day': 0, 'hour': 8, 'minute': 0},
            'close': {'day': 0, 'hour': 20, 'minute': 30},
          },
          {
            'open': {'day': 1, 'hour': 6, 'minute': 0},
            'close': {'day': 2, 'hour': 1, 'minute': 0},
          },
        ],
      })!;

      final sunday = schedule.hours.firstWhere((h) => h.dayOfWeek == 7);
      expect(sunday.displayHours, '08:00 - 20:30');
      final monday = schedule.hours.firstWhere((h) => h.dayOfWeek == 1);
      expect(monday.displayHours, '06:00 - 23:59');
      final tuesday = schedule.hours.firstWhere((h) => h.dayOfWeek == 2);
      expect(tuesday.isClosed, isTrue);
    });

    test('sin periodos no inventa un horario', () {
      expect(GooglePlacesService.parseOpeningHours(null), isNull);
      expect(GooglePlacesService.parseOpeningHours({'periods': []}), isNull);
    });
  });

  group('filterStations', () {
    test('"solo gratis" no incluye estaciones sin precio conocido', () {
      final repo = _repo();
      final stations = [
        _station('sin_precio'),
        _station('gratis', paymentType: PaymentType.free),
      ];

      final result = repo.filterStations(stations, onlyFree: true);

      expect(result.map((s) => s.id), ['gratis']);
    });
  });

  group('OpenChargeMapService', () {
    OpenChargeMapService ocmReturning(List<Map<String, dynamic>> body) {
      return OpenChargeMapService(
        client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
        apiKey: 'test-key',
      );
    }

    Map<String, dynamic> poi({List<Map<String, dynamic>>? connections}) => {
          'ID': 123,
          'AddressInfo': {
            'Title': 'Estación OCM',
            'Latitude': 6.25,
            'Longitude': -75.58,
            'Town': 'Medellín',
          },
          'Connections': connections ?? [],
          'UserComments': [
            {'Comment': 'ok'},
          ],
        };

    test('sin conectores no inventa un Type 2 22 kW', () async {
      final result = await ocmReturning([poi()])
          .getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      final station = result.single;
      expect(station.connectors.single.type, ConnectorType.unknown);
      expect(station.hasCompleteData, isFalse);
    });

    test('tipo de conector no soportado se mapea como desconocido', () async {
      final result = await ocmReturning([
        poi(connections: [
          {'ID': 1, 'ConnectionTypeID': 3, 'PowerKW': 3.0}, // BS1363
        ]),
      ]).getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      expect(result.single.connectorTypes, {ConnectorType.unknown});
    });

    test('no fabrica una calificación a partir de comentarios', () async {
      final result = await ocmReturning([poi()])
          .getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      expect(result.single.rating, isNull);
    });

    test('aplica la tarifa de UsageCost a los conectores', () async {
      final body = poi(connections: [
        {'ID': 1, 'ConnectionTypeID': 33, 'PowerKW': 60.0},
      ])
        ..['UsageCost'] = '1300 COP/kWh';
      final result = await ocmReturning([body])
          .getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      final connector = result.single.connectors.single;
      expect(connector.pricePerKwh, 1300);
      expect(connector.currency, 'COP');
    });

    test('mapea GB/T DC y estado "en uso" en tiempo real', () async {
      final result = await ocmReturning([
        poi(connections: [
          {'ID': 1, 'ConnectionTypeID': 1040, 'PowerKW': 60.0, 'StatusTypeID': 20},
        ]),
      ]).getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      final connector = result.single.connectors.single;
      expect(connector.type, ConnectorType.gbtDc);
      expect(connector.chargingType, ChargingType.dc);
      expect(connector.status, ConnectorStatus.occupied);
    });

    test('CCS2 sin potencia usa 50 kW DC por defecto', () async {
      final result = await ocmReturning([
        poi(connections: [
          {'ID': 1, 'ConnectionTypeID': 33},
        ]),
      ]).getNearbyStations(latitude: 6.2442, longitude: -75.5812);

      final connector = result.single.connectors.single;
      expect(connector.type, ConnectorType.ccs2);
      expect(connector.chargingType, ChargingType.dc);
      expect(connector.powerKw, 50);
    });
  });

  group('OpenChargeMapService.parseUsageCost', () {
    final cases = <String?, double?>{
      '1300 COP/kWh': 1300,
      '1650/kWh': 1650,
      '1700': 1700,
      '0': 0,
      '\$1.300': 1300, // separador de miles colombiano
      'Gratis': 0,
      '5000 por hora': null, // no es por kWh: no inventar precio
      'Pago en el parqueadero': null,
      null: null,
    };
    cases.forEach((input, expected) {
      test('"$input" → $expected', () {
        expect(OpenChargeMapService.parseUsageCost(input), expected);
      });
    });
  });

  group('GooglePlacesService (sin API key en tests)', () {
    test('sin key no consulta la API y reporta el error', () async {
      var calls = 0;
      final service = GooglePlacesService(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        service.getNearbyStations(latitude: 6.2442, longitude: -75.5812),
        throwsException,
      );
      expect(calls, 0);
    });
  });

  group('OsmService', () {
    test('usa el primer servidor que responde aunque el otro falle', () async {
      final service = OsmService(
        client: MockClient((request) async {
          if (request.url.host == 'overpass-api.de') {
            return http.Response('at capacity', 502);
          }
          return http.Response(
            jsonEncode({
              'elements': [
                {
                  'type': 'node',
                  'id': 1,
                  'lat': 6.25,
                  'lon': -75.58,
                  'tags': {'amenity': 'charging_station', 'name': 'Celsia'},
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.getNearbyStations(
        latitude: 6.2442,
        longitude: -75.5812,
      );

      expect(result.single.id, 'osm_node_1');
    });

    test('si todos los servidores fallan lanza error', () async {
      final service = OsmService(
        client: MockClient((_) async => http.Response('busy', 504)),
      );

      expect(
        service.getNearbyStations(latitude: 6.2442, longitude: -75.5812),
        throwsException,
      );
    });
  });
}
