import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/push_service.dart';

part 'auth_provider.g.dart';

class AuthState {
  final bool isLoggedIn;
  final bool isInitialized;
  final String? userDisplayName;
  final String? accessToken;

  const AuthState({
    this.isLoggedIn = false,
    this.isInitialized = false,
    this.userDisplayName,
    this.accessToken,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    bool? isInitialized,
    String? userDisplayName,
    String? accessToken,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isInitialized: isInitialized ?? this.isInitialized,
      userDisplayName: userDisplayName ?? this.userDisplayName,
      accessToken: accessToken ?? this.accessToken,
    );
  }
}

@Riverpod(keepAlive: true)
class Auth extends _$Auth {
  @override
  Future<AuthState> build() async {
    return _loadAuthState();
  }

  Future<AuthState> _loadAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    return AuthState(
      isLoggedIn: prefs.getBool('isLoggedIn') ?? false,
      isInitialized: true,
      userDisplayName: prefs.getString('userDisplayName'),
      accessToken: prefs.getString('accessToken'),
    );
  }

  Future<void> _saveAuthState(AuthState authState) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', authState.isLoggedIn);
    await prefs.setString('userDisplayName', authState.userDisplayName ?? '');
    await prefs.setString('accessToken', authState.accessToken ?? '');
  }

  Future<void> login(String displayName, String accessToken) async {
    final newState = AuthState(
      isLoggedIn: true,
      isInitialized: true,
      userDisplayName: displayName,
      accessToken: accessToken,
    );
    await _saveAuthState(newState);
    state = AsyncData(newState);
    await PushService.registerWithServer();
  }

  Future<void> logout() async {
    await PushService.unregisterFromServer();
    final newState = const AuthState(
      isLoggedIn: false,
      isInitialized: true,
      userDisplayName: null,
      accessToken: null,
    );
    await _saveAuthState(newState);
    state = AsyncData(newState);
  }
}
