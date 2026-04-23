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
