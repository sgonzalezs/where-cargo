import '../../../charging_stations/domain/enums/charging_enums.dart';

/// Resultado de un intento de carga reportado por un conductor.
enum CommunityStatus {
  working('working', 'Funciona'),
  partial('partial', 'Funciona parcialmente'),
  notWorking('not_working', 'No funciona');

  final String apiValue;
  final String label;

  const CommunityStatus(this.apiValue, this.label);

  static CommunityStatus? fromString(String? value) =>
      CommunityStatus.values.where((s) => s.apiValue == value).firstOrNull;
}

/// Rangos de potencia que puede elegir quien reporta (nadie conoce la cifra
/// exacta). [representativeKw] es la que se usa para mostrar y filtrar.
enum CommunityPowerLevel {
  ac7('ac_7', 'AC hasta 7 kW', ChargingType.ac, 7),
  ac22('ac_22', 'AC 11–22 kW', ChargingType.ac, 22),
  dc60('dc_60', 'DC 30–60 kW', ChargingType.dc, 50),
  dc120('dc_120', 'DC 60–120 kW', ChargingType.dc, 90),
  dc150('dc_150', 'DC 120 kW o más', ChargingType.dc, 150);

  final String apiValue;
  final String label;
  final ChargingType chargingType;
  final double representativeKw;

  const CommunityPowerLevel(
    this.apiValue,
    this.label,
    this.chargingType,
    this.representativeKw,
  );

  static CommunityPowerLevel? fromString(String? value) =>
      CommunityPowerLevel.values.where((p) => p.apiValue == value).firstOrNull;
}

/// Detalles predefinidos (sin texto libre: no requieren moderación y se
/// pueden medir).
enum CommunityTag {
  requiresApp('requires_app', 'Requiere app o tarjeta'),
  parkingFee('parking_fee', 'Cobran parqueadero'),
  restrictedAccess('restricted_access', 'Acceso restringido'),
  iceBlocked('ice_blocked', 'Ocupado por carros de combustión'),
  damagedCharger('damaged_charger', 'Cargador dañado');

  final String apiValue;
  final String label;

  const CommunityTag(this.apiValue, this.label);

  static CommunityTag? fromString(String? value) =>
      CommunityTag.values.where((t) => t.apiValue == value).firstOrNull;
}

/// Conector confirmado por la comunidad (tipo + rango de potencia).
class CommunityConnector {
  final ConnectorType type;
  final CommunityPowerLevel power;

  const CommunityConnector(this.type, this.power);

  /// Clave en Firestore, p. ej. `ccs2|dc_60`.
  String get key => '${type.apiValue}|${power.apiValue}';

  static CommunityConnector? fromKey(String key) {
    final parts = key.split('|');
    if (parts.length != 2) return null;
    final type = ConnectorType.fromString(parts[0]);
    final power = CommunityPowerLevel.fromString(parts[1]);
    if (type == ConnectorType.unknown || power == null) return null;
    return CommunityConnector(type, power);
  }

  @override
  bool operator ==(Object other) =>
      other is CommunityConnector && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Reporte de un conductor sobre una estación.
class CommunityReport {
  final CommunityStatus status;
  final Set<CommunityConnector> connectors;
  final Set<CommunityTag> tags;

  /// null = no lo indicó.
  final bool? isFree;
  final double? pricePerKwh;
  final String? vehicleModelId;

  const CommunityReport({
    required this.status,
    this.connectors = const {},
    this.tags = const {},
    this.isFree,
    this.pricePerKwh,
    this.vehicleModelId,
  });
}

/// Estado mostrado de una estación según los reportes recientes.
enum CommunityState {
  /// Sin reportes de estado en las últimas [CommunityStation.statusWindow].
  none,
  working,
  partial,
  notWorking,

  /// Reportes recientes que se contradicen.
  mixed,
}

/// Estado reciente de un reporte (sin datos del autor).
class CommunityStatusEntry {
  final CommunityStatus status;
  final DateTime at;

