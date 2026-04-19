import 'place_data.dart';

class ImageData {
  final String id;
  final String url;
  final String filename;
  final String userId;
  final DateTime uploadedAt;
  final String? holdPolygonId;

  final PlaceData? place;
  final String? wallName;
  final DateTime? wallExpirationDate;
  final int routeCount;

  ImageData({
    required this.id,
    required this.url,
    required this.filename,
    required this.userId,
    required this.uploadedAt,
    this.holdPolygonId,
    this.place,
    this.wallName,
    this.wallExpirationDate,
    this.routeCount = 0,
  });

  factory ImageData.fromJson(Map<String, dynamic> json) {
    return ImageData(
      id: json['_id'],
      url: json['url'],
      filename: json['filename'],
      userId: json['userId'],
      uploadedAt: DateTime.parse(json['uploadedAt']),
      holdPolygonId: json['holdPolygonId'],
      place: json['place'] != null ? PlaceData.fromJson(json['place']) : null,
      wallName: json['wallName'],
      wallExpirationDate: json['wallExpirationDate'] != null ? DateTime.parse(json['wallExpirationDate']) : null,
      routeCount: (json['routeCount'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'filename': filename,
        'userId': userId,
        'uploadedAt': uploadedAt.toIso8601String(),
        'holdPolygonId': holdPolygonId,
        'place': place,
        'wallName': wallName,
        'wallExpirationDate': wallExpirationDate?.toIso8601String(),
        'routeCount': routeCount,
      };
}
