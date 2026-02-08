import 'dart:async';
import 'package:app_links/app_links.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// 딥링크 대기 중인 route ID (로그인 후 처리용)
  String? pendingRouteId;

  /// 딥링크 리스너 초기화
  void init({required Function(String routeId) onRouteLink}) {
    // 앱이 이미 실행 중일 때 딥링크 수신
    _subscription = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri, onRouteLink);
    });

    // 앱이 딥링크로 시작된 경우
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleUri(uri, onRouteLink);
      }
    });
  }

  void _handleUri(Uri uri, Function(String routeId) onRouteLink) {
    // /share/routes/{routeId} 형식 파싱
    final pathSegments = uri.pathSegments;
    if (pathSegments.length >= 3 &&
        pathSegments[0] == 'share' &&
        pathSegments[1] == 'routes') {
      final routeId = pathSegments[2];
      onRouteLink(routeId);
    }
  }

  /// 대기 중인 딥링크 소비
  String? consumePendingRouteId() {
    final routeId = pendingRouteId;
    pendingRouteId = null;
    return routeId;
  }

  void dispose() {
    _subscription?.cancel();
  }
}
