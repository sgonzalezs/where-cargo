import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../charging_stations/domain/models/charging_station.dart';
import '../../../../core/theme/app_colors.dart';

/// Generador de marcadores personalizados para Google Maps
/// Utiliza Canvas para dibujar directamente sin necesidad de renderizar widgets
class MarkerGenerator {
  // Cache de marcadores generados
  static final Map<String, BitmapDescriptor> _cache = {};

  /// Genera un marcador personalizado para una estación
  static Future<BitmapDescriptor> generateMarker({
    required int powerKw,
    required int availableConnectors,
    required int totalConnectors,
    required bool isAvailable,
    bool isCompatibleWithVehicle = false,
    bool hasCompleteData = true,
  }) async {
    // Crear key para cache
    final cacheKey =
        'marker_${powerKw}_${availableConnectors}_${totalConnectors}_${isAvailable}_${isCompatibleWithVehicle}_$hasCompleteData';
    
    // Retornar de cache si existe
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // Generar la imagen del marcador
    final descriptor = await _createMarkerBitmap(
      powerKw: powerKw,
      availableConnectors: availableConnectors,
      totalConnectors: totalConnectors,
      isAvailable: isAvailable,
      isCompatibleWithVehicle: isCompatibleWithVehicle,
      hasCompleteData: hasCompleteData,
    );
    
    // Guardar en cache
    _cache[cacheKey] = descriptor;
    
    return descriptor;
  }

  /// Genera un marcador para una estación de carga.
  /// Si se pasan [vehicleConnectors] (apiValues del vehículo del usuario),
  /// se marca la estación con estrella dorada cuando es compatible.
  static Future<BitmapDescriptor> generateStationMarker(
    ChargingStation station, {
    List<String>? vehicleConnectors,
  }) async {
    bool compatible = false;
    if (vehicleConnectors != null && vehicleConnectors.isNotEmpty) {
      compatible = vehicleConnectors.any(
        (connId) => station.connectorTypes.any((type) => type.apiValue == connId),
      );
    }
    return generateMarker(
      powerKw: station.maxPowerKw.toInt(),
      availableConnectors: station.availableConnectorCount,
      totalConnectors: station.totalConnectorCount,
      isAvailable: station.hasAvailableConnectors,
      isCompatibleWithVehicle: compatible,
      hasCompleteData: station.hasCompleteData,
    );
  }

  /// Genera un marcador tradicional para la ubicación del usuario (pin verde y blanco)
  /// Tamaño lógico del marcador de usuario (el anclaje usa la punta).
  static const double userMarkerWidth = 44;
  static const double userMarkerHeight = 58;

  /// Punto de anclaje: la punta de la gota, para que señale la ubicación exacta.
  static const Offset userMarkerAnchor = Offset(0.5, 54 / 58);

