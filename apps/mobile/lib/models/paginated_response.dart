class PaginatedResponse<T> {
  final List<T> data;
  final String? nextToken;

  PaginatedResponse({
    required this.data,
    this.nextToken,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    return PaginatedResponse(
      data: (json['data'] as List).map((item) => fromJson(item)).toList(),
      nextToken: json['meta']['nextToken'],
    );
  }
} 