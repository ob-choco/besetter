import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/legal_urls.dart';
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
  bool _isServiceTermsAgreed = false;
  bool _isPrivacyPolicyAgreed = false;
  bool _isLocationTermsAgreed = false;
  bool _isMarketingConsentAgreed = false;

  bool get _canProceed =>
      _isServiceTermsAgreed && _isPrivacyPolicyAgreed && _isLocationTermsAgreed;

  static const String _host = 'https://api.besetter.olivebagel.com';

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
            'marketingPushConsent': _isMarketingConsentAgreed,
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
          body: jsonEncode({
            'marketingPushConsent': _isMarketingConsentAgreed,
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
      } else if (widget.appleAuthorizationCode != null) {
        final response = await http.post(
          Uri.parse('$_host/authentications/sign-up/apple'),
          headers: {
            'Authorization': 'Bearer ${widget.appleAuthorizationCode}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'marketingPushConsent': _isMarketingConsentAgreed,
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
      } else if (widget.googleIdToken != null) {
        final response = await http.post(
          Uri.parse('$_host/authentications/sign-up/google'),
          headers: {
            'Authorization': 'Bearer ${widget.googleIdToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'marketingPushConsent': _isMarketingConsentAgreed,
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
    final termsUrl = legalDocumentUrl(LegalDocument.serviceTerms, locale);
    final privacyPolicyUrl = legalDocumentUrl(LegalDocument.privacyPolicy, locale);
    final locationTermsUrl = legalDocumentUrl(LegalDocument.locationTerms, locale);

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
            CheckboxListTile(
              title: Text(
                AppLocalizations.of(context)!.marketingPushConsentOptional,
              ),
              subtitle: Text(
                AppLocalizations.of(context)!.marketingPushConsentHint,
                style: const TextStyle(fontSize: 12),
              ),
              value: _isMarketingConsentAgreed,
              onChanged: (value) {
                setState(() {
                  _isMarketingConsentAgreed = value ?? false;
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

class WebViewPage extends StatefulWidget {
  final String url;
  final String title;

  const WebViewPage({super.key, required this.url, required this.title});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _errorMessage = null);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _progress = 100);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) return;
            if (mounted) {
              setState(() {
                _errorMessage = '${error.errorCode}: ${error.description}';
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_progress < 100)
            LinearProgressIndicator(value: _progress / 100),
          if (_errorMessage != null)
            Container(
              color: Colors.white,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF595C5D)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _errorMessage = null);
                      _controller.loadRequest(Uri.parse(widget.url));
                    },
                    child: Text(AppLocalizations.of(context)!.retry),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