  /// Genera el marcador de la ubicación del usuario: una gota ancha en el
  /// color de la app con un círculo blanco y un vehículo en el centro.
  static Future<BitmapDescriptor> generateUserLocationMarker() async {
    const String cacheKey = 'marker_user_location_v2';

    // Retornar de cache si existe
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // Se dibuja a 3x para que se vea nítido en pantallas de alta densidad
    const double scale = 3;
    const double width = userMarkerWidth * scale;
    const double height = userMarkerHeight * scale;
    const double cx = width / 2;
    const double headRadius = 19 * scale;
    const double headCenterY = 2 * scale + headRadius;
    const double tipY = 54 * scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Sombra suave bajo la punta
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(cx, tipY),
        width: 14 * scale,
        height: 4 * scale,
      ),
      Paint()
        ..color = Colors.black.withAlpha(60)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2 * scale),
    );

    // Gota: cabeza circular y lados curvos que se cierran en una punta
    final pinPath = Path()
      ..moveTo(cx, tipY)
      ..cubicTo(
        cx - headRadius * 0.3, tipY - 8 * scale,
        cx - headRadius, headCenterY + headRadius * 0.8,
        cx - headRadius, headCenterY,
      )
      ..arcToPoint(
        const Offset(cx + headRadius, headCenterY),
        radius: const Radius.circular(headRadius),
        clockwise: true,
      )
      ..cubicTo(
        cx + headRadius, headCenterY + headRadius * 0.8,
        cx + headRadius * 0.3, tipY - 8 * scale,
        cx, tipY,
      )
      ..close();

    // Borde blanco para que destaque sobre el mapa y los marcadores verdes
    canvas.drawPath(
      pinPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(pinPath, Paint()..color = AppColors.primary);

    // Círculo blanco interior
    canvas.drawCircle(
      const Offset(cx, headCenterY),
      headRadius * 0.68,
      Paint()..color = Colors.white,
    );

    // Vehículo en el centro (glifo de Material Icons)
    const carIcon = Icons.directions_car;
    final iconPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(carIcon.codePoint),
        style: TextStyle(
          fontSize: headRadius * 0.9,
          fontFamily: carIcon.fontFamily,
          package: carIcon.fontPackage,
          color: AppColors.primaryDark,
        ),
      )
      ..layout();
    iconPainter.paint(
      canvas,
      Offset(
        cx - iconPainter.width / 2,
        headCenterY - iconPainter.height / 2,
      ),
    );

    // Convertir a imagen
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    }

    final descriptor = BitmapDescriptor.bytes(
      byteData.buffer.asUint8List(),
      width: userMarkerWidth,
      height: userMarkerHeight,
    );

    // Guardar en cache
    _cache[cacheKey] = descriptor;

    return descriptor;
  }

  /// Limpia el cache de marcadores
  static void clearCache() {
    _cache.clear();
  }

  /// Crea la imagen del marcador usando Canvas
  /// Diseño: Fondo verde/naranja, ícono blanco con rayo verde, textos blancos
  static Future<BitmapDescriptor> _createMarkerBitmap({
    required int powerKw,
    required int availableConnectors,
    required int totalConnectors,
    required bool isAvailable,
    bool isCompatibleWithVehicle = false,
    bool hasCompleteData = true,
  }) async {
    // Dibujamos a alta resolución para mantener nitidez
    const double scale = 2.5;
    const double width = 72 * scale;
    const double height = 40 * scale;
    const double iconSize = 22 * scale;
    const double borderRadius = 8 * scale;
    const double triangleSize = 7 * scale;
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Estaciones sin datos completos: color ámbar para indicar "datos limitados".
    // Estaciones con datos completos: verde si disponible, gris si ocupada.
    final Color accentColor = !hasCompleteData
        ? const Color(0xFFE69900) // ámbar
        : (isAvailable
            ? AppColors.stationAvailable
            : AppColors.stationOccupied);

    // Sombra
    final shadowPaint = Paint()
      ..color = Colors.black.withAlpha(30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    
    final shadowRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 4, width - 4, height - triangleSize - 4),
      Radius.circular(borderRadius),
    );
    canvas.drawRRect(shadowRect, shadowPaint);

    // Fondo verde/naranja del marcador (invertido)
    final bgPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height - triangleSize),
      Radius.circular(borderRadius),
    );
    canvas.drawRRect(bgRect, bgPaint);

    // Triángulo inferior
    final trianglePath = Path()
      ..moveTo(width / 2 - triangleSize, height - triangleSize)
      ..lineTo(width / 2, height)
      ..lineTo(width / 2 + triangleSize, height - triangleSize)
      ..close();
    canvas.drawPath(trianglePath, bgPaint);

    // Ícono de rayo (fondo blanco, rayo verde/naranja)
    final iconBgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    final iconRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(6 * scale, 5 * scale, iconSize, iconSize),
      Radius.circular(6 * scale),
    );
    canvas.drawRRect(iconRect, iconBgPaint);

    // Dibujar el símbolo de rayo (en color verde/naranja)
    _drawBoltIcon(canvas, 6 * scale + iconSize / 2, 5 * scale + iconSize / 2, iconSize * 0.4, accentColor);

    // Texto de potencia (blanco sobre fondo verde)
    final powerText = hasCompleteData ? '$powerKw kW' : '? kW';
    const powerFontSize = 11.0;
    final powerStyle = ui.TextStyle(
      color: Colors.white,
      fontSize: powerFontSize * scale,
      fontWeight: FontWeight.bold,
    );
    final powerParagraph = _createParagraph(
      powerText, powerStyle, 42 * scale, powerFontSize * scale, FontWeight.bold,
    );
    canvas.drawParagraph(powerParagraph, Offset(32 * scale, 4 * scale));

    // Indicador de disponibilidad (punto blanco)
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(35 * scale, 23 * scale),
      3 * scale,
      dotPaint,
    );

    // Texto de disponibilidad (blanco)
    final availText =
        hasCompleteData ? '$availableConnectors/$totalConnectors' : 'info';
    const availFontSize = 10.0;
    final availStyle = ui.TextStyle(
      color: Colors.white,
      fontSize: availFontSize * scale,
      fontWeight: FontWeight.w600,
    );
    final availParagraph = _createParagraph(
      availText, availStyle, 38 * scale, availFontSize * scale, FontWeight.w600,
    );
    canvas.drawParagraph(availParagraph, Offset(41 * scale, 19 * scale));

    // Badge de compatibilidad con vehículo: estrella dorada en esquina superior derecha
    if (isCompatibleWithVehicle) {
      final badgeR = 9.5 * scale;
      final badgeCx = width - badgeR;
      final badgeCy = badgeR;

      // Círculo blanco de fondo (borde)
      canvas.drawCircle(
        Offset(badgeCx, badgeCy),
        badgeR,
        Paint()..color = Colors.white,
      );
      // Relleno dorado
      canvas.drawCircle(
        Offset(badgeCx, badgeCy),
        badgeR - 2 * scale,
        Paint()..color = const Color(0xFFFFB300),
      );
      // Estrella blanca
      _drawStar(
        canvas,
        badgeCx,
        badgeCy,
        (badgeR - 2 * scale) * 0.68,
        Colors.white,
      );
    }

    // Convertir a imagen
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    if (byteData == null) {
      return BitmapDescriptor.defaultMarkerWithHue(
        isAvailable ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange,
      );
    }

    // Usamos width/height para escalar el marcador en el mapa
    // Esto mantiene la alta resolución pero muestra el marcador más pequeño
    return BitmapDescriptor.bytes(
      byteData.buffer.asUint8List(),
      width: 72,
      height: 40,
    );
  }

  /// Dibuja una estrella de 5 puntas centrada en (cx, cy)
  static void _drawStar(
    Canvas canvas,
    double cx,
    double cy,
    double outerRadius,
    Color color,
  ) {
    const int points = 5;
    final innerRadius = outerRadius * 0.42;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    for (int i = 0; i < points * 2; i++) {
      final radius = i.isEven ? outerRadius : innerRadius;
      final angle = (i * pi / points) - (pi / 2);
      final x = cx + radius * cos(angle);
      final y = cy + radius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  /// Dibuja el ícono de rayo
  static void _drawBoltIcon(Canvas canvas, double cx, double cy, double size, [Color color = Colors.white]) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    // Forma del rayo simplificada
    path.moveTo(cx + size * 0.1, cy - size);
    path.lineTo(cx - size * 0.5, cy + size * 0.1);
    path.lineTo(cx - size * 0.05, cy + size * 0.1);
    path.lineTo(cx - size * 0.15, cy + size);
    path.lineTo(cx + size * 0.5, cy - size * 0.15);
    path.lineTo(cx + size * 0.05, cy - size * 0.15);
    path.close();

    canvas.drawPath(path, paint);
  }

  /// Crea un párrafo de texto
  static ui.Paragraph _createParagraph(
    String text,
    ui.TextStyle style,
    double maxWidth,
    double fontSize,
    FontWeight fontWeight,
  ) {
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      fontWeight: fontWeight,
    ))
      ..pushStyle(style)
      ..addText(text);
    
    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));
    
    return paragraph;
  }
}
