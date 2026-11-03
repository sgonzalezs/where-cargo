import 'dart:math';

/// Geohash mínimo para consultar en Firestore por zona: los documentos
/// guardan el geohash de su posición y se consultan por prefijo
/// (`geohash >= celda && geohash < celda + '~'`).
class Geohash {
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  static String encode(double latitude, double longitude, {int precision = 7}) {
    var latMin = -90.0, latMax = 90.0;
    var lngMin = -180.0, lngMax = 180.0;
    final hash = StringBuffer();
    var bit = 0, ch = 0;
    var evenBit = true;
    while (hash.length < precision) {
      if (evenBit) {
        final mid = (lngMin + lngMax) / 2;
        if (longitude >= mid) {
          ch = (ch << 1) | 1;
          lngMin = mid;
        } else {
          ch = ch << 1;
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (latitude >= mid) {
          ch = (ch << 1) | 1;
          latMin = mid;
        } else {
          ch = ch << 1;
          latMax = mid;
        }
      }
      evenBit = !evenBit;
      if (++bit == 5) {
        hash.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return hash.toString();
  }

  /// Celdas de [precision] caracteres que cubren el círculo de [radiusKm]
  /// alrededor del punto. Con precisión 4 (celdas de ~39 × 20 km) un radio de
  /// 30 km necesita entre 4 y 12 consultas.
  static Set<String> coveringCells(
    double latitude,
    double longitude,
    double radiusKm, {
    int precision = 4,
  }) {
    final latDelta = radiusKm / 111.0;
    final lngDelta = radiusKm / (111.0 * cos(latitude * pi / 180));
    // Paso menor que el tamaño de la celda para no saltarse ninguna
    const steps = 6;
    final cells = <String>{};
    for (var i = 0; i <= steps; i++) {
      for (var j = 0; j <= steps; j++) {
        cells.add(
          encode(
            latitude - latDelta + 2 * latDelta * i / steps,
            longitude - lngDelta + 2 * lngDelta * j / steps,
            precision: precision,
          ),
        );
      }
    }
    return cells;
  }
}
