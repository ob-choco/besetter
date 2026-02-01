import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import '../pages/terms_page.dart';
import '../services/token_service.dart';
import 'providers/auth_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  static const String _host = 'https://besetter-api-371038003203.asia-northeast3.run.app';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // 로고 또는 앱 이름
              const Text(
                'besetter',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              // 환영 메시지
              Text(
                AppLocalizations.of(context)!.recordAndShareClimbing,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              // 로그인 버튼들
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _handleAppleLogin(context, ref),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: const Image(
                            image: AssetImage('assets/apple/iOS/Logo - SIWA - Logo-only - White.png'),
                            width: 44,
                            height: 44,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _handleGoogleLogin(context, ref),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SvgPicture.asset(
                            'assets/google/Android/svg/light/android_light_sq_na.svg',
                            width: 44,
                            height: 44,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => _handleLineLogin(context, ref),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Image(
                          image: Theme.of(context).platform == TargetPlatform.iOS
                              ? AssetImage('assets/line/images/iOS/44dp/btn_base.png')
                              : AssetImage('assets/line/images/Android/btn_base.png'),
                          width: 44,
                          height: 44,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _handleKakaoLogin(context, ref),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SvgPicture.asset(
                            'assets/kakao/kakaotalk.svg',
                            width: 44,
                            height: 44,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40), // 하단 여백
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAppleLogin(BuildContext context, WidgetRef ref) async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final signInResponse = await http.post(
        Uri.parse('$_host/authentications/sign-in/apple'),
        headers: {
          'Authorization': 'Bearer ${credential.identityToken}',
          'Content-Type': 'application/json',
        },
      );
      if (signInResponse.statusCode == 200) {
        // 로그인 성공
        final data = jsonDecode(signInResponse.body);
        await TokenService.saveTokens(
          accessToken: data['accessToken'],
          refreshToken: data['refreshToken'],
        );

        await ref.read(authProvider.notifier).login(
          '',
          data['accessToken'],
        );

        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      } else if (signInResponse.statusCode == 403) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => TermsPage(
            appleAuthorizationCode: credential.authorizationCode,
          ),
        ));
      } else {
        throw Exception('Failed to sign in');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.loginFailedTryAgain),
        ),
      );
    }
  }

  Future<void> _handleGoogleLogin(BuildContext context, WidgetRef ref) async {
    const List<String> scopes = <String>['email', 'openid', 'profile'];

    GoogleSignIn googleSignIn = GoogleSignIn(
      scopes: scopes,
    );

    try {
      final GoogleSignInAccount? googleSignInAccount = await googleSignIn.signIn();
      if (googleSignInAccount == null) {
        throw Exception('Failed to sign in');
      }

      final GoogleSignInAuthentication googleSignInAuthentication = await googleSignInAccount.authentication;

      final signInResponse = await http.post(
        Uri.parse('$_host/authentications/sign-in/google'),
        headers: {
          'Authorization': 'Bearer ${googleSignInAuthentication.idToken}',
          'Content-Type': 'application/json',
        },
      );
      if (signInResponse.statusCode == 200) {
        // 로그인 성공
        final data = jsonDecode(signInResponse.body);
        await TokenService.saveTokens(
          accessToken: data['accessToken'],
          refreshToken: data['refreshToken'],
        );

        await ref.read(authProvider.notifier).login(
          '',
          data['accessToken'],
        );

        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      } else if (signInResponse.statusCode == 403) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => TermsPage(
            googleIdToken: googleSignInAuthentication.idToken,
          ),
        ));
      } else {
        throw Exception('Failed to sign in');
      }
    } catch (error) {
      print(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.loginFailedTryAgain),
        ),
      );
    }
  }

  Future<void> _handleLineLogin(BuildContext context, WidgetRef ref) async {
    try {
      // LINE 로그인을 위한 nonce 값을 서버에서 가져옴
      final response = await http.post(
        Uri.parse('$_host/authentications/nonces'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'type': 'line'}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get nonce from server');
      }

      final createdNonce = jsonDecode(response.body);

      final loginOption = LoginOption(false, 'normal');
      loginOption.idTokenNonce = createdNonce['nonce'];
      final result = await LineSDK.instance.login(
        scopes: ['profile', 'openid', 'email'],
        option: loginOption,
      );

      // 로그인 시도
      final signInResponse = await http.post(
        Uri.parse('$_host/authentications/sign-in/line'),
        headers: {
          'Authorization': 'Bearer ${result.accessToken.value}',
          'Content-Type': 'application/json',
        },
      );

      if (signInResponse.statusCode == 200) {
        // 로그인 성공
        final data = jsonDecode(signInResponse.body);
        await TokenService.saveTokens(
          accessToken: data['accessToken'],
          refreshToken: data['refreshToken'],
        );

        await ref.read(authProvider.notifier).login(
          result.userProfile?.displayName ?? '',
          data['accessToken'],
        );

        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      } else if (signInResponse.statusCode == 403) {
        // 회원가입 필요
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => TermsPage(
            lineIdToken: result.accessToken.idTokenRaw ?? '',
            nonceId: createdNonce['_id'],
          ),
        ));
      } else {
        throw Exception('Failed to sign in');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.loginFailedTryAgain),
        ),
      );
    }
  }

  Future<void> _handleKakaoLogin(BuildContext context, WidgetRef ref) async {
    if (await isKakaoTalkInstalled()) {
      try {
        final result = await UserApi.instance.loginWithKakaoTalk();
        await _handleKakaoLoginResult(context, ref, result);
      } catch (error) {

        // 사용자가 카카오톡 설치 후 디바이스 권한 요청 화면에서 로그인을 취소한 경우,
        // 의도적인 로그인 취소로 보고 카카오계정으로 로그인 시도 없이 로그인 취소로 처리 (예: 뒤로 가기)
        if (error is PlatformException && error.code == 'CANCELED') {
          return;
        }
        // 카카오톡에 연결된 카카오계정이 없는 경우, 카카오계정으로 로그인
        try {
          final result = await UserApi.instance.loginWithKakaoAccount();
          await _handleKakaoLoginResult(context, ref, result);
        } catch (error) {
        }
      }
    } else {
      try {
        final result = await UserApi.instance.loginWithKakaoAccount();
        await _handleKakaoLoginResult(context, ref, result);
      } catch (error) {
        print('카카오계정으로 로그인 실패 $error');
      }
    }
  }

  Future<void> _handleKakaoLoginResult(BuildContext context, WidgetRef ref, OAuthToken result) async {
    print(result);
    final signInResponse = await http.post(
      Uri.parse('$_host/authentications/sign-in/kakao'),
      headers: {
        'Authorization': 'Bearer ${result.idToken}',
        'Content-Type': 'application/json',
      },
    );
    if (signInResponse.statusCode == 200) {
      // 로그인 성공
      final data = jsonDecode(signInResponse.body);
      await TokenService.saveTokens(
        accessToken: data['accessToken'],
        refreshToken: data['refreshToken'],
      );

      await ref.read(authProvider.notifier).login(
        '',
        data['accessToken'],
      );

      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } else if (signInResponse.statusCode == 403) {
      // 회원가입 필요
      Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => TermsPage(
          kakaoAccessToken: result.accessToken,
        ),
      ));
    } else {
      throw Exception('Failed to sign in');
    }
  }
}
