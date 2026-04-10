import '../enums/charging_enums.dart';
import 'connector.dart';
import 'operating_hours.dart';

/// Modelo principal de estación de carga
class ChargingStation {
  final String id;
  final String name;
  final String? description;
  final String address;
  final String city;
  final String? state;
  final String country;
  final double latitude;
  final double longitude;
  final List<Connector> connectors;
  final StationStatus status;
  final PaymentType paymentType;
  final OperatingSchedule? operatingSchedule;
  final String? networkName; // Ej: "Celsia", "Enel X", etc.
  final String? networkLogo;
  final String? phoneNumber;
  final String? website;
  final List<String>? amenities; // Wifi, Baño, Restaurante, etc.
  final List<String>? images;
  final double? rating;
  final int? reviewCount;
  final DateTime? lastUpdated;

  // Campos calculados (se llenan con datos de ubicación del usuario)
  final double? distanceKm;
  final Duration? estimatedDrivingTime;

  const ChargingStation({
    required this.id,
    required this.name,
    this.description,
    required this.address,
    required this.city,
    this.state,
    this.country = 'Colombia',
    required this.latitude,
    required this.longitude,
    required this.connectors,
    required this.status,
    required this.paymentType,
    this.operatingSchedule,
    this.networkName,
    this.networkLogo,
    this.phoneNumber,
    this.website,
    this.amenities,
    this.images,
    this.rating,
    this.reviewCount,
    this.lastUpdated,
    this.distanceKm,
    this.estimatedDrivingTime,
  });

  // Getters útiles
  bool get isAvailable => status == StationStatus.available;

  bool get hasAvailableConnectors =>
      connectors.any((c) => c.status == ConnectorStatus.available);

  int get availableConnectorCount =>
      connectors.where((c) => c.status == ConnectorStatus.available).length;

  int get totalConnectorCount => connectors.length;

  double get maxPowerKw =>
      connectors.isEmpty
          ? 0
          : connectors.map((c) => c.powerKw).reduce((a, b) => a > b ? a : b);

  ChargingSpeed get fastestChargingSpeed => ChargingSpeed.fromPower(maxPowerKw);

  bool get isFree =>
      paymentType == PaymentType.free ||
      connectors.every((c) => c.isFree);

  bool get isOpen => operatingSchedule?.isOpenNow() ?? true;

  Set<ConnectorType> get connectorTypes =>
      connectors.map((c) => c.type).toSet();

  Set<ChargingType> get chargingTypes =>
      connectors.map((c) => c.chargingType).toSet();

  bool get hasDcCharging => chargingTypes.contains(ChargingType.dc);

  bool get hasAcCharging => chargingTypes.contains(ChargingType.ac);

  String get availabilityText =>
      '$availableConnectorCount/$totalConnectorCount disponibles';

  factory ChargingStation.fromJson(Map<String, dynamic> json) {
    return ChargingStation(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      address: json['address'] as String,
      city: json['city'] as String,
      state: json['state'] as String?,
      country: json['country'] as String? ?? 'Colombia',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      connectors: (json['connectors'] as List<dynamic>?)
              ?.map((c) => Connector.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      status: StationStatus.fromString(json['status'] as String),
      paymentType: PaymentType.fromString(json['payment_type'] as String),
      operatingSchedule: json['operating_schedule'] != null
          ? OperatingSchedule.fromJson(json['operating_schedule'] as List)
          : null,
      networkName: json['network_name'] as String?,
      networkLogo: json['network_logo'] as String?,
      phoneNumber: json['phone_number'] as String?,
      website: json['website'] as String?,
      amenities: (json['amenities'] as List<dynamic>?)
          ?.map((a) => a as String)
          .toList(),
      images: (json['images'] as List<dynamic>?)
          ?.map((i) => i as String)
          .toList(),
      rating: json['rating'] != null
          ? (json['rating'] as num).toDouble()
          : null,
      reviewCount: json['review_count'] as int?,
      lastUpdated: json['last_updated'] != null
          ? DateTime.parse(json['last_updated'] as String)
          : null,
      distanceKm: json['distance_km'] != null
          ? (json['distance_km'] as num).toDouble()
          : null,
      estimatedDrivingTime: json['estimated_driving_time_minutes'] != null
          ? Duration(minutes: json['estimated_driving_time_minutes'] as int)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'address': address,
      'city': city,
      'state': state,
      'country': country,
      'latitude': latitude,
      'longitude': longitude,
      'connectors': connectors.map((c) => c.toJson()).toList(),
      'status': status.apiValue,
      'payment_type': paymentType.apiValue,
      'operating_schedule': operatingSchedule?.toJson(),
      'network_name': networkName,
      'network_logo': networkLogo,
      'phone_number': phoneNumber,
      'website': website,
      'amenities': amenities,
      'images': images,
      'rating': rating,
      'review_count': reviewCount,
      'last_updated': lastUpdated?.toIso8601String(),
      'distance_km': distanceKm,
      'estimated_driving_time_minutes': estimatedDrivingTime?.inMinutes,
    };
  }

  ChargingStation copyWith({
    String? id,
    String? name,
    String? description,
    String? address,
    String? city,
    String? state,
    String? country,
    double? latitude,
    double? longitude,
    List<Connector>? connectors,
    StationStatus? status,
    PaymentType? paymentType,
    OperatingSchedule? operatingSchedule,
    String? networkName,
    String? networkLogo,
    String? phoneNumber,
    String? website,
    List<String>? amenities,
    List<String>? images,
    double? rating,
    int? reviewCount,
    DateTime? lastUpdated,
    double? distanceKm,
    Duration? estimatedDrivingTime,
  }) {
    return ChargingStation(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      connectors: connectors ?? this.connectors,
      status: status ?? this.status,
      paymentType: paymentType ?? this.paymentType,
      operatingSchedule: operatingSchedule ?? this.operatingSchedule,
      networkName: networkName ?? this.networkName,
      networkLogo: networkLogo ?? this.networkLogo,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      website: website ?? this.website,
      amenities: amenities ?? this.amenities,
      images: images ?? this.images,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      distanceKm: distanceKm ?? this.distanceKm,
      estimatedDrivingTime: estimatedDrivingTime ?? this.estimatedDrivingTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChargingStation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
