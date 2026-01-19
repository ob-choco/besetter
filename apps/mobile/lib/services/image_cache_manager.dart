import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:typed_data';

class ImageCacheManager {
  static final ImageCacheManager _instance = ImageCacheManager._internal();
  factory ImageCacheManager() => _instance;
  ImageCacheManager._internal();

  final Map<String, Uint8List> _memoryCache = {};
  static const int _maxMemoryCacheSize = 100; // 메모리에 최대 100개 이미지 저장

  String _generateKey(String url) {
    final baseUrl = url.split('?').first;
    return md5.convert(utf8.encode(baseUrl)).toString();
  }

  Future<String> get _cacheDir async {
    final dir = await getTemporaryDirectory();
    final cacheDir = Directory('${dir.path}/image_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir.path;
  }

  Future<Uint8List?> getImage(String url) async {
    final key = _generateKey(url);
    
    // 1. 메모리 캐시 확인
    if (_memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }

    // 2. 디스크 캐시 확인
    try {
      final file = File('${await _cacheDir}/$key');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        _addToMemoryCache(key, bytes);
        return bytes;
      }
    } catch (e) {
      print('Failed to read disk cache: $e');
    }

    return null;
  }

  Future<void> cacheImage(String url, Uint8List bytes) async {
    final key = _generateKey(url);
    
    // 메모리 캐시에 저장
    _addToMemoryCache(key, bytes);

    // 디스크 캐시에 저장
    try {
      final file = File('${await _cacheDir}/$key');
      await file.writeAsBytes(bytes);
    } catch (e) {
      print('Failed to write disk cache: $e');
    }
  }

  void _addToMemoryCache(String key, Uint8List bytes) {
    if (_memoryCache.length >= _maxMemoryCacheSize) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = bytes;
  }

  Future<void> clearCache() async {
    _memoryCache.clear();
    final dir = Directory(await _cacheDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
} 