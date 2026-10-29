import 'vehicle_catalog.dart';

/// Vehículo eléctrico del usuario.
///
/// Si [modelId] y [variantId] apuntan al catálogo, las especificaciones
/// (batería, autonomía, potencia) vienen de allí y en la nube solo se guarda
/// la referencia. Si son null es un vehículo personalizado ("Otro modelo")
/// y sus especificaciones las escribió el usuario.
class Vehicle {
  final String id;
  final String? name;
  final String? modelId;
  final String? variantId;
  final String brand;
  final String model;
  final String? variantName;
  final int year;
  final double batteryCapacityKwh;
  final double currentBatteryPercent;

  /// Autonomía con la batería al 100 %.
  final double? estimatedRangeKm;
  final List<String> compatibleConnectors;
  final double? maxChargingPowerKw;
  final String? imageUrl;
  final bool isPrimary;
  final DateTime createdAt;

  Vehicle({
    required this.id,
    this.name,
    this.modelId,
    this.variantId,
    required this.brand,
    required this.model,
    this.variantName,
    required this.year,
    required this.batteryCapacityKwh,
    required this.currentBatteryPercent,
    this.estimatedRangeKm,
    required this.compatibleConnectors,
    this.maxChargingPowerKw,
    this.imageUrl,
    this.isPrimary = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? _createdAtFromId(id) ?? DateTime.now();

  /// Vehículo del catálogo. [connectors] permite ajustar los conectores de
  /// la versión (p. ej. un vehículo importado con otro estándar).
  factory Vehicle.fromCatalog({
    required String id,
    String? name,
    required VehicleBrand brand,
    required VehicleModel model,
    required VehicleVariant variant,
    required int year,
    double currentBatteryPercent = 100,
    List<String>? connectors,
    bool isPrimary = false,
    DateTime? createdAt,
  }) {
    return Vehicle(
      id: id,
      name: name,
      modelId: model.id,
      variantId: variant.id,
      brand: brand.name,
      model: model.name,
      variantName: variant.name,
      year: year,
      batteryCapacityKwh: variant.batteryKwh,
      currentBatteryPercent: currentBatteryPercent,
      estimatedRangeKm: variant.rangeKm,
      compatibleConnectors: connectors ?? variant.connectors,
      maxChargingPowerKw: variant.maxDcKw,
      isPrimary: isPrimary,
      createdAt: createdAt,
    );
  }

  /// Los ids son `vehicle_<milisegundos>`: sirve como fecha de creación
  /// para los vehículos guardados antes de existir [createdAt].
  static DateTime? _createdAtFromId(String id) {
    final millis = int.tryParse(id.replaceFirst('vehicle_', ''));
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  bool get isFromCatalog => modelId != null && variantId != null;

  /// Calcula la energía restante en kWh
  double get currentBatteryKwh => batteryCapacityKwh * (currentBatteryPercent / 100);

  /// Calcula cuánta energía se necesita para llegar al 100%
  double get energyNeededForFullCharge =>
      batteryCapacityKwh - currentBatteryKwh;

  /// Autonomía con el nivel de batería actual.
  double? get currentRangeKm => estimatedRangeKm == null
      ? null
      : estimatedRangeKm! * currentBatteryPercent / 100;

  /// Estima el tiempo de carga dado un cargador
  Duration estimateChargingTime(double chargerPowerKw, {double targetPercent = 80}) {
    final targetKwh = batteryCapacityKwh * (targetPercent / 100);
    final kwhToCharge = targetKwh - currentBatteryKwh;
    
    if (kwhToCharge <= 0) return Duration.zero;
    
    // Considerar que la carga se ralentiza después del 80%
    final effectivePower = chargerPowerKw > (maxChargingPowerKw ?? chargerPowerKw)
        ? (maxChargingPowerKw ?? chargerPowerKw)
        : chargerPowerKw;
    
    final hours = kwhToCharge / effectivePower;
    return Duration(minutes: (hours * 60).ceil());
  }

  /// Verifica si puede llegar a cierta distancia con la carga actual
  bool canReachDistance(double distanceKm) {
    final range = currentRangeKm;
    if (range == null) return true; // No sabemos, asumimos que sí
    return range >= distanceKm;
  }

  /// Calcula el porcentaje de batería restante después de un viaje
  double batteryPercentAfterTrip(double distanceKm) {
    if (estimatedRangeKm == null || estimatedRangeKm == 0) {
      return currentBatteryPercent;
    }

    final percentUsed = distanceKm / estimatedRangeKm! * 100;
    return (currentBatteryPercent - percentUsed).clamp(0, 100);
  }

  /// Formato local (SharedPreferences): incluye las especificaciones ya
  /// resueltas para mostrarlas sin consultar el catálogo.
  factory Vehicle.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at'] as String?;
    return Vehicle(
      id: json['id'] as String,
      name: json['name'] as String?,
      modelId: json['model_id'] as String?,
      variantId: json['variant_id'] as String?,
      brand: json['brand'] as String,
      model: json['model'] as String,
      variantName: json['variant_name'] as String?,
      year: json['year'] as int,
      batteryCapacityKwh: (json['battery_capacity_kwh'] as num).toDouble(),
      currentBatteryPercent: (json['current_battery_percent'] as num).toDouble(),
      estimatedRangeKm: json['estimated_range_km'] != null
          ? (json['estimated_range_km'] as num).toDouble()
          : null,
      compatibleConnectors: (json['compatible_connectors'] as List<dynamic>)
          .map((c) => c as String)
          .toList(),
      maxChargingPowerKw: json['max_charging_power_kw'] != null
          ? (json['max_charging_power_kw'] as num).toDouble()
          : null,
      imageUrl: json['image_url'] as String?,
      isPrimary: json['is_primary'] as bool? ?? false,
      createdAt: createdAt != null ? DateTime.tryParse(createdAt) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'model_id': modelId,
      'variant_id': variantId,
      'brand': brand,
      'model': model,
      'variant_name': variantName,
      'year': year,
      'battery_capacity_kwh': batteryCapacityKwh,
      'current_battery_percent': currentBatteryPercent,
      'estimated_range_km': estimatedRangeKm,
      'compatible_connectors': compatibleConnectors,
      'max_charging_power_kw': maxChargingPowerKw,
      'image_url': imageUrl,
      'is_primary': isPrimary,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Copia el vehículo. Las especificaciones de catálogo no se cambian aquí:
  /// para cambiar de modelo se crea con [Vehicle.fromCatalog].
  Vehicle copyWith({
    String? id,
    String? name,
    int? year,
    double? currentBatteryPercent,
    List<String>? compatibleConnectors,
    String? imageUrl,
    bool? isPrimary,
  }) {
    return Vehicle(
      id: id ?? this.id,
      name: name ?? this.name,
      modelId: modelId,
      variantId: variantId,
      brand: brand,
      model: model,
      variantName: variantName,
      year: year ?? this.year,
      batteryCapacityKwh: batteryCapacityKwh,
      currentBatteryPercent: currentBatteryPercent ?? this.currentBatteryPercent,
      estimatedRangeKm: estimatedRangeKm,
      compatibleConnectors: compatibleConnectors ?? this.compatibleConnectors,
      maxChargingPowerKw: maxChargingPowerKw,
      imageUrl: imageUrl ?? this.imageUrl,
      isPrimary: isPrimary ?? this.isPrimary,
      createdAt: createdAt,
    );
  }

  /// Marca, modelo y versión, p. ej. "BYD Dolphin 44.9 kWh".
  String get fullModelName =>
      [brand, model, if (variantName != null) variantName].join(' ');

  String get displayName => name ?? '$brand $model';

  @override
  String toString() => 'Vehicle($displayName, $currentBatteryPercent%)';
}

/// Modelo de sesión de carga
class ChargingSession {
  final String id;
  final String stationId;
  final String stationName;
  final String connectorId;
  final DateTime startTime;
  final DateTime? endTime;
  final double startBatteryPercent;
  final double? endBatteryPercent;
  final double? energyDeliveredKwh;
  final double? cost;
  final String? currency;
  final ChargingSessionStatus status;

  const ChargingSession({
    required this.id,
    required this.stationId,
    required this.stationName,
    required this.connectorId,
    required this.startTime,
    this.endTime,
    required this.startBatteryPercent,
    this.endBatteryPercent,
    this.energyDeliveredKwh,
    this.cost,
    this.currency,
    required this.status,
  });

  Duration? get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  bool get isActive => status == ChargingSessionStatus.charging;

  factory ChargingSession.fromJson(Map<String, dynamic> json) {
    return ChargingSession(
      id: json['id'] as String,
      stationId: json['station_id'] as String,
      stationName: json['station_name'] as String,
      connectorId: json['connector_id'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null
          ? DateTime.parse(json['end_time'] as String)
          : null,
      startBatteryPercent: (json['start_battery_percent'] as num).toDouble(),
      endBatteryPercent: json['end_battery_percent'] != null
          ? (json['end_battery_percent'] as num).toDouble()
          : null,
      energyDeliveredKwh: json['energy_delivered_kwh'] != null
          ? (json['energy_delivered_kwh'] as num).toDouble()
          : null,
      cost: json['cost'] != null
          ? (json['cost'] as num).toDouble()
          : null,
      currency: json['currency'] as String?,
      status: ChargingSessionStatus.fromString(json['status'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'station_id': stationId,
      'station_name': stationName,
      'connector_id': connectorId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'start_battery_percent': startBatteryPercent,
      'end_battery_percent': endBatteryPercent,
      'energy_delivered_kwh': energyDeliveredKwh,
      'cost': cost,
      'currency': currency,
      'status': status.apiValue,
    };
  }
}

enum ChargingSessionStatus {
  charging('Cargando', 'charging'),
  completed('Completada', 'completed'),
  stopped('Detenida', 'stopped'),
  error('Error', 'error');

  final String displayName;
  final String apiValue;

  const ChargingSessionStatus(this.displayName, this.apiValue);

  static ChargingSessionStatus fromString(String value) {
    return ChargingSessionStatus.values.firstWhere(
      (s) => s.apiValue == value,
      orElse: () => ChargingSessionStatus.error,
    );
  }
}
