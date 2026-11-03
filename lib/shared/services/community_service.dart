import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/charging_stations/domain/enums/charging_enums.dart';
import '../../features/charging_stations/domain/models/charging_station.dart';
import '../../features/charging_stations/domain/models/connector.dart';
import '../../features/community/data/geohash.dart';
import '../../features/community/domain/models/community_station.dart';

/// Reportes de la comunidad sobre las estaciones.
///
/// Firestore:
/// - `community_stations/{id}`: resumen público (sin autores), lectura libre.
/// - `community_stations/{id}/reports/{id}`: cada reporte con su autor;
///   no se puede leer desde la app.
/// - `community_stations/{id}/contributors/{uid}`: último reporte del
///   usuario en esa estación (límite de 1 cada 30 min).
/// - `users/{uid}.report_window_*`: límite de reportes por día.
///
/// La app calcula el resumen en la misma transacción que crea el reporte; las
/// reglas exigen que ambos se escriban juntos.
class CommunityService extends ChangeNotifier {
  static final CommunityService _instance = CommunityService._internal();
  factory CommunityService() => _instance;
  CommunityService._internal();

  static const Duration perStationCooldown = Duration(minutes: 30);
  static const int maxReportsPerDay = 20;

  /// Distancia máxima a la estación para poder reportar.
  static const double maxReportDistanceMeters = 500;

  /// Una estación de la comunidad corresponde a una cargada de otra fuente
  /// si comparten id o están a menos de esta distancia.
  static const double _sameStationMeters = 60;

  static const Duration _areaMaxAge = Duration(minutes: 10);

  FirebaseFirestore? _firestoreOverride;
  FirebaseFirestore get _db => _firestoreOverride ?? FirebaseFirestore.instance;

  @visibleForTesting
  set firestore(FirebaseFirestore value) => _firestoreOverride = value;

  final Map<String, CommunityStation> _stations = {};
  final Map<String, DateTime> _loadedCells = {};

  Iterable<CommunityStation> get stations => _stations.values;

