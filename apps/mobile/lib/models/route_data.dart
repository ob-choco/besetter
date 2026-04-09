import 'place_data.dart';
import 'polygon_data.dart';

enum RouteType {
  bouldering,
  endurance,
}

enum BoulderingHoldType {
  normal,
  feetOnly,
  starting,
  finishing,
  checkpoint1,
  checkpoint2,
}

enum GripHand {
  left,
  right,
}

class RouteData {
  final String id;
  final RouteType type;

  final String? title;
  final String? description;

  final String imageId;
  final String imageUrl;

  final String holdPolygonId;

  final String gradeType;
  final String grade;
  final int? gradeScore;
  final String? gradeColor;

  final List<BoulderingHold>? boulderingHolds;
  final List<EnduranceHold>? enduranceHolds;

  final DateTime createdAt;
  final DateTime? updatedAt;

  final PlaceData? place;
  final String? wallName;
  final DateTime? wallExpirationDate;

  final String? overlayImageUrl;
  final bool overlayProcessing;

  final List<Polygon>? polygons;

  RouteData({
    required this.id,
    required this.type,
    this.title,
    this.description,
    required this.imageId,
    required this.imageUrl,
    required this.holdPolygonId,
    required this.gradeType,
    required this.grade,
    this.gradeScore,
    this.gradeColor,
    this.boulderingHolds,
    this.enduranceHolds,
    required this.createdAt,
    this.updatedAt,
    this.place,
    this.wallName,
    this.wallExpirationDate,
    this.overlayImageUrl,
    this.overlayProcessing = false,
    this.polygons,
  });

  factory RouteData.fromJson(Map<String, dynamic> json) {
    return RouteData(
      id: json['_id'],
      type: json['type'] == 'bouldering' ? RouteType.bouldering : RouteType.endurance,
      title: json['title'],
      description: json['description'],
      imageId: json['imageId'],
      imageUrl: json['imageUrl'],
      holdPolygonId: json['holdPolygonId'],
      gradeType: json['gradeType'],
      grade: json['grade'],
      gradeScore: json['gradeScore'],
      gradeColor: json['gradeColor'],
      boulderingHolds: json['boulderingHolds'] != null
          ? (json['boulderingHolds'] as List)
              .map((hold) => BoulderingHold.fromJson(hold as Map<String, dynamic>))
              .toList()
          : null,
      enduranceHolds: json['enduranceHolds'] != null
          ? (json['enduranceHolds'] as List)
              .map((hold) => EnduranceHold.fromJson(hold as Map<String, dynamic>))
              .toList()
          : null,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      place: json['place'] != null ? PlaceData.fromJson(json['place']) : null,
      wallName: json['wallName'],
      wallExpirationDate: json['wallExpirationDate'] != null ? DateTime.parse(json['wallExpirationDate']) : null,
      overlayImageUrl: json['overlayImageUrl'],
      overlayProcessing: json['overlayProcessing'] ?? false,
      polygons: json['polygons'] != null
          ? (json['polygons'] as List).map((polygon) => Polygon.fromJson(polygon as Map<String, dynamic>)).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.toString().split('.').last,
        'title': title,
        'description': description,
        'imageId': imageId,
        'imageUrl': imageUrl,
        'holdPolygonId': holdPolygonId,
        'gradeType': gradeType,
        'grade': grade,
        'gradeScore': gradeScore,
        'gradeColor': gradeColor,
        'boulderingHolds': boulderingHolds?.map((hold) => hold.toJson()).toList(),
        'enduranceHolds': enduranceHolds?.map((hold) => hold.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'place': place,
        'wallName': wallName,
        'wallExpirationDate': wallExpirationDate?.toIso8601String(),
        'overlayImageUrl': overlayImageUrl,
        'overlayProcessing': overlayProcessing,
        'polygons': polygons?.map((polygon) => polygon.toJson()).toList(),
      };
}

class BoulderingHold {
  final int polygonId;
  final String type;
  final int? markingCount;
  final int? checkpointScore;

  BoulderingHold({
    required this.polygonId,
    required this.type,
    this.markingCount,
    this.checkpointScore,
  });

  factory BoulderingHold.fromJson(Map<String, dynamic> json) {
    return BoulderingHold(
      polygonId: json['polygonId'],
      type: json['type'],
      markingCount: json['markingCount'],
      checkpointScore: json['checkpointScore'],
    );
  }

  Map<String, dynamic> toJson() => {
        'polygonId': polygonId,
        'type': type,
        'markingCount': markingCount,
        'checkpointScore': checkpointScore,
      };
}

class EnduranceHold {
  final int polygonId;
  final GripHand? gripHand;

  EnduranceHold({
    required this.polygonId,
    this.gripHand,
  });

  factory EnduranceHold.fromJson(Map<String, dynamic> json) {
    return EnduranceHold(
      polygonId: json['polygonId'],
      gripHand: json['gripHand'] != null
          ? GripHand.values.firstWhere((e) => e.toString().split('.').last == json['gripHand'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'polygonId': polygonId,
        'gripHand': gripHand?.toString().split('.').last,
      };
}
