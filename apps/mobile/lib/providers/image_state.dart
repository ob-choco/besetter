import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/image_data.dart';
import '../services/http_client.dart';
import '../models/paginated_response.dart';
import '../models/polygon_data.dart';
import 'dart:io';

class ImageProvider extends ChangeNotifier {
  List<ImageData>? _images;
  bool _isLoading = false;
  String? _error;

  List<ImageData>? get images => _images;
  bool get isLoading => _isLoading;
  String? get error => _error;

  ImageProvider() {
    fetchImages(); // 생성 시 초기 데이터 로드
  }

  Future<void> fetchImages({bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) return; // 이미 로딩 중이면 중복 호출 방지 (강제 새로고침 제외)

    _isLoading = true;
    _error = null;
    if (forceRefresh) _images = null; // 강제 새로고침 시 기존 데이터 초기화
    notifyListeners(); // 로딩 상태 UI 반영

    try {
      final queryParams = {
        'sort': 'uploadedAt:desc',
        'limit': '9',
      };
      final uri = Uri.parse('/images').replace(queryParameters: queryParams);
      final response = await AuthorizedHttpClient.get(uri.toString());

      if (response.statusCode == 200) {
        final result = PaginatedResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
          (json) => ImageData.fromJson(json),
        );
        _images = result.data;

      } else {
        _error = 'Failed to load images. Status code: ${response.statusCode}';
      }
    } catch (e) {
      _error = 'An error occurred: $e';
    } finally {
      _isLoading = false;
      notifyListeners(); // 최종 상태 UI 반영
    }
  }

  // createImage 함수 (예시)
  // 실제 파일 업로드 로직은 별도의 서비스 계층에서 처리하거나 여기서 직접 구현할 수 있습니다.
  // 이 함수는 API 호출 성공 후 fetchImages(forceRefresh: true)를 호출하여 목록을 갱신합니다.
  Future<PolygonData?> createImage(File image) async {
    _isLoading = true; // 작업 시작을 알림
    _error = null;    // 이전 에러 상태 초기화
    notifyListeners();  // 로딩 시작 UI 반영

    PolygonData? createdPolygonData;

    try {
      final response = await AuthorizedHttpClient.multipartPost(
        '/hold-polygons', // 대상 엔드포인트
        image.path,
      );

      if (response.statusCode == 201) { // 201 Created
        final responseBody = jsonDecode(response.body);
        createdPolygonData = PolygonData.fromJson(responseBody);

        // 이미지 생성 성공 후, 이미지 목록을 강제로 새로고침
        // 이렇게 하면 ImageProvider를 사용하는 모든 UI가 최신 상태를 반영할 수 있음
        await fetchImages(forceRefresh: true);
        // fetchImages 내부에서 _isLoading 상태 변경 및 notifyListeners 호출이 이루어짐
        // 따라서 여기서 _isLoading을 다시 false로 설정할 필요는 fetchImages의 동작에 따라 달라질 수 있으나,
        // createImage 작업 자체의 완료를 명시하기 위해 finally에서 처리

      } else {
        _error = 'Failed to create image. Status: ${response.statusCode}, Body: ${response.body}';
        // notifyListeners()는 finally 블록에서 호출됨
      }
    } catch (e) {
      _error = 'Error creating image: $e';
      // notifyListeners()는 finally 블록에서 호출됨
    } finally {
      // createImage 작업의 로딩 상태를 최종적으로 false로 설정
      // fetchImages가 내부적으로 _isLoading을 false로 설정했더라도,
      // 이 finally 블록은 createImage 액션 자체의 완료를 보장
      _isLoading = false;
      notifyListeners(); // 로딩 종료 및 에러 상태, 또는 fetchImages로 인한 데이터 변경을 UI에 최종적으로 알림
    }

    return createdPolygonData; // 성공 시 PolygonData, 실패 시 null 반환
  }
}
