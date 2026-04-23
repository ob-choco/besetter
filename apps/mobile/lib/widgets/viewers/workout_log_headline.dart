/// Categorizes the workout-log headline copy based on completed vs total
/// attempt counts. Keep this a pure function so it can be unit-tested without
/// Flutter boilerplate; the widget layer maps each variant to localized text.
enum HeadlineVariant {
  /// Only attempts logged, no completions (C == 0, T >= 1).
  attemptsOnly,
  /// Single perfect attempt (C == T == 1).
  firstTry,
  /// Two-in-a-row (C == T == 2).
  secondStreak,
  /// 3–5 consecutive completions with no misses.
  streakSmall,
  /// 6–10 consecutive completions with no misses.
  allCompletedMid,
  /// 11+ consecutive completions with no misses (🔥 variant).
  streakFire,
  /// Any run containing at least one completion and at least one miss.
  mixed,
}

HeadlineVariant selectHeadlineVariant(int completedCount, int totalCount) {
  final c = completedCount < 0 ? 0 : completedCount;
  final t = totalCount < 1 ? 1 : totalCount;
  final clampedC = c > t ? t : c;
  if (clampedC == 0) return HeadlineVariant.attemptsOnly;
  if (clampedC == t) {
    if (clampedC == 1) return HeadlineVariant.firstTry;
    if (clampedC == 2) return HeadlineVariant.secondStreak;
    if (clampedC <= 5) return HeadlineVariant.streakSmall;
    if (clampedC <= 10) return HeadlineVariant.allCompletedMid;
    return HeadlineVariant.streakFire;
  }
  return HeadlineVariant.mixed;
}

/// Human-friendly duration formatter for the workout-log meta row.
///
/// - Under 1 hour: `MM:SS.cs` (matches the per-activity row format).
/// - 1 hour or longer: `Hh MM:SS` (drops centiseconds, which are irrelevant at
///   that scale).
///
/// Fractional seconds truncate (floor), matching the convention in
/// `_formatDuration` inside `workout_log_panel.dart`.
String formatDurationHuman(double seconds) {
  if (seconds < 0) seconds = 0;
  if (seconds >= 3600) {
    final hours = (seconds / 3600).floor();
    final rem = seconds - hours * 3600;
    final minutes = (rem / 60).floor().toString().padLeft(2, '0');
    final secs = (rem % 60).floor().toString().padLeft(2, '0');
    return '${hours}h $minutes:$secs';
  }
  final minutes = (seconds / 60).floor().toString().padLeft(2, '0');
  final secs = (seconds % 60).floor().toString().padLeft(2, '0');
  final cs = ((seconds * 100) % 100).floor().toString().padLeft(2, '0');
  return '$minutes:$secs.$cs';
}
