import 'package:shared_preferences/shared_preferences.dart';

/// Servicio para gestionar el estado del onboarding
class OnboardingService {
  // Singleton
  static final OnboardingService _instance = OnboardingService._internal();
  factory OnboardingService() => _instance;
  OnboardingService._internal();

  static const String _hasSeenOnboardingKey = 'has_seen_onboarding';

  bool _hasSeenOnboarding = false;
  bool _isLoaded = false;

  /// Indica si el usuario ya vio el onboarding
  bool get hasSeenOnboarding => _hasSeenOnboarding;

  /// Indica si ya se cargó el estado
  bool get isLoaded => _isLoaded;

  /// Carga el estado del onboarding desde SharedPreferences
  Future<void> loadOnboardingStatus() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _hasSeenOnboarding = prefs.getBool(_hasSeenOnboardingKey) ?? false;
      _isLoaded = true;
    } catch (e) {
      _hasSeenOnboarding = false;
      _isLoaded = true;
    }
  }

  /// Marca el onboarding como completado
  Future<void> completeOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hasSeenOnboardingKey, true);
      _hasSeenOnboarding = true;
    } catch (e) {
      // Error silencioso, el peor caso es que vuelva a ver el onboarding
    }
  }

  /// Reinicia el estado del onboarding (útil para testing)
  Future<void> resetOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_hasSeenOnboardingKey);
      _hasSeenOnboarding = false;
    } catch (e) {
      // Error silencioso
    }
  }
}
