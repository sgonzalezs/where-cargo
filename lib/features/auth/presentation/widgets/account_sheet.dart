import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/auth_service.dart';
import '../pages/login_page.dart';

/// Hoja inferior con la cuenta del usuario: iniciar o cerrar sesión y
/// eliminar la cuenta.
class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AccountSheet(),
    );
  }

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  final AuthService _authService = AuthService();
  bool _isBusy = false;

  Future<void> _run(Future<void> Function() action, String doneMessage) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _isBusy = true);
    try {
      await action();
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(doneMessage)));
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar tu cuenta?'),
        content: const Text(
          'Se borrarán tu perfil y los vehículos guardados en la nube. '
          'Los datos guardados en este teléfono se conservan. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(_authService.deleteAccount, 'Tu cuenta fue eliminada');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.user;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mi cuenta',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            if (user == null) ...[
              const Text(
                'Inicia sesión para guardar tus vehículos en la nube.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    navigator.pop();
                    navigator.push(
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    );
                  },
                  icon: const Icon(Icons.account_circle),
                  label: const Text('Iniciar sesión con Google'),
                ),
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  foregroundImage: user.photoURL != null
                      ? NetworkImage(user.photoURL!)
                      : null,
                  child: const Icon(Icons.person, color: AppColors.primary),
                ),
                title: Text(user.displayName ?? 'Usuario'),
                subtitle: user.email != null ? Text(user.email!) : null,
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: !_isBusy,
                leading: const Icon(Icons.logout),
                title: const Text('Cerrar sesión'),
                onTap: () => _run(_authService.signOut, 'Sesión cerrada'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: !_isBusy,
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text(
                  'Eliminar cuenta',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: _confirmDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
