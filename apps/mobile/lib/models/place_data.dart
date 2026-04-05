class PlaceData {
  final String id;
  final String name;
  final String type; // "gym" | "private-gym"
  final double? latitude;
  final double? longitude;
  final String? imageUrl;
  final String? thumbnailUrl;
  final String createdBy;
  final double? distance;

  PlaceData({
    required this.id,
    required this.name,
    required this.type,
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.thumbnailUrl,
    required this.createdBy,
    this.distance,
  });

  factory PlaceData.fromJson(Map<String, dynamic> json) {
    return PlaceData(
      id: json['_id'],
      name: json['name'],
      type: json['type'],
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      imageUrl: json['imageUrl'],
      thumbnailUrl: json['thumbnailUrl'],
      createdBy: json['createdBy'],
      distance: json['distance']?.toDouble(),
    );
  }
}
