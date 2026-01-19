import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'start.dart';
import 'login.dart';
import 'pages/home.dart';
import 'providers/auth_state.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'pages/image_list_page.dart';
import 'services/http_client.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:upgrader/upgrader.dart';
import 'package:kakao_flutter_sdk_common/kakao_flutter_sdk_common.dart';
import 'providers/image_state.dart' as image_provider;
import 'providers/route_state.dart';


// 개발 모드에서 스플래시 화면 스킵을 위한 상수
const bool skipSplash = true;

final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthState()),
        ChangeNotifierProvider(create: (context) => image_provider.ImageProvider()),
        ChangeNotifierProvider(create: (context) => RouteProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      navigatorObservers: [routeObserver],
    );
  }
}

class MainMenuPage extends StatelessWidget {
  const MainMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();

    // 초기화가 완료될 때까지 로딩 표시
    if (!authState.isInitialized) {
      return const CircularProgressIndicator();
    }

    return UpgradeAlert(child: authState.isLoggedIn ? const HomePage() : const LoginPage());
  }
}
