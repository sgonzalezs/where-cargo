import '../enums/charging_enums.dart';

/// Modelo de conector de carga
class Connector {
  final String id;
  final ConnectorType type;
  final ChargingType chargingType;
  final double powerKw;
  final ConnectorStatus status;
  final double? pricePerKwh;
  final String? currency;

  const Connector({
    required this.id,
    required this.type,
    required this.chargingType,
    required this.powerKw,
    required this.status,
    this.pricePerKwh,
    this.currency,
  });

  ChargingSpeed get chargingSpeed => ChargingSpeed.fromPower(powerKw);

  bool get isAvailable => status == ConnectorStatus.available;

  bool get isFree => pricePerKwh == null || pricePerKwh == 0;

  factory Connector.fromJson(Map<String, dynamic> json) {
    return Connector(
      id: json['id'] as String,
      type: ConnectorType.fromString(json['type'] as String),
      chargingType: ChargingType.fromString(json['charging_type'] as String),
      powerKw: (json['power_kw'] as num).toDouble(),
      status: ConnectorStatus.fromString(json['status'] as String),
      pricePerKwh: json['price_per_kwh'] != null
          ? (json['price_per_kwh'] as num).toDouble()
          : null,
      currency: json['currency'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.apiValue,
      'charging_type': chargingType.apiValue,
      'power_kw': powerKw,
      'status': status.apiValue,
      'price_per_kwh': pricePerKwh,
      'currency': currency,
    };
  }

  Connector copyWith({
    String? id,
    ConnectorType? type,
    ChargingType? chargingType,
    double? powerKw,
    ConnectorStatus? status,
    double? pricePerKwh,
    String? currency,
  }) {
    return Connector(
      id: id ?? this.id,
      type: type ?? this.type,
      chargingType: chargingType ?? this.chargingType,
      powerKw: powerKw ?? this.powerKw,
      status: status ?? this.status,
      pricePerKwh: pricePerKwh ?? this.pricePerKwh,
      currency: currency ?? this.currency,
    );
  }
}
