import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../../features/charging_stations/domain/models/charging_station.dart';
import '../../features/vehicle_sync/domain/models/vehicle.dart';
import 'vehicle_service.dart';

/// Analítica de uso (Firebase Analytics) y reporte de fallos (Crashlytics).
///
/// Solo se envían eventos de uso de la app: nunca nombre, correo, ubicación
/// exacta ni el uid de Firebase. En modo debug no se recolecta nada.
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  // Se resuelve al usarse: sin [initialize] (p. ej. en tests) no toca Firebase.
  FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;
  bool _initialized = false;
  String? _vehicleKey;

  /// Activa la recolección y captura los errores no controlados de Flutter y
  /// de la plataforma. Llamar justo después de `Firebase.initializeApp`.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final enabled = !kDebugMode;
    await Future.wait([
      _analytics.setAnalyticsCollectionEnabled(enabled),
      FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled),
    ]);

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    VehicleService().addListener(_onVehiclesChanged);
  }

  /// Registra un error controlado que vale la pena revisar.
  void recordError(Object error, StackTrace? stack, {String? reason}) {
    if (!_initialized) return;
    FirebaseCrashlytics.instance.recordError(error, stack, reason: reason);
  }

  // ---------------------------------------------------------------------------
  // Propiedades del usuario (segmentan las estadísticas)
  // ---------------------------------------------------------------------------

  void setSignedIn(bool signedIn) => _run(
    () => _analytics.setUserProperty(
      name: 'has_account',
      value: signedIn.toString(),
    ),
  );

  void _onVehiclesChanged() {
    final vehicle = VehicleService().primaryVehicle;
    final brand = vehicle == null ? 'none' : _brandOf(vehicle);
    final model = vehicle == null ? 'none' : vehicle.modelId ?? 'custom';
    final key = '$brand|$model';
    if (key == _vehicleKey) return;
    _vehicleKey = key;
    _run(() async {
      await _analytics.setUserProperty(name: 'vehicle_brand', value: brand);
      await _analytics.setUserProperty(name: 'vehicle_model', value: model);
    });
  }

  // ---------------------------------------------------------------------------
  // Eventos
  // ---------------------------------------------------------------------------

  /// Pestañas y páginas: `map`, `stations`, `favorites`, `vehicle`,
  /// `station_detail`, `login`, `onboarding`.
  void logScreen(String name) =>
      _run(() => _analytics.logScreenView(screenName: name));

  void logStationView(ChargingStation station) => _log('station_view', {
    'station_source': _sourceOf(station),
    'city': _limit(station.city),
    'complete_data': station.hasCompleteData.toString(),
  });

  /// [app]: `google_maps`, `waze`, `apple_maps`.
  void logNavigationStart(String app) =>
      _log('navigation_start', {'app': app});

  void logFavorite(ChargingStation station, {required bool added}) => _log(
    added ? 'favorite_add' : 'favorite_remove',
    {'station_source': _sourceOf(station)},
  );

  void logCommunityReport(String status) =>
      _log('community_report', {'status': status});

  void logVehicleAdded(Vehicle vehicle) => _log('vehicle_add', {
    'kind': vehicle.modelId != null ? 'catalog' : 'custom',
    'brand': _brandOf(vehicle),
  });

  void logLogin() => _run(() => _analytics.logLogin(loginMethod: 'google'));

  void logLoginSkipped() => _log('login_skipped');

  void logAccountDeleted() => _log('account_deleted');

  // ---------------------------------------------------------------------------

  void _log(String name, [Map<String, Object>? parameters]) =>
      _run(() => _analytics.logEvent(name: name, parameters: parameters));

  /// La analítica nunca debe romper un flujo de la app.
  void _run(Future<void> Function() action) {
    if (!_initialized) return;
    unawaited(
      action().catchError((Object e) {
        debugPrint('[WhereCargo] Analytics: $e');
      }),
    );
  }

  /// Fuente según el prefijo del id (OCM usa su id numérico sin prefijo).
  static String _sourceOf(ChargingStation station) {
    final id = station.id;
    if (id.startsWith('gpl_')) return 'google';
    if (id.startsWith('osm_')) return 'osm';
    return 'ocm';
  }

  static String _brandOf(Vehicle vehicle) =>
      _limit(vehicle.brandId ?? vehicle.brand.trim().toLowerCase());

  /// Analytics admite hasta 36 caracteres en propiedades de usuario y 100 en
  /// parámetros: se usa el límite menor para ambos.
  static String _limit(String value) =>
      value.length <= 36 ? value : value.substring(0, 36);
}
