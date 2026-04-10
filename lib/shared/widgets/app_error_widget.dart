import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Widget de error personalizado
class AppErrorWidget extends StatelessWidget {
  final String? title;
  final String message;
  final VoidCallback? onRetry;
  final IconData? icon;

  const AppErrorWidget({
    super.key,
    this.title,
    required this.message,
    this.onRetry,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon ?? Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            if (title != null) ...[
              Text(
                title!,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Error de conexión
  factory AppErrorWidget.network({VoidCallback? onRetry}) {
    return AppErrorWidget(
      icon: Icons.wifi_off,
      title: 'Sin conexión',
      message: 'No hay conexión a internet.\nVerifica tu conexión e intenta de nuevo.',
      onRetry: onRetry,
    );
  }

  /// Error de servidor
  factory AppErrorWidget.server({VoidCallback? onRetry}) {
    return AppErrorWidget(
      icon: Icons.cloud_off,
      title: 'Error del servidor',
      message: 'Hubo un problema con el servidor.\nIntenta de nuevo más tarde.',
      onRetry: onRetry,
    );
  }

  /// Error de ubicación
  factory AppErrorWidget.location({VoidCallback? onRetry}) {
    return AppErrorWidget(
      icon: Icons.location_off,
      title: 'Ubicación no disponible',
      message: 'No pudimos obtener tu ubicación.\nVerifica los permisos de la aplicación.',
      onRetry: onRetry,
    );
  }

  /// Estado vacío
  static Widget empty({
    String? title,
    String? message,
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    return _EmptyStateWidget(
      title: title ?? 'Sin resultados',
      message: message ?? 'No se encontraron elementos',
      onAction: onAction,
      actionLabel: actionLabel,
    );
  }
}

class _EmptyStateWidget extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onAction;
  final String? actionLabel;

  const _EmptyStateWidget({
    required this.title,
    required this.message,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
