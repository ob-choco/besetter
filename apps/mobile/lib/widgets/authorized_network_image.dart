import 'package:flutter/material.dart';
import '../services/http_client.dart';
import 'package:flutter/services.dart' as ui;
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'dart:ui' as ui;
import 'dart:async';
import '../services/image_cache_manager.dart';

class AuthorizedNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit? fit;

  const AuthorizedNetworkImage({
    required this.imageUrl,
    this.fit,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Image(
      image: AuthorizedNetworkImageProvider(imageUrl),
      fit: fit,
    );
  }
}

class AuthorizedNetworkImageProvider extends ImageProvider<AuthorizedNetworkImageProvider> {
  final String imageUrl;

  AuthorizedNetworkImageProvider(this.imageUrl);

  @override
  ImageStreamCompleter loadImage(
    AuthorizedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      informationCollector: () sync* {
        yield ErrorDescription('Image URL: $imageUrl');
      },
    );
  }

  Future<ui.Codec> _loadAsync(
    AuthorizedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    try {
      return await _fetchImage(decode);
    } catch (e) {
      throw Exception('Error loading image: $e');
    }
  }

  Future<ui.Codec> _fetchImage(ImageDecoderCallback decode) async {
    try {
      // 캐시에서 이미지 확인
      final cachedImage = await ImageCacheManager().getImage(imageUrl);
      if (cachedImage != null) {
        final buffer = await ui.ImmutableBuffer.fromUint8List(cachedImage);
        return decode(buffer);
      }

      // 캐시에 없는 경우 다운로드
      final response = await AuthorizedHttpClient.getImage(imageUrl);
      if (response.statusCode != 200) throw Exception('Failed to load image');

      // 다운로드한 이미지를 캐시에 저장
      await ImageCacheManager().cacheImage(imageUrl, response.bodyBytes);
      
      final buffer = await ui.ImmutableBuffer.fromUint8List(response.bodyBytes);
      return decode(buffer);
    } catch (e) {
      throw Exception('Error loading image: $e');
    }
  }

  @override
  Future<AuthorizedNetworkImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<AuthorizedNetworkImageProvider>(this);
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is AuthorizedNetworkImageProvider && other.imageUrl == imageUrl;
  }

  @override
  int get hashCode => imageUrl.hashCode;
}
