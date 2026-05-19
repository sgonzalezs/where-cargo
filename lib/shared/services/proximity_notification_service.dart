import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/charging_stations/domain/models/charging_station.dart';
import 'notification_service.dart';

/// Servicio singleton que detecta cuando el usuario se aproxima a una
/// estación de carga y dispara una notificación local informativa.
///
/// Solo opera mientras la app está en foreground.
/// Usa el stream de posición de Geolocator (permiso ya gestionado en la app).
class ProximityNotificationService {
  static final ProximityNotificationService _instance =
      ProximityNotificationService._internal();
  factory ProximityNotificationService() => _instance;
  ProximityNotificationService._internal();

  /// Radio en metros para considerar que el usuario está "cerca".
  static const double _enterThresholdMeters = 500;

  /// El usuario debe alejarse esta distancia para permitir re-notificar.
  static const double _exitThresholdMeters = 1500;

  List<ChargingStation> _stations = [];
  final Set<String> _notifiedIds = {};
  StreamSubscription<Position>? _positionSubscription;

  /// Actualiza la lista de estaciones contra las que se comprueba proximidad.
  /// Llamar cada vez que se carguen nuevas estaciones.
  void updateStations(List<ChargingStation> stations) {
    _stations = stations;
  }

  /// Activa la detección de proximidad en foreground.
  /// Idempotente: si ya está activo no crea un segundo stream.
  void activate() {
    if (_positionSubscription != null) return;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50, // solo reevalúa cuando el usuario se mueve ≥50 m
    );

    try {
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        _checkProximity,
        onError: (e) => debugPrint('ProximityNotificationService error: $e'),
      );
    } catch (e) {
      debugPrint('No se pudo iniciar ProximityNotificationService: $e');
    }
  }

  /// Desactiva la detección (p. ej. al cerrar la app).
  void deactivate() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _checkProximity(Position position) {
    for (final station in _stations) {
      final distanceM = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        station.latitude,
        station.longitude,
      );

      if (distanceM <= _enterThresholdMeters &&
          !_notifiedIds.contains(station.id)) {
        _notifiedIds.add(station.id);
        NotificationService().showProximityNotification(
          stationId: station.id,
          stationName: station.name,
          distanceMeters: distanceM,
        );
      } else if (distanceM > _exitThresholdMeters) {
        // Permite volver a notificar si el usuario se aleja y regresa
        _notifiedIds.remove(station.id);
      }
    }
  }
}
