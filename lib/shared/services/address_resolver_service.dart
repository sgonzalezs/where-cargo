import 'dart:async';

import 'package:geocoding/geocoding.dart';

/// Cache en memoria para resolución de direcciones por geocodificación inversa.
///
/// Evita llamadas repetidas para la misma ubicación durante la sesión.
/// Cuando varias cards piden la misma coordenada al mismo tiempo, solo se
/// lanza una llamada y todas esperan el mismo Completer.
class AddressResolverService {
  static final AddressResolverService _instance =
      AddressResolverService._internal();
  factory AddressResolverService() => _instance;
  AddressResolverService._internal();

  static const String _unavailable = 'Dirección no disponible';

  // Clave: "lat_lng" → dirección resuelta
  final Map<String, String> _cache = {};
  // Llamadas en vuelo: misma clave comparte un Completer
  final Map<String, Completer<String?>> _inflight = {};

  /// Resuelve la dirección real desde coordenadas usando geocodificación inversa.
  ///
  /// - Si la dirección ya es válida retorna `null` (no hay nada que corregir).
  /// - Si otra card ya está resolviendo la misma coordenada, espera el mismo
  ///   resultado en lugar de lanzar una segunda llamada.
  Future<String?> resolve({
    required String stationId,
    required double latitude,
    required double longitude,
    required String currentAddress,
  }) async {
    // Si ya tiene una dirección válida no hacemos nada
    if (currentAddress.isNotEmpty && currentAddress != _unavailable) {
      return null;
    }

    final key =
        '${latitude.toStringAsFixed(5)}_${longitude.toStringAsFixed(5)}';

    // Resultado ya en cache
    if (_cache.containsKey(key)) return _cache[key];

    // Ya hay una llamada en vuelo para esta coordenada — esperar su resultado
    if (_inflight.containsKey(key)) {
      return _inflight[key]!.future;
    }

    // Primera llamada para esta coordenada
    final completer = Completer<String?>();
    _inflight[key] = completer;

    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) {
        completer.complete(null);
        return null;
      }

      final p = placemarks.first;
      final resolved = _buildAddress(p);

      if (resolved != null) _cache[key] = resolved;
      completer.complete(resolved);
      return resolved;
    } catch (_) {
      completer.complete(null);
      return null;
    } finally {
      _inflight.remove(key);
    }
  }

  /// Construye la mejor dirección posible desde un Placemark.
  ///
  /// Intenta en orden: calle + número → barrio → localidad → subadmin → admin.
  String? _buildAddress(Placemark p) {
    final street = p.thoroughfare;
    final number = p.subThoroughfare;
    final neighborhood = p.subLocality;
    final locality = p.locality;
    final subAdmin = p.subAdministrativeArea;
    final admin = p.administrativeArea;

    final parts = <String>[];

    if (street != null && street.isNotEmpty) {
      parts.add(
        (number != null && number.isNotEmpty) ? '$street # $number' : street,
      );
    }
    if (neighborhood != null && neighborhood.isNotEmpty) {
      parts.add(neighborhood);
    }

    if (parts.isNotEmpty) return parts.join(', ');

    // Fallback: solo localidad o nivel administrativo
    if (locality != null && locality.isNotEmpty) return locality;
    if (subAdmin != null && subAdmin.isNotEmpty) return subAdmin;
    if (admin != null && admin.isNotEmpty) return admin;

    return null;
  }
}
