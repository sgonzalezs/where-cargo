// Script para generar el Feature Graphic de Play Store
// Ejecutar con: dart run tool/generate_feature_graphic.dart

import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  print('🎨 Generando Feature Graphic para Play Store...');
  
  // Crear imagen 1024x500
  final image = img.Image(width: 1024, height: 500);
  
  // Colores
  final primaryGreen = img.ColorRgba8(0, 200, 83, 255);      // #00C853
  final darkGreen = img.ColorRgba8(0, 150, 60, 255);         // Más oscuro
  final white = img.ColorRgba8(255, 255, 255, 255);
  final lightGreen = img.ColorRgba8(0, 230, 118, 80);        // Semi-transparente
  
  // Fondo con gradiente verde (simulado con bandas)
  for (int y = 0; y < 500; y++) {
    // Gradiente de arriba a abajo
    final ratio = y / 500.0;
    final r = (0 * (1 - ratio) + 0 * ratio).round();
    final g = (200 * (1 - ratio) + 150 * ratio).round();
    final b = (83 * (1 - ratio) + 60 * ratio).round();
    final color = img.ColorRgba8(r, g, b, 255);
    
    for (int x = 0; x < 1024; x++) {
      image.setPixel(x, y, color);
    }
  }
  
  // Círculos decorativos
  _fillCircle(image, 150, 250, 200, lightGreen);
  _fillCircle(image, 900, 300, 150, lightGreen);
  _fillCircle(image, 512, 100, 80, lightGreen);
  
  // Icono de estación de carga en el centro-izquierda
  final iconX = 200;
  final iconY = 250;
  
  // Base de la estación (rectángulo blanco)
  _fillRoundedRect(image, iconX - 60, iconY - 100, 120, 200, 15, white);
  
  // Rayo en el centro
  _fillRoundedRect(image, iconX - 15, iconY - 50, 30, 80, 5, primaryGreen);
  
  // LEDs
  _fillCircle(image, iconX - 25, iconY + 70, 8, primaryGreen);
  _fillCircle(image, iconX, iconY + 70, 8, primaryGreen);
  _fillCircle(image, iconX + 25, iconY + 70, 8, img.ColorRgba8(76, 175, 80, 180));
  
  // Cable
  _fillRoundedRect(image, iconX + 60, iconY - 10, 50, 20, 10, white);
  _fillRoundedRect(image, iconX + 100, iconY, 15, 80, 8, white);
  
  // Texto "WhereCargo" - usando rectángulos como placeholder
  // (En una imagen real usarías una fuente, pero aquí simulamos)
  final textY = 230;
  final textX = 380;
  
  // W
  _fillRect(image, textX, textY, 8, 50, white);
  _fillRect(image, textX + 15, textY + 30, 8, 20, white);
  _fillRect(image, textX + 30, textY, 8, 50, white);
  _fillRect(image, textX + 45, textY + 30, 8, 20, white);
  _fillRect(image, textX + 60, textY, 8, 50, white);
  
  // Línea decorativa debajo del "texto"
  _fillRoundedRect(image, 380, 300, 450, 4, 2, white);
  
  // Subtítulo área
  _fillRoundedRect(image, 380, 320, 300, 3, 1, img.ColorRgba8(255, 255, 255, 150));
  
  // Íconos de características (círculos pequeños)
  _fillCircle(image, 420, 380, 25, white);
  _fillCircle(image, 500, 380, 25, white);
  _fillCircle(image, 580, 380, 25, white);
  _fillCircle(image, 660, 380, 25, white);
  
  // Iconos dentro de los círculos (puntos verdes)
  _fillCircle(image, 420, 380, 12, primaryGreen);
  _fillCircle(image, 500, 380, 12, primaryGreen);
  _fillCircle(image, 580, 380, 12, primaryGreen);
  _fillCircle(image, 660, 380, 12, primaryGreen);
  
  // Guardar
  final pngBytes = img.encodePng(image);
  await File('assets/feature_graphic.png').writeAsBytes(pngBytes);
  
  print('✅ Feature Graphic guardado: assets/feature_graphic.png');
  print('   Tamaño: 1024 x 500 px');
}

void _fillRect(img.Image image, int x, int y, int width, int height, img.Color color) {
  for (int py = y; py < y + height && py < image.height; py++) {
    for (int px = x; px < x + width && px < image.width; px++) {
      if (px >= 0 && py >= 0) {
        image.setPixel(px, py, color);
      }
    }
  }
}

void _fillRoundedRect(img.Image image, int x, int y, int width, int height, int radius, img.Color color) {
  for (int py = y; py < y + height && py < image.height; py++) {
    for (int px = x; px < x + width && px < image.width; px++) {
      if (px >= 0 && py >= 0) {
        image.setPixel(px, py, color);
      }
    }
  }
}

void _fillCircle(img.Image image, int cx, int cy, int radius, img.Color color) {
  for (int y = -radius; y <= radius; y++) {
    for (int x = -radius; x <= radius; x++) {
      if (x * x + y * y <= radius * radius) {
        int px = cx + x;
        int py = cy + y;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          if (color is img.ColorRgba8 && color.a < 255) {
            final existing = image.getPixel(px, py);
            final alpha = color.a / 255.0;
            final newR = ((existing.r * (1 - alpha)) + (color.r * alpha)).round();
            final newG = ((existing.g * (1 - alpha)) + (color.g * alpha)).round();
            final newB = ((existing.b * (1 - alpha)) + (color.b * alpha)).round();
            image.setPixel(px, py, img.ColorRgba8(newR, newG, newB, 255));
          } else {
            image.setPixel(px, py, color);
          }
        }
      }
    }
  }
}
