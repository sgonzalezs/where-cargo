import 'package:flutter/material.dart';

import '../../data/services/navigation_service.dart';
import '../../../../core/theme/app_colors.dart';

/// Widget que muestra opciones de navegación
class NavigationOptionsSheet extends StatelessWidget {
  final double destinationLat;
  final double destinationLng;
  final String? destinationName;
  final NavigationService _navigationService = NavigationService();

  NavigationOptionsSheet({
    super.key,
    required this.destinationLat,
    required this.destinationLng,
    this.destinationName,
  });

  @override
  Widget build(BuildContext context) {
    final options = _navigationService.getNavigationOptions(
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      destinationName: destinationName,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Abrir con',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          if (destinationName != null) ...[
            const SizedBox(height: 4),
            Text(
              destinationName!,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: options.map((option) {
              return _buildNavigationButton(
                context,
                name: option.name,
                icon: _getIconForApp(option.icon),
                color: _getColorForApp(option.icon),
                onTap: () async {
                  final success = await option.onTap();
                  if (!success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('No se pudo abrir ${option.name}'),
                      ),
                    );
                  } else {
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copiar coordenadas'),
            onTap: () async {
              await _navigationService.copyCoordinates(
                lat: destinationLat,
                lng: destinationLng,
              );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Coordenadas copiadas'),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('Compartir ubicación'),
            onTap: () {
              // TODO: Implementar share con url_launcher
              // final link = _navigationService.generateShareLink(
              //   lat: destinationLat,
              //   lng: destinationLng,
              //   name: destinationName,
              // );
              Navigator.pop(context);
            },
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildNavigationButton(
    BuildContext context, {
    required String name,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForApp(String icon) {
    switch (icon) {
      case 'google_maps':
        return Icons.map;
      case 'waze':
        return Icons.navigation;
      case 'apple_maps':
        return Icons.explore;
      default:
        return Icons.directions;
    }
  }

  Color _getColorForApp(String icon) {
    switch (icon) {
      case 'google_maps':
        return const Color(0xFF4285F4);
      case 'waze':
        return const Color(0xFF33CCFF);
      case 'apple_maps':
        return const Color(0xFF007AFF);
      default:
        return AppColors.primary;
    }
  }
}

/// Muestra el sheet de opciones de navegación
void showNavigationOptions(
  BuildContext context, {
  required double destinationLat,
  required double destinationLng,
  String? destinationName,
}) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => NavigationOptionsSheet(
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      destinationName: destinationName,
    ),
  );
}
