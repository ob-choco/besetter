import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/token_service.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

class TermsPage extends ConsumerStatefulWidget {
  final String? lineIdToken;
  final String? appleAuthorizationCode;
  final String? googleIdToken;
  final String? kakaoAccessToken;
  final String? nonceId;

  const TermsPage(
      {super.key,
      this.lineIdToken,
      this.appleAuthorizationCode,
      this.googleIdToken,
      this.kakaoAccessToken,
      this.nonceId});

  @override
  ConsumerState<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends ConsumerState<TermsPage> {
  final Map<String, String> _terms = {
    'ko': 'https://truth-crafter-0c7.notion.site/1f2ad66660f1809ca756d8425c829e9a',
    'en': 'https://truth-crafter-0c7.notion.site/Terms-of-Use-1f2ad66660f18048b71eff109b16a3e0',
    'es': 'https://truth-crafter-0c7.notion.site/T-rminos-y-Condiciones-de-Uso-1f2ad66660f1803d817dc40d21386327',
    'ja': 'https://truth-crafter-0c7.notion.site/1f2ad66660f18036ba13d9c3947aa831',
  };
  final Map<String, String> _privacyPolicy = {
    'ko': 'https://truth-crafter-0c7.notion.site/1abad66660f1800ca144d8645ac8fc75',
    'en': 'https://truth-crafter-0c7.notion.site/Privacy-Policy-1f2ad66660f1808c9760d7b00c5d366f',
    'es': 'https://truth-crafter-0c7.notion.site/Pol-tica-de-Privacidad-1f2ad66660f181fd9d87cb068b896248',
    'ja': 'https://truth-crafter-0c7.notion.site/1f2ad66660f18161815ec804daaf4992',
  };
  final Map<String, String> _locationTerms = {
    'ko': 'https://truth-crafter-0c7.notion.site/348ad66660f1812a8c56dd8b3bbb5da8',
    'en': 'https://truth-crafter-0c7.notion.site/Location-Based-Services-Terms-of-Use-English-348ad66660f1818baab2e0c5bd7ad8dc',
    'es': 'https://truth-crafter-0c7.notion.site/T-rminos-de-uso-del-Servicio-Basado-en-Ubicaci-n-Espa-ol-348ad66660f181dab567e03c8978e2d4',
    'ja': 'https://truth-crafter-0c7.notion.site/348ad66660f18164b92ff73578a93362',
  };
  bool _isServiceTermsAgreed = false;
  bool _isPrivacyPolicyAgreed = false;
  bool _isLocationTermsAgreed = false;

  bool get _canProceed =>
      _isServiceTermsAgreed && _isPrivacyPolicyAgreed && _isLocationTermsAgreed;

  static const String _host = 'https://besetter-api-371038003203.asia-northeast3.run.app';

  Future<void> _handleSignUp() async {
    try {
      if (widget.lineIdToken != null) {
        final response = await http.post(
          Uri.parse('$_host/authentications/sign-up/line'),
          headers: {
            'Authorization': 'Bearer ${widget.lineIdToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'nonceId': widget.nonceId,
          }),
        );

        if (response.statusCode == 201) {
          final data = jsonDecode(response.body);

          await TokenService.saveTokens(
            accessToken: data['accessToken'],
            refreshToken: data['refreshToken'],
          );
          await ref.read(authProvider.notifier).login(
            '',
            data['accessToken'],
          );

          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
          }
        } else {
          throw Exception('Failed to sign up');
        }
      } else if (widget.kakaoAccessToken != null) {
        final response = await http.post(
          Uri.parse('$_host/authentications/sign-up/kakao'),
          headers: {
            'Authorization': 'Bearer ${widget.kakaoAccessToken}',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 201) {
          final data = jsonDecode(response.body);

          await TokenService.saveTokens(
            accessToken: data['accessToken'],
            refreshToken: data['refreshToken'],
          );
          await ref.read(authProvider.notifier).login(
            '',
            data['accessToken'],
          );

          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
          }
        } else {
          throw Exception('Failed to sign up');
        }
      } else if (widget.appleAuthorizationCode != null) {
        final response = await http.post(
          Uri.parse('$_host/authentications/sign-up/apple'),
          headers: {
            'Authorization': 'Bearer ${widget.appleAuthorizationCode}',
            'Content-Type': 'application/json',
          },
        );
        if (response.statusCode == 201) {
          final data = jsonDecode(response.body);

          await TokenService.saveTokens(
            accessToken: data['accessToken'],
            refreshToken: data['refreshToken'],
          );
          await ref.read(authProvider.notifier).login(
            '',
            data['accessToken'],
          );

          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
          }
        } else {
          throw Exception('Failed to sign up');
        }
      } else if (widget.googleIdToken != null) {
        final response = await http.post(
          Uri.parse('$_host/authentications/sign-up/google'),
          headers: {
            'Authorization': 'Bearer ${widget.googleIdToken}',
            'Content-Type': 'application/json',
          },
        );
        if (response.statusCode == 201) {
          final data = jsonDecode(response.body);

          await TokenService.saveTokens(
            accessToken: data['accessToken'],
            refreshToken: data['refreshToken'],
          );
          await ref.read(authProvider.notifier).login(
            '',
            data['accessToken'],
          );

          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
          }
        } else {
          throw Exception('Failed to sign up');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.signupError)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final termsUrl = _terms[locale] ?? _terms['en']!;
    final privacyPolicyUrl = _privacyPolicy[locale] ?? _privacyPolicy['en']!;
    final locationTermsUrl = _locationTerms[locale] ?? _locationTerms['en']!;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.agreeToTerms),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppLocalizations.of(context)!.agreeToTermsForService,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            CheckboxListTile(
              title: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WebViewPage(url: termsUrl, title: AppLocalizations.of(context)!.agreeToServiceTermsRequired),
                    ),
                  );
                  setState(() {
                    _isServiceTermsAgreed = true;
                  });
                },
                child: Text(
                  AppLocalizations.of(context)!.agreeToServiceTermsRequired,
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              value: _isServiceTermsAgreed,
              onChanged: (value) {
                setState(() {
                  _isServiceTermsAgreed = value ?? false;
                });
              },
            ),
            CheckboxListTile(
              title: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WebViewPage(url: privacyPolicyUrl, title: AppLocalizations.of(context)!.agreeToPrivacyPolicyRequired),
                    ),
                  );
                  setState(() {
                    _isPrivacyPolicyAgreed = true;
                  });
                },
                child: Text(
                  AppLocalizations.of(context)!.agreeToPrivacyPolicyRequired,
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              value: _isPrivacyPolicyAgreed,
              onChanged: (value) {
                setState(() {
                  _isPrivacyPolicyAgreed = value ?? false;
                });
              },
            ),
            CheckboxListTile(
              title: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WebViewPage(url: locationTermsUrl, title: AppLocalizations.of(context)!.agreeToLocationTermsRequired),
                    ),
                  );
                  setState(() {
                    _isLocationTermsAgreed = true;
                  });
                },
                child: Text(
                  AppLocalizations.of(context)!.agreeToLocationTermsRequired,
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              value: _isLocationTermsAgreed,
              onChanged: (value) {
                setState(() {
                  _isLocationTermsAgreed = value ?? false;
                });
              },
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _canProceed ? _handleSignUp : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(AppLocalizations.of(context)!.agreeAndStart),
            ),
          ],
        ),
      ),
    );
  }
}

class WebViewPage extends StatelessWidget {
  final String url;
  final String title;

  const WebViewPage({super.key, required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}
