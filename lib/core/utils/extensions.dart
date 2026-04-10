import 'package:flutter/material.dart';

/// Extensiones para String
extension StringExtensions on String {
  /// Capitaliza la primera letra
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// Capitaliza cada palabra
  String capitalizeWords() {
    return split(' ').map((word) => word.capitalize()).join(' ');
  }

  /// Verifica si es un email válido
  bool get isValidEmail {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(this);
  }
}

/// Extensiones para números
extension DoubleExtensions on double {
  /// Formatea distancia en km o m
  String formatDistance() {
    if (this >= 1) {
      return '${toStringAsFixed(1)} km';
    } else {
      return '${(this * 1000).round()} m';
    }
  }

  /// Formatea potencia en kW
  String formatPower() {
    return '${toStringAsFixed(0)} kW';
  }

  /// Formatea porcentaje de batería
  String formatBatteryPercentage() {
    return '${toStringAsFixed(0)}%';
  }
}

/// Extensiones para Duration
extension DurationExtensions on Duration {
  /// Formatea duración en horas y minutos
  String formatDuration() {
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}min';
    }
    return '${minutes}min';
  }
}

/// Extensiones para BuildContext
extension ContextExtensions on BuildContext {
  /// Obtiene el tema actual
  ThemeData get theme => Theme.of(this);
  
  /// Obtiene el esquema de colores
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  
  /// Obtiene el estilo de texto
  TextTheme get textTheme => Theme.of(this).textTheme;
  
  /// Obtiene el tamaño de pantalla
  Size get screenSize => MediaQuery.of(this).size;
  
  /// Obtiene el ancho de pantalla
  double get screenWidth => MediaQuery.of(this).size.width;
  
  /// Obtiene el alto de pantalla
  double get screenHeight => MediaQuery.of(this).size.height;
  
  /// Muestra un SnackBar
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }
}

/// Extensiones para DateTime
extension DateTimeExtensions on DateTime {
  /// Formatea como hora (HH:mm)
  String formatTime() {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// Formatea como fecha corta
  String formatShortDate() {
    return '$day/${month.toString().padLeft(2, '0')}/$year';
  }

  /// Verifica si es hoy
  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }
}
