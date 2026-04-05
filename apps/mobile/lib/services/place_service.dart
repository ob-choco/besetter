import 'dart:convert';
import '../models/place_data.dart';
import 'http_client.dart';

class PlaceService {
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
    final response = await AuthorizedHttpClient.get(uri.toString());

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
    final response = await AuthorizedHttpClient.get(uri.toString());

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((json) => PlaceData.fromJson(json)).toList();
    } else {
      throw Exception('Failed to search places. Status: ${response.statusCode}');
    }
  }

  static Future<PlaceData> createPlace({
    required String name,
    double? latitude,
    double? longitude,
    required String type,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'type': type,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
    final response = await AuthorizedHttpClient.post('/places', body: body);

    if (response.statusCode == 201) {
      return PlaceData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception('Failed to create place. Status: ${response.statusCode}');
    }
  }

  static Future<PlaceData> updatePlace(
    String placeId, {
    String? name,
    double? latitude,
    double? longitude,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
    final response = await AuthorizedHttpClient.put('/places/$placeId', body: body);

    if (response.statusCode == 200) {
      return PlaceData.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception('Failed to update place. Status: ${response.statusCode}');
    }
  }

  static Future<void> createSuggestion({
    required String placeId,
    String? name,
    double? latitude,
    double? longitude,
  }) async {
    final body = <String, dynamic>{
      'placeId': placeId,
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
    final response = await AuthorizedHttpClient.post('/places/suggestions', body: body);

    if (response.statusCode != 201) {
      throw Exception('Failed to create suggestion. Status: ${response.statusCode}');
    }
  }

  static Future<Map<String, String>> uploadImage(
    String placeId,
    String filePath,
  ) async {
    final response = await AuthorizedHttpClient.multipartPost(
      '/places/$placeId/image',
      filePath,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return {
        'imageUrl': data['imageUrl'] as String,
        'thumbnailUrl': data['thumbnailUrl'] as String,
      };
    } else {
      throw Exception('Failed to upload image. Status: ${response.statusCode}');
    }
  }
}
