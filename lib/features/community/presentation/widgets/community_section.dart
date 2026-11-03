import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/models/community_station.dart';

/// Sección "Comunidad" del detalle de una estación: estado reportado,
/// conectores confirmados, etiquetas frecuentes y botón para reportar.
class CommunitySection extends StatelessWidget {
  final CommunityStation? community;
  final VoidCallback onReport;
  final bool isPreparingReport;

  const CommunitySection({
    super.key,
    required this.community,
    required this.onReport,
    this.isPreparingReport = false,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final c = community;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Comunidad',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StatusBanner(community: c, now: now),
          if (c != null && c.connectors.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Conectores confirmados',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in c.rankedConnectors)
                  Chip(
                    avatar: const Icon(
                      Icons.verified_outlined,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    label: Text(
                      '${e.key.type.displayName} · ${e.key.power.label}'
                      '${e.value > 1 ? ' (${e.value})' : ''}',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          if (c != null && (c.tags.isNotEmpty || c.isFree != null)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.isFree != null)
                  Chip(
                    avatar: Icon(
                      c.isFree! ? Icons.money_off : Icons.attach_money,
                      size: 16,
                    ),
                    label: Text(
                      c.isFree!
                          ? 'Gratis'
                          : c.pricePerKwh != null
                          ? 'De pago · \$${c.pricePerKwh!.toStringAsFixed(0)}/kWh'
                          : 'De pago',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                for (final e in c.rankedTags)
                  Chip(
                    label: Text(e.key.label),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isPreparingReport ? null : onReport,
              icon: isPreparingReport
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.campaign_outlined),
              label: Text(
                isPreparingReport
                    ? 'Verificando ubicación…'
                    : 'Reportar estado',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final CommunityStation? community;
  final DateTime now;

  const _StatusBanner({required this.community, required this.now});

  @override
  Widget build(BuildContext context) {
    final c = community;
    final state = c?.stateAt(now) ?? CommunityState.none;
    final recent = c?.recentStatuses(now) ?? const [];
    final latest = recent.isEmpty ? null : recent.first;

    final (IconData icon, Color color, String title) = switch (state) {
      CommunityState.working => (
        Icons.check_circle,
        AppColors.success,
        'Funcionando',
      ),
      CommunityState.partial => (
        Icons.warning_amber_rounded,
        AppColors.warning,
        'Funciona parcialmente',
      ),
      CommunityState.notWorking => (
        Icons.cancel,
        AppColors.error,
        'Reportada sin servicio',
      ),
      CommunityState.mixed => (
        Icons.help_outline,
        AppColors.warning,
        'Reportes mixtos',
      ),
      CommunityState.none => (
        Icons.schedule,
        AppColors.textSecondary,
        'Sin reportes recientes',
      ),
    };

    final String subtitle;
    if (state == CommunityState.none) {
      final last = c?.lastReportAt;
      subtitle = last == null
          ? 'Sé el primero en contar cómo funciona esta estación.'
          : 'Último reporte ${timeAgo(last, now)}.';
    } else {
      final drivers = recent.length;
      subtitle = state == CommunityState.mixed
          ? '$drivers reportes con resultados distintos en las últimas 24 h.'
          : 'Reportado ${timeAgo(latest!.at, now)}'
                '${drivers > 1 ? ' · $drivers reportes en 24 h' : ''}.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "hace 5 min", "hace 3 h", "hace 2 días".
String timeAgo(DateTime time, DateTime now) {
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  final days = diff.inDays;
  return days == 1 ? 'hace 1 día' : 'hace $days días';
}
