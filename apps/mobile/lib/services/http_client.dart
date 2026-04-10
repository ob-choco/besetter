import 'package:http/http.dart' as http;
import 'dart:convert';
import 'token_service.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/auth_provider.dart';
import '../main.dart' show container;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class AuthorizedHttpClient {
  static const String _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://besetter-api-371038003203.asia-northeast3.run.app',
  );

  // 전역 네비게이터 키 추가
  static final navigatorKey = GlobalKey<NavigatorState>();

  // 토큰 리프레시 요청
  static Future<Map<String, dynamic>> _refreshTokens(
      String refreshToken) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/authentications/refresh'),
      headers: {
        'Authorization': 'Bearer $refreshToken',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 401) {
      final context = navigatorKey.currentContext;
      await container.read(authProvider.notifier).logout();
      navigatorKey.currentState
          ?.pushNamedAndRemoveUntil('/', (route) => false);
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.sessionExpiredLogout)),
        );
      }
      throw Exception('Session expired');
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to refresh tokens');
    }

    final data = jsonDecode(response.body);
    await TokenService.saveTokens(
      accessToken: data['accessToken'],
      refreshToken: data['refreshToken'],
    );

    return data;
  }

  // HTTP 요청 실행 (재시도 로직 포함)
  static Future<http.Response> _executeRequest(
    Future<http.Response> Function(String token) request,
  ) async {
    String? accessToken = await TokenService.getAccessToken();

    // 첫 번째 시도
    final response = await request(accessToken ?? '');

    // 401 에러가 아니면 바로 반환
    if (response.statusCode != 401) {
      return response;
    }

    final refreshToken = await TokenService.getRefreshToken();
    if (refreshToken == null) {
      throw Exception('Signing in is required');
    }

    try {
      final refreshData = await _refreshTokens(refreshToken);
      // 새로운 액세스 토큰으로 원래 요청 재시도
      return await request(refreshData['accessToken']);
    } catch (e) {
      // 토큰 갱신 실패 시 로그아웃 처리
      final context = navigatorKey.currentContext;
      await container.read(authProvider.notifier).logout();

      // 메인 화면으로 이동하면서 모든 스택 제거
      navigatorKey.currentState
          ?.pushNamedAndRemoveUntil('/', (route) => false);

      // 스낵바로 알림
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.sessionExpiredLogout)),
        );
      }
      throw Exception('Authentication expired. Please log in again.');
    }
  }

  // GET 요청
  static Future<http.Response> get(String path) async {
    return _executeRequest((token) => http.get(
          Uri.parse('$_baseUrl$path'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ));
  }

  static Future<http.Response> getImage(String url) async {
    return _executeRequest((token) => http.get(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $token',
          },
        ));
  }

  // POST 요청
  static Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _executeRequest((token) => http.post(
          Uri.parse('$_baseUrl$path'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: body != null ? jsonEncode(body) : null,
        ));
  }

  // PUT 요청
  static Future<http.Response> put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _executeRequest((token) => http.put(
          Uri.parse('$_baseUrl$path'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: body != null ? jsonEncode(body) : null,
        ));
  }

  // DELETE 요청
  static Future<http.Response> delete(String path) async {
    return _executeRequest((token) => http.delete(
          Uri.parse('$_baseUrl$path'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ));
  }

  // PATCH 요청
  static Future<http.Response> patch(
    String path, {
    dynamic body,
  }) async {
    return _executeRequest((token) => http.patch(
          Uri.parse('$_baseUrl$path'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: body != null ? jsonEncode(body) : null,
        ));
  }

  // Multipart request (supports POST, PATCH, etc.)
  static Future<http.Response> multipartRequest(
    String path,
    String? filePath, {
    String fieldName = 'file',
    Map<String, String>? fields,
    String method = 'POST',
  }) async {
    return _executeRequest((token) async {
      final request = http.MultipartRequest(
        method,
        Uri.parse('$_baseUrl$path'),
      );

      request.headers['Authorization'] = 'Bearer $token';

      if (filePath != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            fieldName,
            filePath,
            filename: filePath.split('/').last,
          ),
        );
      }

      if (fields != null) {
        request.fields.addAll(fields);
      }

      final streamedResponse = await request.send();
      return await http.Response.fromStream(streamedResponse);
    });
  }

  // Multipart POST 요청
  static Future<http.Response> multipartPost(
    String path,
    String? filePath, {
    String fieldName = 'file',
    Map<String, String>? fields,
  }) async {
    return _executeRequest((token) async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl$path'),
      );

      request.headers['Authorization'] = 'Bearer $token';

      if (filePath != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            fieldName,
            filePath,
            filename: filePath.split('/').last,
          ),
        );
      }

      if (fields != null) {
        request.fields.addAll(fields);
      }

      final streamedResponse = await request.send();
      return await http.Response.fromStream(streamedResponse);
    });
  }
}
