import 'package:flutter_test/flutter_test.dart';
import 'package:where_cargo/features/charging_stations/domain/enums/charging_enums.dart';
import 'package:where_cargo/features/charging_stations/domain/models/charging_station.dart';
import 'package:where_cargo/features/charging_stations/domain/models/connector.dart';
import 'package:where_cargo/features/community/data/geohash.dart';
import 'package:where_cargo/features/community/domain/models/community_station.dart';
import 'package:where_cargo/shared/services/community_service.dart';

void main() {
  final now = DateTime(2026, 11, 3, 12);

  ChargingStation station({
    String id = 'gpl_1',
    double lat = 6.2442,
    double lng = -75.5812,
    List<Connector> connectors = const [],
  }) => ChargingStation(
    id: id,
    name: 'Estación',
    address: 'Calle 1',
    city: 'Medellín',
    latitude: lat,
    longitude: lng,
    connectors: connectors,
    status: StationStatus.unknown,
    paymentType: PaymentType.paid,
  );

  CommunityStation community({
    List<CommunityStatusEntry> recent = const [],
    Map<CommunityConnector, int> connectors = const {},
    int freeVotes = 0,
  }) => CommunityStation(
    id: 'gpl_1',
    sourceIds: const ['gpl_1'],
    latitude: 6.2442,
    longitude: -75.5812,
    recent: recent,
    connectors: connectors,
    freeVotes: freeVotes,
  );

  CommunityStatusEntry entry(CommunityStatus s, Duration ago) =>
      CommunityStatusEntry(s, now.subtract(ago));

  group('estado según reportes recientes', () {
    test('sin reportes o vencidos', () {
      expect(community().stateAt(now), CommunityState.none);
      expect(
        community(
          recent: [
            entry(CommunityStatus.notWorking, const Duration(hours: 25)),
          ],
        ).stateAt(now),
        CommunityState.none,
      );
    });

    test('reportes que coinciden', () {
      final c = community(
        recent: [
          entry(CommunityStatus.working, const Duration(hours: 1)),
          entry(CommunityStatus.working, const Duration(hours: 5)),
        ],
      );
      expect(c.stateAt(now), CommunityState.working);
    });

    test('contradicción cercana es "mixto"', () {
      final c = community(
        recent: [
          entry(CommunityStatus.working, const Duration(minutes: 30)),
          entry(CommunityStatus.notWorking, const Duration(hours: 1)),
        ],
      );
      expect(c.stateAt(now), CommunityState.mixed);
    });

    test('el último manda si llegó 2 h o más después', () {
      // Ya repararon el cargador
      final c = community(
        recent: [
          entry(CommunityStatus.working, const Duration(hours: 1)),
          entry(CommunityStatus.notWorking, const Duration(hours: 4)),
        ],
      );
      expect(c.stateAt(now), CommunityState.working);
    });
  });

  group('aplicar a estaciones', () {
    const ccs2Dc60 = CommunityConnector(
      ConnectorType.ccs2,
      CommunityPowerLevel.dc60,
    );

    test('completa conectores de estaciones sin datos', () {
      final s = station();
      expect(s.hasCompleteData, isFalse);
      final applied = CommunityService.applyTo(
        s,
        community(connectors: {ccs2Dc60: 2}, freeVotes: 1),
        now,
      );
      expect(applied.hasCompleteData, isTrue);
      expect(applied.connectors.single.type, ConnectorType.ccs2);
      expect(applied.connectors.single.powerKw, 50);
      expect(applied.isFree, isTrue);
    });

    test('no reemplaza conectores que ya vienen de las fuentes', () {
      final s = station(
        connectors: const [
          Connector(
            id: 'c1',
            type: ConnectorType.type2,
            chargingType: ChargingType.ac,
            powerKw: 22,
            status: ConnectorStatus.available,
          ),
        ],
      );
      final applied = CommunityService.applyTo(
        s,
        community(connectors: {ccs2Dc60: 1}),
        now,
      );
      expect(identical(applied, s), isTrue);
    });

    test('reportada sin servicio deja los conectores con falla', () {
      final applied = CommunityService.applyTo(
        station(),
        community(
          connectors: {ccs2Dc60: 1},
          recent: [
            entry(CommunityStatus.notWorking, const Duration(minutes: 10)),
          ],
        ),
        now,
      );
      expect(applied.hasAvailableConnectors, isFalse);
      expect(applied.status, StationStatus.offline);
    });

    test('se reconoce por id o por cercanía', () {
      final c = community();
      expect(CommunityService.match(station(), [c]), same(c));
      // Misma estación con id de otra fuente, a ~20 m
      expect(
        CommunityService.match(
          station(id: 'ocm_9', lat: 6.24438, lng: -75.5812),
          [c],
        ),
        same(c),
      );
      // Otra estación a ~200 m
      expect(
        CommunityService.match(station(id: 'ocm_9', lat: 6.2460), [c]),
        isNull,
      );
    });
  });

  group('resumen en Firestore', () {
    test('sumar un reporte y volver a leerlo', () {
      final base = CommunityStation(
        id: 'osm_node_1',
        sourceIds: const ['osm_node/1'],
        latitude: 6.2,
        longitude: -75.5,
      );
      final updated = base
          .withReport(
            CommunityReport(
              status: CommunityStatus.working,
              connectors: {
                const CommunityConnector(
                  ConnectorType.type2,
                  CommunityPowerLevel.ac22,
                ),
              },
              tags: {CommunityTag.parkingFee},
              isFree: false,
              pricePerKwh: 1300,
            ),
            now,
            sourceId: 'gpl_2',
          )
          .withReport(
            const CommunityReport(
              status: CommunityStatus.notWorking,
              tags: {CommunityTag.parkingFee, CommunityTag.damagedCharger},
            ),
            now.add(const Duration(minutes: 40)),
            sourceId: 'osm_node/1',
          );

      expect(updated.reportCount, 2);
      expect(updated.sourceIds, ['osm_node/1', 'gpl_2']);
      expect(updated.recent.first.status, CommunityStatus.notWorking);
      expect(updated.tags[CommunityTag.parkingFee], 2);
      expect(updated.isFree, isFalse);

      final doc = CommunityService.stationToDoc(updated);
      expect(doc['geohash'], hasLength(7));
      final back = CommunityService.stationFromDoc(updated.id, doc)!;
      expect(back.reportCount, 2);
      expect(back.connectors.keys.single.key, 'type2|ac_22');
      expect(back.tags[CommunityTag.damagedCharger], 1);
      expect(back.pricePerKwh, 1300);
      expect(back.recent.map((e) => e.status), [
        CommunityStatus.notWorking,
        CommunityStatus.working,
      ]);
    });

    test('ids de documento válidos', () {
      expect(CommunityService.safeDocId('osm_node/123'), 'osm_node_123');
      expect(CommunityService.safeDocId('gpl_ChIJ-ab_1'), 'gpl_ChIJ-ab_1');
    });

    test('documento inválido se ignora', () {
      expect(CommunityService.stationFromDoc('x', {'lat': 'no'}), isNull);
    });
  });

  group('geohash', () {
    test('codifica igual que la referencia', () {
      // Valor de referencia: 57.64911, 10.40744 → u4pruydqqvj
      expect(Geohash.encode(57.64911, 10.40744, precision: 11), 'u4pruydqqvj');
    });

    test('las celdas cubren todo el radio de búsqueda', () {
      const lat = 6.2442, lng = -75.5812;
      final cells = Geohash.coveringCells(lat, lng, 30);
      expect(cells.length, lessThanOrEqualTo(12));
      // Puntos a 29 km en las cuatro direcciones quedan dentro de alguna celda
      for (final (dLat, dLng) in [
        (0.26, 0.0),
        (-0.26, 0.0),
        (0.0, 0.26),
        (0.0, -0.26),
      ]) {
        final hash = Geohash.encode(lat + dLat, lng + dLng);
        expect(cells.any(hash.startsWith), isTrue, reason: '$dLat,$dLng');
      }
    });
  });
}
