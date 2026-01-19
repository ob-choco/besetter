class PolygonData {
  final String id;
  final List<Polygon> polygons;
  final String imageId;
  final String imageUrl;
  final String? gymName;
  final String? wallName;
  final DateTime? wallExpirationDate;

  PolygonData({
    required this.id,
    required this.polygons,
    required this.imageId,
    required this.imageUrl,
    this.gymName,
    this.wallName,
    this.wallExpirationDate,
  });

  factory PolygonData.fromJson(Map<String, dynamic> json) {
    return PolygonData(
      id: json['_id'],
      polygons: (json['polygons'] as List)
          .map((p) => Polygon.fromJson(p))
          .toList(),
      imageId: json['imageId'],
      imageUrl: json['imageUrl'],
      gymName: json['gymName'],
      wallName: json['wallName'],
      wallExpirationDate: json['wallExpirationDate'] != null 
          ? DateTime.parse(json['wallExpirationDate'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'polygons': polygons.map((p) => p.toJson()).toList(),
        'imageId': imageId,
        'imageUrl': imageUrl,
        'gymName': gymName,
        'wallName': wallName,
        'wallExpirationDate': wallExpirationDate?.toIso8601String(),
      };
}

class Polygon {
  final int polygonId;
  final List<List<int>> points;
  final String type;
  final double? score;
  final String? feedbackStatus;
  final DateTime? feedbackAt;
  final bool? isDeleted;

  Polygon({
    required this.polygonId,
    required this.points,
    required this.type,
    this.score,
    this.feedbackStatus,
    this.feedbackAt,
    this.isDeleted,
  });

  factory Polygon.fromJson(Map<String, dynamic> json) {
    return Polygon(
      polygonId: json['polygonId'],
      points: (json['points'] as List<dynamic>)
          .map((point) => (point as List<dynamic>).map((xy) => xy as int).toList())
          .toList(),
      type: json['type'],
      score: json['score']?.toDouble(),
      feedbackStatus: json['feedbackStatus'],
      feedbackAt: json['feedbackAt'] != null ? DateTime.parse(json['feedbackAt']) : null,
      isDeleted: json['isDeleted'],
    );
  }

  Map<String, dynamic> toJson() => {
        'polygonId': polygonId,
        'points': points,
        'type': type,
        'score': score,
        'feedbackStatus': feedbackStatus,
        'feedbackAt': feedbackAt?.toIso8601String(),
        'isDeleted': isDeleted,
      };
}