  const CommunityStatusEntry(this.status, this.at);
}

/// Resumen público de los reportes de una estación
/// (`community_stations/{id}`). No contiene datos de quién reportó.
class CommunityStation {
  /// Tiempo durante el cual el estado (funciona / no funciona) se considera
  /// vigente. Conectores, etiquetas y precio son información estable.
  static const Duration statusWindow = Duration(hours: 24);

  /// Un reporte más nuevo que esto prevalece sobre los anteriores que lo
  /// contradicen (p. ej. ya repararon el cargador).
  static const Duration latestWins = Duration(hours: 2);

  /// Máximo de estados recientes guardados en el resumen.
  static const int maxRecent = 10;

  final String id;
  final List<String> sourceIds;
  final double latitude;
  final double longitude;
  final String? name;

  /// Más reciente primero.
  final List<CommunityStatusEntry> recent;
  final Map<CommunityConnector, int> connectors;
  final Map<CommunityTag, int> tags;
  final int freeVotes;
  final int paidVotes;
  final double? pricePerKwh;
  final int reportCount;

  const CommunityStation({
    required this.id,
    required this.sourceIds,
    required this.latitude,
    required this.longitude,
    this.name,
    this.recent = const [],
    this.connectors = const {},
    this.tags = const {},
    this.freeVotes = 0,
    this.paidVotes = 0,
    this.pricePerKwh,
    this.reportCount = 0,
  });

  /// Estados dentro de [statusWindow] respecto a [now].
  List<CommunityStatusEntry> recentStatuses(DateTime now) =>
      recent.where((e) => now.difference(e.at) < statusWindow).toList();

  CommunityState stateAt(DateTime now) {
    final entries = recentStatuses(now);
    if (entries.isEmpty) return CommunityState.none;
    final latest = entries.first;
    final allSame = entries.every((e) => e.status == latest.status);
    if (!allSame) {
      // Reportes que se contradicen: el último manda si llegó al menos
      // [latestWins] después del último que dice otra cosa.
      final newestConflict = entries
          .firstWhere((e) => e.status != latest.status)
          .at;
      if (latest.at.difference(newestConflict) < latestWins) {
        return CommunityState.mixed;
      }
    }
    return switch (latest.status) {
      CommunityStatus.working => CommunityState.working,
      CommunityStatus.partial => CommunityState.partial,
      CommunityStatus.notWorking => CommunityState.notWorking,
    };
  }

  /// Último reporte de estado (aunque ya no esté vigente).
  DateTime? get lastReportAt => recent.isEmpty ? null : recent.first.at;

  /// Conectores confirmados, el más confirmado primero.
  List<MapEntry<CommunityConnector, int>> get rankedConnectors =>
      connectors.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  /// Etiquetas reportadas, la más frecuente primero.
  List<MapEntry<CommunityTag, int>> get rankedTags =>
      tags.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  /// true/false si la mayoría dijo gratis/de pago; null si no hay votos.
  bool? get isFree => freeVotes == paidVotes ? null : freeVotes > paidVotes;

  /// Resumen tras sumar [report] hecho en [at]. Lo calcula la app al
  /// reportar (en una transacción con el resumen actual).
  CommunityStation withReport(
    CommunityReport report,
    DateTime at, {
    required String sourceId,
  }) {
    final connectorCounts = Map.of(connectors);
    for (final c in report.connectors) {
      connectorCounts[c] = (connectorCounts[c] ?? 0) + 1;
    }
    final tagCounts = Map.of(tags);
    for (final t in report.tags) {
      tagCounts[t] = (tagCounts[t] ?? 0) + 1;
    }
    return CommunityStation(
      id: id,
      sourceIds: sourceIds.contains(sourceId)
          ? sourceIds
          : [...sourceIds, sourceId].take(10).toList(),
      latitude: latitude,
      longitude: longitude,
      name: name,
      recent: [
        CommunityStatusEntry(report.status, at),
        ...recent,
      ].take(maxRecent).toList(),
      connectors: connectorCounts,
      tags: tagCounts,
      freeVotes: freeVotes + (report.isFree == true ? 1 : 0),
      paidVotes: paidVotes + (report.isFree == false ? 1 : 0),
      pricePerKwh: report.pricePerKwh ?? pricePerKwh,
      reportCount: reportCount + 1,
    );
  }
}
