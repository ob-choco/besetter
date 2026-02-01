import 'dart:convert';
import 'dart:io';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/image_data.dart';
import '../models/paginated_response.dart';
import '../models/polygon_data.dart';
import '../services/http_client.dart';

part 'images_provider.g.dart';

@riverpod
class Images extends _$Images {
  @override
  Future<List<ImageData>> build() async {
    return _fetchImages();
  }

  Future<List<ImageData>> _fetchImages() async {
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
      return result.data;
    } else {
      throw Exception('Failed to load images. Status code: ${response.statusCode}');
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<PolygonData?> createImage(File image) async {
    state = const AsyncLoading();

    try {
      final response = await AuthorizedHttpClient.multipartPost(
        '/hold-polygons',
        image.path,
      );

      if (response.statusCode == 201) {
        final responseBody = jsonDecode(response.body);
        final polygonData = PolygonData.fromJson(responseBody);

        await refresh();
        return polygonData;
      } else {
        throw Exception('Failed to create image. Status: ${response.statusCode}');
      }
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return null;
    }
  }
}
