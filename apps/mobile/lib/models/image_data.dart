class ImageData {
  final String id;
  final String url;
  final String filename;
  final String userId;
  final DateTime uploadedAt;
  final String? holdPolygonId;

  final String? gymName;
  final String? wallName;
  final DateTime? wallExpirationDate;

  ImageData({
    required this.id,
    required this.url,
    required this.filename,
    required this.userId,
    required this.uploadedAt,
    this.holdPolygonId,
    this.gymName,
    this.wallName,
    this.wallExpirationDate,
  });

  factory ImageData.fromJson(Map<String, dynamic> json) {
    return ImageData(
      id: json['_id'],
      url: json['url'],
      filename: json['filename'],
      userId: json['userId'],
      uploadedAt: DateTime.parse(json['uploadedAt']),
      holdPolygonId: json['holdPolygonId'],
      gymName: json['gymName'],
      wallName: json['wallName'],
      wallExpirationDate: json['wallExpirationDate'] != null ? DateTime.parse(json['wallExpirationDate']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'filename': filename,
        'userId': userId,
        'uploadedAt': uploadedAt.toIso8601String(),
        'holdPolygonId': holdPolygonId,
        'gymName': gymName,
        'wallName': wallName,
        'wallExpirationDate': wallExpirationDate?.toIso8601String(),
      };
}
