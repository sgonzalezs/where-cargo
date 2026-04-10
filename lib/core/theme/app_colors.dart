import 'package:flutter/material.dart';

/// Colores de la aplicación
class AppColors {
  AppColors._();

  // Colores primarios - Verde eléctrico
  static const Color primary = Color(0xFF00C853);
  static const Color primaryLight = Color(0xFF5EFC82);
  static const Color primaryDark = Color(0xFF009624);

  // Colores secundarios
  static const Color secondary = Color(0xFF2196F3);
  static const Color secondaryLight = Color(0xFF6EC6FF);
  static const Color secondaryDark = Color(0xFF0069C0);

  // Colores de fondo
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF121212);

  // Colores de texto
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Colores de estado
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Colores específicos de estaciones
  static const Color stationAvailable = Color(0xFF4CAF50);
  static const Color stationOccupied = Color(0xFFFF9800);
  static const Color stationOffline = Color(0xFF9E9E9E);
  static const Color stationMaintenance = Color(0xFFF44336);

  // Colores de conectores
  static const Color connectorType1 = Color(0xFF1976D2);
  static const Color connectorType2 = Color(0xFF388E3C);
  static const Color connectorCCS = Color(0xFFF57C00);
  static const Color connectorCHAdeMO = Color(0xFF7B1FA2);
  static const Color connectorTesla = Color(0xFFD32F2F);
}