  /// Carga los resúmenes de la zona (una consulta por celda geohash, solo las
  /// que no se cargaron hace poco). Los errores se ignoran: sin conexión la
  /// app sigue funcionando sin datos de la comunidad.
  Future<void> loadArea(
    double latitude,
    double longitude,
    double radiusKm, {
    bool force = false,
  }) async {
    final now = DateTime.now();
    final cells = Geohash.coveringCells(latitude, longitude, radiusKm)
        .where(
          (cell) =>
              force ||
              _loadedCells[cell] == null ||
              now.difference(_loadedCells[cell]!) > _areaMaxAge,
        )
        .toList();
    if (cells.isEmpty) return;
    try {
      final snapshots = await Future.wait(
        cells.map(
          (cell) => _db
              .collection('community_stations')
              .where('geohash', isGreaterThanOrEqualTo: cell)
              .where('geohash', isLessThan: '$cell~')
              .get(),
        ),
      );
      for (final snapshot in snapshots) {
        for (final doc in snapshot.docs) {
          final station = stationFromDoc(doc.id, doc.data());
          if (station != null) _stations[doc.id] = station;
        }
      }
      for (final cell in cells) {
        _loadedCells[cell] = now;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[WhereCargo] No se pudieron cargar reportes: $e');
    }
  }

  /// Resumen de la comunidad para [station], si existe.
  CommunityStation? forStation(ChargingStation station) =>
      match(station, _stations.values);

  @visibleForTesting
  static CommunityStation? match(
    ChargingStation station,
    Iterable<CommunityStation> candidates,
  ) {
    CommunityStation? nearest;
    var nearestMeters = _sameStationMeters;
    for (final c in candidates) {
      if (c.sourceIds.contains(station.id)) return c;
      final meters = distanceMeters(
        station.latitude,
        station.longitude,
        c.latitude,
        c.longitude,
      );
      if (meters < nearestMeters) {
        nearest = c;
        nearestMeters = meters;
      }
    }
    return nearest;
  }

  /// Aplica a [station] lo que reportó la comunidad.
  ChargingStation apply(ChargingStation station) =>
      applyTo(station, forStation(station), DateTime.now());

  /// - Si la estación no tiene conectores conocidos, usa los confirmados.
  /// - Si la mayoría la reportó gratis, la marca gratis.
  /// - Si está reportada sin servicio, sus conectores quedan "con falla".
  @visibleForTesting
  static ChargingStation applyTo(
    ChargingStation station,
    CommunityStation? community,
    DateTime now,
  ) {
    if (community == null) return station;
    var connectors = station.connectors;
    var paymentType = station.paymentType;
    final isFree = community.isFree;

    if (!station.hasCompleteData && community.connectors.isNotEmpty) {
      connectors = [
        for (final entry in community.rankedConnectors)
          Connector(
            id: 'community_${entry.key.key}',
            type: entry.key.type,
            chargingType: entry.key.power.chargingType,
            powerKw: entry.key.power.representativeKw,
            status: ConnectorStatus.available,
            pricePerKwh: isFree == true ? 0 : community.pricePerKwh,
            currency: isFree == true || community.pricePerKwh != null
                ? 'COP'
                : null,
          ),
      ];
    }
    if (isFree == true) paymentType = PaymentType.free;

    final notWorking = community.stateAt(now) == CommunityState.notWorking;
    if (notWorking) {
      connectors = [
        for (final c in connectors) c.copyWith(status: ConnectorStatus.faulted),
      ];
    }

    if (identical(connectors, station.connectors) &&
        paymentType == station.paymentType) {
      return station;
    }
    return station.copyWith(
      connectors: connectors,
      paymentType: paymentType,
      status: notWorking ? StationStatus.offline : null,
    );
  }

  /// Distancia en metros entre el teléfono y [station], o null si no se pudo
  /// obtener la ubicación (sin permiso o GPS apagado).
  Future<double?> distanceToStation(ChargingStation station) async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      return distanceMeters(
        position.latitude,
        position.longitude,
        station.latitude,
        station.longitude,
      );
    } catch (e) {
      debugPrint('[WhereCargo] Ubicación para reporte: $e');
      return null;
    }
  }

  /// Guarda el reporte y actualiza el resumen de la estación.
  ///
  /// Lanza [CommunityException] con un mensaje para mostrar.
  Future<void> submitReport(
    ChargingStation station,
    CommunityReport report,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const CommunityException('Inicia sesión para reportar');
    }
    // El resumen puede existir aunque la zona aún no se haya cargado
    await loadArea(station.latitude, station.longitude, 1);
    final existing = forStation(station);
    final stationRef = _db
        .collection('community_stations')
        .doc(existing?.id ?? safeDocId(station.id));
    final userRef = _db.collection('users').doc(uid);
    final contributorRef = stationRef.collection('contributors').doc(uid);
    final reportRef = stationRef.collection('reports').doc();

    late CommunityStation updated;
    try {
      await _db.runTransaction((tx) async {
        final now = DateTime.now();
        final contributor = await tx.get(contributorRef);
        final lastReport = (contributor.data()?['last_report_at'] as Timestamp?)
            ?.toDate();
        if (lastReport != null &&
            now.difference(lastReport) < perStationCooldown) {
          throw const CommunityException(
            'Ya reportaste esta estación hace poco. Intenta más tarde.',
          );
        }

        final user = (await tx.get(userRef)).data() ?? const {};
        final windowStart = (user['report_window_start'] as Timestamp?)
            ?.toDate();
        final windowCount = user['report_window_count'] as int? ?? 0;
        final newWindow =
            windowStart == null ||
            now.difference(windowStart) >= const Duration(days: 1);
        if (!newWindow && windowCount >= maxReportsPerDay) {
          throw const CommunityException(
            'Alcanzaste el límite de reportes de hoy. ¡Gracias por aportar!',
          );
        }

        final snapshot = await tx.get(stationRef);
        final current =
            (snapshot.exists
                ? stationFromDoc(stationRef.id, snapshot.data()!)
                : null) ??
            CommunityStation(
              id: stationRef.id,
              sourceIds: [station.id],
              latitude: station.latitude,
              longitude: station.longitude,
              name: station.name,
            );
        updated = current.withReport(report, now, sourceId: station.id);

        tx.set(reportRef, {
          'user_id': uid,
          'status': report.status.apiValue,
          'connectors': report.connectors.map((c) => c.key).toList(),
          'tags': report.tags.map((t) => t.apiValue).toList(),
          'is_free': report.isFree,
          'price_kwh': report.pricePerKwh,
          'vehicle_model_id': report.vehicleModelId,
          'created_at': FieldValue.serverTimestamp(),
        });
        tx.set(contributorRef, {
          'last_report_at': FieldValue.serverTimestamp(),
        });
        tx.set(
          userRef,
          newWindow
              ? {
                  'report_window_start': FieldValue.serverTimestamp(),
                  'report_window_count': 1,
                }
              : {'report_window_count': windowCount + 1},
          SetOptions(merge: true),
        );
        tx.set(stationRef, {
          ...stationToDoc(updated),
          'last_report_id': reportRef.id,
          'updated_at': FieldValue.serverTimestamp(),
        });
      });
    } on CommunityException {
      rethrow;
    } on FirebaseException catch (e) {
      debugPrint('[WhereCargo] Reporte: ${e.code} ${e.message}');
      throw CommunityException(
        e.code == 'unavailable'
            ? 'Sin conexión a internet'
            : 'No se pudo enviar el reporte',
      );
    }
    _stations[updated.id] = updated;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Firestore
  // ---------------------------------------------------------------------------

  /// Los ids de OSM incluyen "/", que no se permite en un id de documento.
  @visibleForTesting
  static String safeDocId(String stationId) =>
      stationId.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  @visibleForTesting
  static Map<String, dynamic> stationToDoc(CommunityStation s) => {
    'source_ids': s.sourceIds,
    'lat': s.latitude,
    'lng': s.longitude,
    'geohash': Geohash.encode(s.latitude, s.longitude),
    'name': s.name,
    'recent': [
      for (final e in s.recent)
        {'status': e.status.apiValue, 'at': Timestamp.fromDate(e.at)},
    ],
    'connectors': {for (final e in s.connectors.entries) e.key.key: e.value},
    'tags': {for (final e in s.tags.entries) e.key.apiValue: e.value},
    'free_votes': s.freeVotes,
    'paid_votes': s.paidVotes,
    'price_kwh': s.pricePerKwh,
    'report_count': s.reportCount,
  };

  /// null si el documento no es válido.
  @visibleForTesting
  static CommunityStation? stationFromDoc(
    String id,
    Map<String, dynamic> data,
  ) {
    try {
      final recent = <CommunityStatusEntry>[];
      for (final raw in data['recent'] as List<dynamic>? ?? const []) {
        final map = raw as Map<String, dynamic>;
        final status = CommunityStatus.fromString(map['status'] as String?);
        final at = (map['at'] as Timestamp?)?.toDate();
        if (status != null && at != null) {
          recent.add(CommunityStatusEntry(status, at));
        }
      }
      recent.sort((a, b) => b.at.compareTo(a.at));

      final connectors = <CommunityConnector, int>{};
      (data['connectors'] as Map<String, dynamic>? ?? const {}).forEach((
        key,
        value,
      ) {
        final c = CommunityConnector.fromKey(key);
        if (c != null) connectors[c] = (value as num).toInt();
      });
      final tags = <CommunityTag, int>{};
      (data['tags'] as Map<String, dynamic>? ?? const {}).forEach((key, value) {
        final t = CommunityTag.fromString(key);
        if (t != null) tags[t] = (value as num).toInt();
      });

      return CommunityStation(
        id: id,
        sourceIds: (data['source_ids'] as List<dynamic>).cast<String>(),
        latitude: (data['lat'] as num).toDouble(),
        longitude: (data['lng'] as num).toDouble(),
        name: data['name'] as String?,
        recent: recent,
        connectors: connectors,
        tags: tags,
        freeVotes: (data['free_votes'] as num?)?.toInt() ?? 0,
        paidVotes: (data['paid_votes'] as num?)?.toInt() ?? 0,
        pricePerKwh: (data['price_kwh'] as num?)?.toDouble(),
        reportCount: (data['report_count'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('[WhereCargo] Resumen de comunidad $id no válido: $e');
      return null;
    }
  }

  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return 2 * earthRadius * asin(sqrt(a));
  }
}

class CommunityException implements Exception {
  final String message;
  const CommunityException(this.message);

  @override
  String toString() => message;
}
