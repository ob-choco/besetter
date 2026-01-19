import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthState extends ChangeNotifier {
  bool _isLoggedIn = false;
  bool _isInitialized = false;  // 초기화 상태 추적
  String? _userDisplayName;
  String? _accessToken;

  bool get isLoggedIn => _isLoggedIn;
  bool get isInitialized => _isInitialized;
  String? get userDisplayName => _userDisplayName;
  String? get accessToken => _accessToken;

  AuthState() {
    loadAuthState();
  }

  Future<void> loadAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    _userDisplayName = prefs.getString('userDisplayName');
    _accessToken = prefs.getString('accessToken');
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _saveAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', _isLoggedIn);
    await prefs.setString('userDisplayName', _userDisplayName ?? '');
    await prefs.setString('accessToken', _accessToken ?? '');
  }

  Future<void> login(String displayName, String accessToken) async {
    _isLoggedIn = true;
    _userDisplayName = displayName;
    _accessToken = accessToken;
    await _saveAuthState();
    notifyListeners();
  }

  Future<void> logout() async {
    _isLoggedIn = false;
    _userDisplayName = null;
    _accessToken = null;
    await _saveAuthState();
    notifyListeners();
  }
} 