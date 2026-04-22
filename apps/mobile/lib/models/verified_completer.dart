import 'route_data.dart';

class VerifiedCompleter {
  final OwnerInfo user;
  final int verifiedCompletedCount;
  final DateTime lastActivityAt;

  const VerifiedCompleter({
    required this.user,
    required this.verifiedCompletedCount,
    required this.lastActivityAt,
  });

  factory VerifiedCompleter.fromJson(Map<String, dynamic> json) =>
      VerifiedCompleter(
        user: OwnerInfo.fromJson(json['user'] as Map<String, dynamic>),
        verifiedCompletedCount: json['verifiedCompletedCount'] as int,
        lastActivityAt: DateTime.parse(json['lastActivityAt'] as String),
      );
}

class VerifiedCompletersPage {
  final List<VerifiedCompleter> items;
  final String? nextToken;

  const VerifiedCompletersPage({required this.items, required this.nextToken});
}
