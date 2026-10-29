import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/auth_service.dart';

/// Pantalla de inicio de sesión (opcional) que se muestra al abrir la app.
///
/// Con [onFinished] se usa como paso del arranque; sin él (abierta desde la
/// cuenta) simplemente se cierra al terminar.
class LoginPage extends StatefulWidget {
  final VoidCallback? onFinished;

  const LoginPage({super.key, this.onFinished});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final AuthService _authService = AuthService();
  bool _isSigningIn = false;

  void _finish() {
    if (widget.onFinished != null) {
      widget.onFinished!();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _signIn() async {
    setState(() => _isSigningIn = true);
    try {
      final signedIn = await _authService.signInWithGoogle();
      if (signedIn && mounted) _finish();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _continueWithoutAccount() async {
    await _authService.dismissLoginPrompt();
    if (mounted) _finish();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.ev_station,
                  size: 64,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Crea tu cuenta',
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Es opcional: puedes usar el mapa sin cuenta.',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              const _Benefit(
                icon: Icons.cloud_done_outlined,
                text: 'Guarda tus vehículos en la nube y no los pierdas '
                    'al cambiar de teléfono',
              ),
              const _Benefit(
                icon: Icons.insights_outlined,
                text: 'Ayúdanos a entender qué cargadores necesitan los '
                    'conductores en Colombia',
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSigningIn ? null : _signIn,
                  icon: _isSigningIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.account_circle),
                  label: const Text('Continuar con Google'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isSigningIn ? null : _continueWithoutAccount,
                child: const Text('Continuar sin cuenta'),
              ),
              const SizedBox(height: 24),
              const _LegalNotice(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Benefit({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Aviso de tratamiento de datos (Ley 1581 de 2012) con enlace a la política.
class _LegalNotice extends StatelessWidget {
  const _LegalNotice();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
          height: 1.4,
        );
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          const TextSpan(
            text: 'Al continuar con Google aceptas la ',
          ),
          TextSpan(
            text: 'Política de privacidad',
            style: const TextStyle(
              color: AppColors.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => launchUrl(
                    Uri.parse(AppConstants.privacyPolicyUrl),
                    mode: LaunchMode.externalApplication,
                  ),
          ),
          const TextSpan(
            text: ' y el uso de los datos de tus vehículos con fines '
                'estadísticos. Puedes eliminar tu cuenta y tus datos en '
                'cualquier momento desde "Mi Auto".',
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
