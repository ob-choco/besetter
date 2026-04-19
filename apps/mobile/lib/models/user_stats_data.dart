class ActivityCounters {
  final int totalCount;
  final int completedCount;
  final int verifiedCompletedCount;

  const ActivityCounters({
    this.totalCount = 0,
    this.completedCount = 0,
    this.verifiedCompletedCount = 0,
  });

  factory ActivityCounters.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ActivityCounters();
    return ActivityCounters(
      totalCount: (json['totalCount'] as int?) ?? 0,
      completedCount: (json['completedCount'] as int?) ?? 0,
      verifiedCompletedCount: (json['verifiedCompletedCount'] as int?) ?? 0,
    );
  }
}

class RoutesCreatedCounters {
  final int totalCount;
  final int boulderingCount;
  final int enduranceCount;

  const RoutesCreatedCounters({
    this.totalCount = 0,
    this.boulderingCount = 0,
    this.enduranceCount = 0,
  });

  factory RoutesCreatedCounters.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RoutesCreatedCounters();
    return RoutesCreatedCounters(
      totalCount: (json['totalCount'] as int?) ?? 0,
      boulderingCount: (json['boulderingCount'] as int?) ?? 0,
      enduranceCount: (json['enduranceCount'] as int?) ?? 0,
    );
  }
}

class UserStatsData {
  final ActivityCounters activity;
  final ActivityCounters distinctRoutes;
  final int distinctDays;
  final ActivityCounters ownRoutesActivity;
  final RoutesCreatedCounters routesCreated;

  const UserStatsData({
    this.activity = const ActivityCounters(),
    this.distinctRoutes = const ActivityCounters(),
    this.distinctDays = 0,
    this.ownRoutesActivity = const ActivityCounters(),
    this.routesCreated = const RoutesCreatedCounters(),
  });

  factory UserStatsData.fromJson(Map<String, dynamic> json) {
    return UserStatsData(
      activity: ActivityCounters.fromJson(json['activity'] as Map<String, dynamic>?),
      distinctRoutes: ActivityCounters.fromJson(json['distinctRoutes'] as Map<String, dynamic>?),
      distinctDays: (json['distinctDays'] as int?) ?? 0,
      ownRoutesActivity: ActivityCounters.fromJson(json['ownRoutesActivity'] as Map<String, dynamic>?),
      routesCreated: RoutesCreatedCounters.fromJson(json['routesCreated'] as Map<String, dynamic>?),
    );
  }
}
