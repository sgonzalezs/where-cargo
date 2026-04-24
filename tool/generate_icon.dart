// Script para generar el icono de la app
// Ejecutar con: dart run tool/generate_icon.dart

import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  print('🎨 Generando icono de Where Cargo...');
  
  // Crear directorio assets si no existe
  final assetsDir = Directory('assets');
  if (!await assetsDir.exists()) {
    await assetsDir.create();
  }
  
  // Crear imagen principal (1024x1024)
  final image = img.Image(width: 1024, height: 1024);
  
  // Colores
  final primaryGreen = img.ColorRgba8(0, 200, 83, 255);      // #00C853
  final lightGreen = img.ColorRgba8(0, 230, 118, 255);       // #00E676
  final white = img.ColorRgba8(255, 255, 255, 255);
  final lightGray = img.ColorRgba8(224, 224, 224, 255);
  final darkGray = img.ColorRgba8(189, 189, 189, 255);
  
  // Fondo verde con esquinas redondeadas
  _fillRoundedRect(image, 0, 0, 1024, 1024, 180, primaryGreen);
  
  // Círculo decorativo semi-transparente
  _fillCircle(image, 512, 480, 320, img.ColorRgba8(0, 230, 118, 64));
  
  // Estación de carga - Base blanca
  _fillRoundedRect(image, 340, 220, 344, 480, 40, white);
  
  // Pantalla de la estación
  _fillRoundedRect(image, 380, 260, 264, 160, 15, img.ColorRgba8(232, 245, 233, 255));
  
  // Rayo en la pantalla (simplificado como rectángulo)
  _fillRoundedRect(image, 480, 290, 64, 100, 10, primaryGreen);
  
  // Indicadores LED
  _fillCircle(image, 420, 460, 15, primaryGreen);
  _fillCircle(image, 470, 460, 15, primaryGreen);
  _fillCircle(image, 520, 460, 15, img.ColorRgba8(76, 175, 80, 128));
  
  // Área del conector
  _fillRoundedRect(image, 400, 520, 224, 80, 15, lightGray);
  _fillCircle(image, 470, 560, 25, darkGray);
  _fillCircle(image, 554, 560, 25, darkGray);
  
  // Cable (rectángulo curvo simplificado)
  _fillRoundedRect(image, 684, 545, 90, 30, 15, white);
  _fillRoundedRect(image, 745, 560, 30, 200, 15, white);
  
  // Conector del cable
  _fillRoundedRect(image, 660, 760, 80, 100, 15, white);
  _fillCircle(image, 700, 810, 20, darkGray);
  
  // Guardar imagen principal
  final pngBytes = img.encodePng(image);
  await File('assets/app_icon.png').writeAsBytes(pngBytes);
  print('✅ Icono principal guardado: assets/app_icon.png');
  
  // Crear versión foreground para adaptive icon (solo el icono sin fondo)
  // numChannels: 4 => RGBA con fondo realmente transparente (alpha=0)
  final foreground = img.Image(width: 1024, height: 1024, numChannels: 4);

  // Asegurar que todos los pixeles inicien completamente transparentes
  final transparent = img.ColorRgba8(0, 0, 0, 0);
  for (int y = 0; y < foreground.height; y++) {
    for (int x = 0; x < foreground.width; x++) {
      foreground.setPixel(x, y, transparent);
    }
  }
  // Copiar solo la estación sin el fondo
  _fillRoundedRect(foreground, 340, 220, 344, 480, 40, white);
  _fillRoundedRect(foreground, 380, 260, 264, 160, 15, img.ColorRgba8(232, 245, 233, 255));
  _fillRoundedRect(foreground, 480, 290, 64, 100, 10, primaryGreen);
  _fillCircle(foreground, 420, 460, 15, primaryGreen);
  _fillCircle(foreground, 470, 460, 15, primaryGreen);
  _fillCircle(foreground, 520, 460, 15, img.ColorRgba8(76, 175, 80, 128));
  _fillRoundedRect(foreground, 400, 520, 224, 80, 15, lightGray);
  _fillCircle(foreground, 470, 560, 25, darkGray);
  _fillCircle(foreground, 554, 560, 25, darkGray);
  _fillRoundedRect(foreground, 684, 545, 90, 30, 15, white);
  _fillRoundedRect(foreground, 745, 560, 30, 200, 15, white);
  _fillRoundedRect(foreground, 660, 760, 80, 100, 15, white);
  _fillCircle(foreground, 700, 810, 20, darkGray);
  
  final fgBytes = img.encodePng(foreground);
  await File('assets/app_icon_foreground.png').writeAsBytes(fgBytes);
  print('✅ Foreground guardado: assets/app_icon_foreground.png');
  
  print('');
  print('📋 Ahora ejecuta:');
  print('   flutter pub get');
  print('   dart run flutter_launcher_icons');
  print('');
}

// Función para dibujar rectángulo con esquinas redondeadas
void _fillRoundedRect(img.Image image, int x, int y, int width, int height, int radius, img.Color color) {
  // Dibujar el rectángulo principal (sin esquinas)
  for (int py = y + radius; py < y + height - radius; py++) {
    for (int px = x; px < x + width; px++) {
      if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
        image.setPixel(px, py, color);
      }
    }
  }
  
  // Dibujar las partes superior e inferior (sin esquinas)
  for (int py = y; py < y + radius; py++) {
    for (int px = x + radius; px < x + width - radius; px++) {
      if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
        image.setPixel(px, py, color);
      }
    }
  }
  for (int py = y + height - radius; py < y + height; py++) {
    for (int px = x + radius; px < x + width - radius; px++) {
      if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
        image.setPixel(px, py, color);
      }
    }
  }
  
  // Dibujar las 4 esquinas redondeadas
  _fillCorner(image, x + radius, y + radius, radius, color, 2);         // Top-left
  _fillCorner(image, x + width - radius - 1, y + radius, radius, color, 1);  // Top-right
  _fillCorner(image, x + radius, y + height - radius - 1, radius, color, 3); // Bottom-left
  _fillCorner(image, x + width - radius - 1, y + height - radius - 1, radius, color, 4); // Bottom-right
}

// Función para dibujar una esquina redondeada
void _fillCorner(img.Image image, int cx, int cy, int radius, img.Color color, int quadrant) {
  for (int py = -radius; py <= radius; py++) {
    for (int px = -radius; px <= radius; px++) {
      if (px * px + py * py <= radius * radius) {
        int x = cx + px;
        int y = cy + py;
        
        bool shouldDraw = false;
        switch (quadrant) {
          case 1: shouldDraw = px >= 0 && py <= 0; break; // Top-right
          case 2: shouldDraw = px <= 0 && py <= 0; break; // Top-left
          case 3: shouldDraw = px <= 0 && py >= 0; break; // Bottom-left
          case 4: shouldDraw = px >= 0 && py >= 0; break; // Bottom-right
        }
        
        if (shouldDraw && x >= 0 && x < image.width && y >= 0 && y < image.height) {
          image.setPixel(x, y, color);
        }
      }
    }
  }
}

// Función para dibujar un círculo relleno
void _fillCircle(img.Image image, int cx, int cy, int radius, img.Color color) {
  for (int y = -radius; y <= radius; y++) {
    for (int x = -radius; x <= radius; x++) {
      if (x * x + y * y <= radius * radius) {
        int px = cx + x;
        int py = cy + y;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          // Blend si tiene alpha
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

