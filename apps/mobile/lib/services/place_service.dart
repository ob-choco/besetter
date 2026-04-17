import 'dart:convert';
import 'dart:ui';
import 'package:http/http.dart' as http;
import '../models/place_data.dart';
import 'http_client.dart';

class PlaceNotUsableException implements Exception {
  final String placeId;
  final String placeName;
  final String placeStatus;
  PlaceNotUsableException({
    required this.placeId,
    required this.placeName,
    required this.placeStatus,
  });

  @override
  String toString() =>
      'PlaceNotUsableException(placeId=$placeId, status=$placeStatus)';
}

void maybeThrowPlaceNotUsable(http.Response response) {
  if (response.statusCode != 409) return;
  try {
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final detail = body is Map ? body['detail'] : null;
    if (detail is Map && detail['code'] == 'PLACE_NOT_USABLE') {
      throw PlaceNotUsableException(
        placeId: detail['place_id'] as String? ?? '',
        placeName: detail['place_name'] as String? ?? '',
        placeStatus: detail['place_status'] as String? ?? '',
      );
    }
  } on PlaceNotUsableException {
    rethrow;
  } catch (_) {
    // fall through; non-matching 409 body is handled by callers
  }
}

class PlaceService {
  static Map<String, String> get _langHeader => {
    'Accept-Language': PlatformDispatcher.instance.locale.languageCode,
  };

  static Future<List<PlaceData>> getNearbyPlaces({
    required double latitude,
    required double longitude,
    required double radius,
  }) async {
    final uri = Uri.parse('/places/nearby').replace(queryParameters: {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'radius': radius.toString(),
    });
    final response = await AuthorizedHttpClient.get(uri.toString(), extraHeaders: _langHeader);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((json) => PlaceData.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load nearby places. Status: ${response.statusCode}');
    }
  }

  static Future<List<PlaceData>> instantSearch(String query) async {
    final uri = Uri.parse('/places/instant-search').replace(queryParameters: {
      'query': query,
    });
    final response = await AuthorizedHttpClient.get(uri.toString(), extraHeaders: _langHeader);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((json) => PlaceData.fromJson(json)).toList();
    } else {
      throw Exception('Failed to search places. Status: ${response.statusCode}');
    }
  }

  /// Create a place with optional image. Uses multipart/form-data.
  static Future<PlaceData> createPlace({
    required String name,
    double? latitude,
    double? longitude,
    required String type,
    String? imagePath,
  }) async {
    final fields = <String, String>{
      'name': name,
      'type': type,
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
    };

    final response = await AuthorizedHttpClient.multipartPost(
      '/places',
      imagePath,
      fieldName: 'image',
      fields: fields,
    );

    if (response.statusCode == 201) {
      return PlaceData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception('Failed to create place. Status: ${response.statusCode}');
    }
  }

  static Future<List<PlaceData>> getMyPrivatePlaces() async {
    final response = await AuthorizedHttpClient.get('/places/my-private');

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((e) => PlaceData.fromJson(e)).toList();
    }
    throw Exception(
        'Failed to fetch my private places. Status: ${response.statusCode}');
  }

  static Future<PlaceData> updatePlace(
    String placeId, {
    String? name,
    double? latitude,
    double? longitude,
    String? imagePath,
  }) async {
    final fields = <String, String>{
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
    };
    final response = await AuthorizedHttpClient.multipartRequest(
      '/places/$placeId',
      imagePath,
      fieldName: 'image',
      fields: fields,
      method: 'PUT',
    );

    if (response.statusCode == 200) {
      return PlaceData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    }
    throw Exception('Failed to update place. Status: ${response.statusCode}');
  }

  static Future<void> deletePlace(String placeId) async {
    final response = await AuthorizedHttpClient.delete('/places/$placeId');
    if (response.statusCode != 204) {
      throw Exception('Failed to delete place. Status: ${response.statusCode}');
    }
  }

  static Future<void> createSuggestion({
    required String placeId,
    String? name,
    double? latitude,
    double? longitude,
    String? imagePath,
  }) async {
    final fields = <String, String>{
      'place_id': placeId,
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
    };
    final response = await AuthorizedHttpClient.multipartPost(
      '/places/suggestions',
      imagePath,
      fieldName: 'image',
      fields: fields,
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to create suggestion. Status: ${response.statusCode}');
    }
  }
}
