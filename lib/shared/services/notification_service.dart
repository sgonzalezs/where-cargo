import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Servicio singleton para mostrar notificaciones locales.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _proximityChannelId = 'where_cargo_proximity';
  static const String _proximityChannelName = 'Estaciones Cercanas';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Inicializa el plugin y solicita permisos en Android 13+.
  /// Llamar una vez desde `main()`.
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_launcher_foreground');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);

    // Solicitar permiso de notificaciones en Android 13+ (API 33+)
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Muestra una notificación informando que hay una estación cercana.
  Future<void> showProximityNotification({
    required String stationId,
    required String stationName,
    required double distanceMeters,
  }) async {
    if (!_initialized) return;

    final distance = distanceMeters < 1000
        ? '${distanceMeters.round()} m'
        : '${(distanceMeters / 1000).toStringAsFixed(1)} km';

    const androidDetails = AndroidNotificationDetails(
      _proximityChannelId,
      _proximityChannelName,
      channelDescription:
          'Notificaciones cuando hay estaciones de carga cerca de tu ubicación',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@drawable/ic_launcher_foreground',
    );

    const details = NotificationDetails(android: androidDetails);

    try {
      await _plugin.show(
        stationId.hashCode.abs() % 2147483647,
        '⚡ Estación de carga cercana',
        '$stationName está a $distance de tu ubicación',
        details,
      );
    } catch (e) {
      debugPrint('Error mostrando notificación: $e');
    }
  }
}
