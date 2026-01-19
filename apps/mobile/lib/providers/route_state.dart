import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/route_data.dart';
import '../services/http_client.dart';
import '../models/paginated_response.dart';

class RouteProvider extends ChangeNotifier {
  List<RouteData> _routes = [];
  String? _nextToken;
  bool _isLoadingInitial = false;
  bool _isLoadingMore = false;
  String? _error;
  int? _totalCount; // 전체 개수 (선택적)

  List<RouteData> get routes => _routes;
  bool get isLoadingInitial => _isLoadingInitial; // 초기 로딩
  bool get isLoadingMore => _isLoadingMore;   // 추가 로딩
  bool get hasMore => _nextToken != null;       // 더 로드할 데이터가 있는지
  String? get error => _error;
  int? get totalCount => _totalCount;

  RouteProvider() {
    fetchInitialRoutes();
    fetchTotalCount(); // 생성 시 전체 개수도 가져오기
  }

  Future<void> fetchInitialRoutes() async {
    if (_isLoadingInitial) return;
    _isLoadingInitial = true;
    _error = null;
    _routes = []; // 초기화
    _nextToken = null;
    notifyListeners();

    await _fetchRoutes();
    _isLoadingInitial = false;
    notifyListeners();
  }

  Future<void> fetchMoreRoutes() async {
    if (_isLoadingMore || _nextToken == null) return;
    _isLoadingMore = true;
    _error = null;
    notifyListeners();

    await _fetchRoutes();
    _isLoadingMore = false;
    notifyListeners();
  }

  Future<void> _fetchRoutes() async {
    try {
      final queryParams = {
        'sort': 'createdAt:desc',
        'limit': '4', // 기존 limit
        if (_nextToken != null) 'next': _nextToken!,
      };
      final uri = Uri.parse('/routes').replace(queryParameters: queryParams);
      final response = await AuthorizedHttpClient.get(uri.toString());

      if (response.statusCode == 200) {
        final result = PaginatedResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
          (json) => RouteData.fromJson(json),
        );
        if (_nextToken == null) { // 초기 로드인 경우
          _routes = result.data;
        } else { // 추가 로드인 경우
          _routes.addAll(result.data);
        }
        _nextToken = result.nextToken;
      } else {
        _error = 'Failed to load routes. Status code: ${response.statusCode}';
      }
    } catch (e) {
      _error = 'An error occurred while fetching routes: $e';
    }
  }

  Future<void> fetchTotalCount() async {
    // 기존 _fetchTotalCount 로직과 유사하게 구현
    try {
      final response = await AuthorizedHttpClient.get('/routes/count');
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        _totalCount = data['totalCount'];
      }
    } catch (e) {
      debugPrint('RouteProvider: Failed to fetch total count: $e');
      // _error 상태를 업데이트 할 수도 있음
    }
    notifyListeners(); // totalCount 변경 알림
  }

  // 루트 생성/수정/삭제 후 호출될 메소드
  Future<void> refreshRoutesAndCount() async {
    // 모든 관련 데이터를 강제로 새로고침
    await fetchInitialRoutes(); // 루트 목록 새로고침
    await fetchTotalCount();  // 전체 개수 새로고침
    // notifyListeners()는 각 fetch 메소드 내부에서 호출됨
  }

  // 예시: 루트 삭제 함수
  Future<bool> deleteRoute(String routeId) async {
    bool success = false;
    try {
      final response = await AuthorizedHttpClient.delete('/routes/$routeId');
      if (response.statusCode == 204) {
        success = true;
        // 성공 시 루트 목록과 카운트 새로고침
        await refreshRoutesAndCount();
      } else {
        _error = 'Failed to delete route.';
        notifyListeners();
      }
    } catch (e) {
      _error = 'Error deleting route: $e';
      notifyListeners();
    }
    return success;
  }
}
