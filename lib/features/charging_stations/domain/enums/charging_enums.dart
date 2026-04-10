/// Tipos de conectores para vehículos eléctricos
enum ConnectorType {
  type1('Type 1 (J1772)', 'type1'),
  type2('Type 2 (Mennekes)', 'type2'),
  ccs1('CCS Combo 1', 'ccs1'),
  ccs2('CCS Combo 2', 'ccs2'),
  chademo('CHAdeMO', 'chademo'),
  tesla('Tesla Supercharger', 'tesla'),
  teslaDestination('Tesla Destination', 'tesla_destination'),
  gbtAc('GB/T AC', 'gbt_ac'),
  gbtDc('GB/T DC', 'gbt_dc');

  final String displayName;
  final String apiValue;

  const ConnectorType(this.displayName, this.apiValue);

  static ConnectorType fromString(String value) {
    return ConnectorType.values.firstWhere(
      (type) => type.apiValue == value || type.name == value,
      orElse: () => ConnectorType.type2,
    );
  }
}

/// Tipo de carga
enum ChargingType {
  ac('AC', 'ac'),
  dc('DC', 'dc');

  final String displayName;
  final String apiValue;

  const ChargingType(this.displayName, this.apiValue);

  static ChargingType fromString(String value) {
    return ChargingType.values.firstWhere(
      (type) => type.apiValue == value || type.name == value,
      orElse: () => ChargingType.ac,
    );
  }
}

/// Velocidad de carga
enum ChargingSpeed {
  slow('Carga Lenta', 'slow', 0, 7),
  medium('Carga Media', 'medium', 7, 22),
  fast('Carga Rápida', 'fast', 22, 50),
  ultraFast('Carga Ultra Rápida', 'ultra_fast', 50, 350);

  final String displayName;
  final String apiValue;
  final double minPowerKw;
  final double maxPowerKw;

  const ChargingSpeed(
    this.displayName,
    this.apiValue,
    this.minPowerKw,
    this.maxPowerKw,
  );

  static ChargingSpeed fromPower(double powerKw) {
    if (powerKw < 7) return ChargingSpeed.slow;
    if (powerKw < 22) return ChargingSpeed.medium;
    if (powerKw < 50) return ChargingSpeed.fast;
    return ChargingSpeed.ultraFast;
  }

  static ChargingSpeed fromString(String value) {
    return ChargingSpeed.values.firstWhere(
      (speed) => speed.apiValue == value || speed.name == value,
      orElse: () => ChargingSpeed.medium,
    );
  }
}

/// Estado del punto de carga
enum StationStatus {
  available('Disponible', 'available'),
  occupied('Ocupado', 'occupied'),
  offline('Fuera de línea', 'offline'),
  maintenance('En mantenimiento', 'maintenance'),
  unknown('Desconocido', 'unknown');

  final String displayName;
  final String apiValue;

  const StationStatus(this.displayName, this.apiValue);

  static StationStatus fromString(String value) {
    return StationStatus.values.firstWhere(
      (status) => status.apiValue == value || status.name == value,
      orElse: () => StationStatus.unknown,
    );
  }
}

/// Estado del conector individual
enum ConnectorStatus {
  available('Disponible', 'available'),
  occupied('En uso', 'occupied'),
  reserved('Reservado', 'reserved'),
  faulted('Con falla', 'faulted'),
  unavailable('No disponible', 'unavailable');

  final String displayName;
  final String apiValue;

  const ConnectorStatus(this.displayName, this.apiValue);

  static ConnectorStatus fromString(String value) {
    return ConnectorStatus.values.firstWhere(
      (status) => status.apiValue == value || status.name == value,
      orElse: () => ConnectorStatus.unavailable,
    );
  }
}

/// Tipo de pago
enum PaymentType {
  free('Gratis', 'free'),
  paid('De pago', 'paid'),
  subscription('Suscripción', 'subscription'),
  membership('Membresía', 'membership');

  final String displayName;
  final String apiValue;

  const PaymentType(this.displayName, this.apiValue);

  static PaymentType fromString(String value) {
    return PaymentType.values.firstWhere(
      (type) => type.apiValue == value || type.name == value,
      orElse: () => PaymentType.paid,
    );
  }
}

/// Ciudades de Colombia disponibles
enum ColombianCity {
  bogota('Bogotá', 4.7110, -74.0721),
  medellin('Medellín', 6.2442, -75.5812),
  cali('Cali', 3.4516, -76.5320),
  barranquilla('Barranquilla', 10.9685, -74.7813),
  cartagena('Cartagena', 10.3910, -75.4794),
  bucaramanga('Bucaramanga', 7.1193, -73.1227),
  pereira('Pereira', 4.8133, -75.6961),
  manizales('Manizales', 5.0689, -75.5174),
  santaMarta('Santa Marta', 11.2408, -74.1990),
  ibague('Ibagué', 4.4389, -75.2322);

  final String displayName;
  final double latitude;
  final double longitude;

  const ColombianCity(this.displayName, this.latitude, this.longitude);
}
