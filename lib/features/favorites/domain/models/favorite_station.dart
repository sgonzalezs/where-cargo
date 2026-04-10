import '../../../charging_stations/domain/models/charging_station.dart';

/// Modelo de estación favorita
class FavoriteStation {
  final String id;
  final String stationId;
  final DateTime addedAt;
  final String? notes;
  final ChargingStation? station;

  const FavoriteStation({
    required this.id,
    required this.stationId,
    required this.addedAt,
    this.notes,
    this.station,
  });

  factory FavoriteStation.fromJson(Map<String, dynamic> json) {
    return FavoriteStation(
      id: json['id'] as String,
      stationId: json['station_id'] as String,
      addedAt: DateTime.parse(json['added_at'] as String),
      notes: json['notes'] as String?,
      station: json['station'] != null
          ? ChargingStation.fromJson(json['station'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'station_id': stationId,
      'added_at': addedAt.toIso8601String(),
      'notes': notes,
      'station': station?.toJson(),
    };
  }

  FavoriteStation copyWith({
    String? id,
    String? stationId,
    DateTime? addedAt,
    String? notes,
    ChargingStation? station,
  }) {
    return FavoriteStation(
      id: id ?? this.id,
      stationId: stationId ?? this.stationId,
      addedAt: addedAt ?? this.addedAt,
      notes: notes ?? this.notes,
      station: station ?? this.station,
    );
  }
}
