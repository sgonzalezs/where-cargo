/// Horario de operación de una estación
class OperatingHours {
  final int dayOfWeek; // 1 = Lunes, 7 = Domingo
  final String openTime; // "08:00"
  final String closeTime; // "22:00"
  final bool is24Hours;
  final bool isClosed;

  const OperatingHours({
    required this.dayOfWeek,
    required this.openTime,
    required this.closeTime,
    this.is24Hours = false,
    this.isClosed = false,
  });

  String get dayName {
    switch (dayOfWeek) {
      case 1:
        return 'Lunes';
      case 2:
        return 'Martes';
      case 3:
        return 'Miércoles';
      case 4:
        return 'Jueves';
      case 5:
        return 'Viernes';
      case 6:
        return 'Sábado';
      case 7:
        return 'Domingo';
      default:
        return '';
    }
  }

  String get shortDayName {
    switch (dayOfWeek) {
      case 1:
        return 'Lun';
      case 2:
        return 'Mar';
      case 3:
        return 'Mié';
      case 4:
        return 'Jue';
      case 5:
        return 'Vie';
      case 6:
        return 'Sáb';
      case 7:
        return 'Dom';
      default:
        return '';
    }
  }

  String get displayHours {
    if (isClosed) return 'Cerrado';
    if (is24Hours) return '24 horas';
    return '$openTime - $closeTime';
  }

  bool isOpenAt(DateTime dateTime) {
    if (isClosed) return false;
    if (is24Hours) return true;

    // Convertir dayOfWeek de Dart (1=Lunes) a nuestro formato
    if (dateTime.weekday != dayOfWeek) return false;

    final currentMinutes = dateTime.hour * 60 + dateTime.minute;
    final openMinutes = _parseTimeToMinutes(openTime);
    final closeMinutes = _parseTimeToMinutes(closeTime);

    return currentMinutes >= openMinutes && currentMinutes < closeMinutes;
  }

  int _parseTimeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  factory OperatingHours.fromJson(Map<String, dynamic> json) {
    return OperatingHours(
      dayOfWeek: json['day_of_week'] as int,
      openTime: json['open_time'] as String? ?? '00:00',
      closeTime: json['close_time'] as String? ?? '23:59',
      is24Hours: json['is_24_hours'] as bool? ?? false,
      isClosed: json['is_closed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'day_of_week': dayOfWeek,
      'open_time': openTime,
      'close_time': closeTime,
      'is_24_hours': is24Hours,
      'is_closed': isClosed,
    };
  }

  /// Crea horarios por defecto (24/7)
  static List<OperatingHours> default24x7() {
    return List.generate(
      7,
      (index) => OperatingHours(
        dayOfWeek: index + 1,
        openTime: '00:00',
        closeTime: '23:59',
        is24Hours: true,
      ),
    );
  }
}

/// Helper para manejar lista de horarios
class OperatingSchedule {
  final List<OperatingHours> hours;

  const OperatingSchedule({required this.hours});

  bool get is24x7 => hours.every((h) => h.is24Hours && !h.isClosed);

  bool isOpenNow() {
    final now = DateTime.now();
    final todayHours = hours.firstWhere(
      (h) => h.dayOfWeek == now.weekday,
      orElse: () => OperatingHours(
        dayOfWeek: now.weekday,
        openTime: '00:00',
        closeTime: '00:00',
        isClosed: true,
      ),
    );
    return todayHours.isOpenAt(now);
  }

  String get currentStatus => isOpenNow() ? 'Abierto' : 'Cerrado';

  factory OperatingSchedule.fromJson(List<dynamic> json) {
    return OperatingSchedule(
      hours: json.map((h) => OperatingHours.fromJson(h)).toList(),
    );
  }

  List<Map<String, dynamic>> toJson() {
    return hours.map((h) => h.toJson()).toList();
  }

  static OperatingSchedule default24x7() {
    return OperatingSchedule(hours: OperatingHours.default24x7());
  }
}
