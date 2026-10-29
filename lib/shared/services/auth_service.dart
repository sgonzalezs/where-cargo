import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_data_repository.dart';
import 'vehicle_service.dart';

/// Servicio singleton de autenticación con Google (Firebase Auth).
///
/// El inicio de sesión es opcional: la app funciona sin cuenta y, al iniciar
/// sesión, el perfil y los vehículos se guardan en Firestore.
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _loginPromptDismissedKey = 'login_prompt_dismissed';

  final UserDataRepository _repository = UserDataRepository();
  Future<void>? _googleSignInReady;
  StreamSubscription<User?>? _authSubscription;
  bool _loginPromptDismissed = false;

  User? get user => FirebaseAuth.instance.currentUser;
  bool get isSignedIn => user != null;

  /// El usuario eligió "Continuar sin cuenta" en la pantalla de inicio.
  bool get loginPromptDismissed => _loginPromptDismissed;

  /// Carga el estado guardado y escucha los cambios de sesión.
  Future<void> initialize() async {
    if (_authSubscription != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _loginPromptDismissed = prefs.getBool(_loginPromptDismissedKey) ?? false;
    } catch (_) {
      // Peor caso: se vuelve a ofrecer el inicio de sesión
    }
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((u) {
      VehicleService().attachUser(u?.uid);
      notifyListeners();
    });
  }

  Future<void> dismissLoginPrompt() async {
    _loginPromptDismissed = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_loginPromptDismissedKey, true);
    } catch (_) {}
  }

  /// Inicia sesión con Google. Devuelve `false` si el usuario canceló.
  ///
  /// Lanza [AuthException] con un mensaje para mostrar si algo falla.
  Future<bool> signInWithGoogle() async {
    try {
      // El client ID se toma de google-services.json (default_web_client_id)
      await (_googleSignInReady ??= GoogleSignIn.instance.initialize());
      final account = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      final result =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = result.user;
      if (user != null) {
        // Al iniciar sesión se aceptan la política de privacidad y el uso
        // estadístico de los datos (texto de la pantalla de inicio).
        try {
          await _repository.upsertUser(user, statsConsent: true);
        } catch (e) {
          debugPrint('[WhereCargo] Error guardando perfil: $e');
        }
      }
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return false;
      }
      debugPrint('[WhereCargo] Google Sign-In: ${e.code} ${e.description}');
      throw const AuthException('No se pudo iniciar sesión con Google');
    } on FirebaseAuthException catch (e) {
      debugPrint('[WhereCargo] Firebase Auth: ${e.code} ${e.message}');
      throw AuthException(e.code == 'network-request-failed'
          ? 'Sin conexión a internet'
          : 'No se pudo iniciar sesión');
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  /// Elimina la cuenta y todos sus datos en Firestore (requisito de Google
  /// Play para apps con cuentas). Los datos locales del teléfono se conservan.
  Future<void> deleteAccount() async {
    final current = user;
    if (current == null) return;
    try {
      // Firebase exige una sesión reciente para eliminar la cuenta: se
      // confirma con Google antes de borrar nada.
      await (_googleSignInReady ??= GoogleSignIn.instance.initialize());
      final account = await GoogleSignIn.instance.authenticate();
      await current.reauthenticateWithCredential(
        GoogleAuthProvider.credential(idToken: account.authentication.idToken),
      );
      await _repository.deleteUserData(current.uid);
      await current.delete();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw const AuthException('Eliminación cancelada');
      }
      throw const AuthException('No se pudo confirmar tu cuenta de Google');
    } on FirebaseException catch (e) {
      debugPrint('[WhereCargo] Eliminar cuenta: ${e.code} ${e.message}');
      throw const AuthException('No se pudo eliminar la cuenta');
    }
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {}
  }
}

/// Error de autenticación con un mensaje listo para mostrar al usuario.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
