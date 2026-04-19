import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'start.dart';
import 'login.dart';
import 'pages/home.dart';
import 'pages/main_tab.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'pages/image_list_page.dart';
import 'services/http_client.dart';
import 'services/deep_link_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:upgrader/upgrader.dart';
import 'package:kakao_flutter_sdk_common/kakao_flutter_sdk_common.dart';
import 'providers/auth_provider.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'services/posthog_service.dart';
import 'providers/user_provider.dart';
import 'models/route_data.dart';
import 'pages/viewers/route_viewer.dart';


// 개발 모드에서 스플래시 화면 스킵을 위한 상수
const bool skipSplash = true;

final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

late ProviderContainer container;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await LineSDK.instance.setup('2006504173');

  KakaoSdk.init(
    nativeAppKey: '2368c0bfac918406b9ea6fe8242d70f7',
    javaScriptAppKey: '6c0285165dddccdae02bffe935c47e72',
  );

  final posthogConfig =
      PostHogConfig('phc_wLKorSH6QdipSfGhpBF2cw8xMc6JrUKYY3trjfwzjnJW')
        ..host = 'https://us.i.posthog.com'
        ..captureApplicationLifecycleEvents = true
        ..sessionReplay = true;
  await Posthog().setup(posthogConfig);

  container = ProviderContainer();

  // PostHog identify when we learn the user id from /users/me.
  container.listen<AsyncValue<UserState>>(
    userProfileProvider,
    (prev, next) {
      next.whenData((user) {
        if (prev?.value?.id != user.id) {
          PosthogService.identify(userId: user.id);
        }
      });
    },
    fireImmediately: true,
  );

  // PostHog reset on logout transition.
  container.listen<AsyncValue<AuthState>>(
    authProvider,
    (prev, next) {
      final wasLoggedIn = prev?.value?.isLoggedIn ?? false;
      final isLoggedIn = next.value?.isLoggedIn ?? false;
      if (wasLoggedIn && !isLoggedIn) {
        PosthogService.reset();
      }
    },
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return PostHogWidget(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: AuthorizedHttpClient.navigatorKey,
        title: 'Besetter',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.light,
        initialRoute: skipSplash ? '/' : '/splash',
        routes: {
          '/': (context) => const MainMenuPage(),
          '/splash': (context) => const SplashPage(),
          '/login': (context) => const LoginPage(),
          '/home': (context) => const HomePage(),
          '/images': (context) => const ImageListPage(),
        },
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [routeObserver, PosthogObserver()],
      ),
    );
  }
}

class MainMenuPage extends ConsumerStatefulWidget {
  const MainMenuPage({super.key});

  @override
  ConsumerState<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends ConsumerState<MainMenuPage> {
  @override
  void initState() {
    super.initState();
    // 딥링크 초기화
    DeepLinkService().init(
      onRouteLink: (routeId) {
        _handleRouteLink(routeId);
      },
    );
    // 앱 시작 시 대기 중인 딥링크 처리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingRouteId = DeepLinkService().consumePendingRouteId();
      if (pendingRouteId != null) {
        _handleRouteLink(pendingRouteId);
      }
    });
  }

  void _handleRouteLink(String routeId) {
    final authAsync = ref.read(authProvider);
    authAsync.whenData((authState) {
      if (authState.isLoggedIn) {
        _navigateToRoute(routeId);
      } else {
        // 로그인 필요 - pendingRouteId 저장 후 로그인 화면으로
        DeepLinkService().pendingRouteId = routeId;
        Navigator.of(context).pushNamed('/login');
      }
    });
  }

  Future<void> _navigateToRoute(String routeId) async {
    final response = await AuthorizedHttpClient.get('/routes/$routeId');
    if (!mounted) return;

    if (response.statusCode == 200) {
      final routeData = RouteData.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RouteViewer(routeData: routeData),
        ),
      );
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    if (response.statusCode == 403) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.routePrivateSnack)),
      );
      return;
    }

    if (response.statusCode == 404) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.routeDeletedSnack)),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.routeUnavailableSnack)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authProvider);

    return authAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        body: Center(child: Text('Error: $e')),
      ),
      data: (authState) {
        if (!authState.isInitialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 로그인 완료 후 대기 중인 딥링크 처리
        if (authState.isLoggedIn) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final pendingRouteId = DeepLinkService().consumePendingRouteId();
            if (pendingRouteId != null) {
              _navigateToRoute(pendingRouteId);
            }
          });
        }

        return UpgradeAlert(
          upgrader: Upgrader(
            minAppVersion: '0.0.2',
          ),
          child: authState.isLoggedIn ? const MainTabPage() : const LoginPage(),
        );
      },
    );
  }
}
