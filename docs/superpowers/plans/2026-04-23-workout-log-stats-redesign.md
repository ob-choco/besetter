# Workout Log Stats Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 3-tile stats row in `WorkoutLogPanel` with a narrative headline + meta block that always shows both 완등 and 시도 figures, with varied celebratory copy for 1–10 perfect streaks and a 🔥 variant for 11+.

**Architecture:** Extract the pure headline-variant selector and the duration formatter into a standalone helper file so they can be unit-tested without Flutter widget boilerplate. Add seven new localized strings across the four ARB files. Rewrite the private `_buildStatsRow` inside `workout_log_panel.dart` as `_buildHeadlineBlock`, removing the `_statTile` helper and the dependency on `_completedOnly` in the stats path. The existing optimistic-update machinery (`addActivity`, `_deleteActivity`) is untouched.

**Tech Stack:** Flutter 3 with `flutter_gen` ARB localization; `flutter_test` for unit tests; no Riverpod changes.

**Spec:** `docs/superpowers/specs/2026-04-23-workout-log-stats-redesign-design.md`

---

## File Structure

### Create
- `apps/mobile/lib/widgets/viewers/workout_log_headline.dart` — pure helper: `HeadlineVariant` enum, `selectHeadlineVariant(int c, int t)`, `formatDurationHuman(double seconds)`.
- `apps/mobile/test/widgets/viewers/workout_log_headline_test.dart` — unit tests for the two pure functions above.

### Modify
- `apps/mobile/lib/l10n/app_ko.arb` — add 8 keys (see Task 1).
- `apps/mobile/lib/l10n/app_en.arb` — add 8 keys.
- `apps/mobile/lib/l10n/app_ja.arb` — add 8 keys.
- `apps/mobile/lib/l10n/app_es.arb` — add 8 keys.
- `apps/mobile/lib/widgets/viewers/workout_log_panel.dart` — delete `_buildStatsRow` and `_statTile` (lines 358–433); add `_buildHeadlineBlock` plus small meta helpers; swap the call inside `build()`.

---

## Phase 1 — Localization

### Task 1: Add new l10n keys to all four ARB files

**Files:**
- Modify: `apps/mobile/lib/l10n/app_ko.arb`
- Modify: `apps/mobile/lib/l10n/app_en.arb`
- Modify: `apps/mobile/lib/l10n/app_ja.arb`
- Modify: `apps/mobile/lib/l10n/app_es.arb`

We add 8 keys: 7 headline variants + 1 meta-row label (`workoutLogMetaTotal`, meaning "누적/Cumulative"). The existing `workoutLogStatAvg` is reused for the 평균 label. The existing `workoutLogStatTotal` (which says "총 시간/Total") stays untouched — it's a different concept from the new "누적" and is left in place as an unused legacy key.

- [ ] **Step 1: Append new keys to `app_ko.arb`**

Insert immediately **after** the existing `"workoutLogStatTotal"` entry (around line 256). The trailing comma on the previous line may need to be added if you paste before another key.

Locate in `apps/mobile/lib/l10n/app_ko.arb`:

```json
  "workoutLogStatTotal": "총 시간",
```

Replace with:

```json
  "workoutLogStatTotal": "총 시간",
  "workoutLogHeadlineAttemptsOnly": "{count}번 시도",
  "@workoutLogHeadlineAttemptsOnly": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineFirstTry": "1번 만에 완등!",
  "workoutLogHeadlineSecondStreak": "2번째도 완등!",
  "workoutLogHeadlineStreakSmall": "{count}번 연속 완등!",
  "@workoutLogHeadlineStreakSmall": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineAllCompletedMid": "{count}번 전부 완등!",
  "@workoutLogHeadlineAllCompletedMid": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineStreakFire": "{count}번 연속 완등 🔥",
  "@workoutLogHeadlineStreakFire": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineMixedLine1": "{count}번 시도 중",
  "@workoutLogHeadlineMixedLine1": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineMixedLine2": "{count}번 완등",
  "@workoutLogHeadlineMixedLine2": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogMetaTotal": "누적",
```

- [ ] **Step 2: Append the same 8 keys to `app_en.arb`** (after `"workoutLogStatTotal": "Total",`)

```json
  "workoutLogStatTotal": "Total",
  "workoutLogHeadlineAttemptsOnly": "{count} attempts",
  "@workoutLogHeadlineAttemptsOnly": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineFirstTry": "Sent on the first try!",
  "workoutLogHeadlineSecondStreak": "Second send in a row!",
  "workoutLogHeadlineStreakSmall": "{count} sends in a row!",
  "@workoutLogHeadlineStreakSmall": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineAllCompletedMid": "{count} sends, no misses!",
  "@workoutLogHeadlineAllCompletedMid": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineStreakFire": "{count} sends in a row 🔥",
  "@workoutLogHeadlineStreakFire": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineMixedLine1": "{count} attempts,",
  "@workoutLogHeadlineMixedLine1": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineMixedLine2": "{count} sends",
  "@workoutLogHeadlineMixedLine2": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogMetaTotal": "Cumulative",
```

- [ ] **Step 3: Append the same 8 keys to `app_ja.arb`** (after `"workoutLogStatTotal": "合計",`)

```json
  "workoutLogStatTotal": "合計",
  "workoutLogHeadlineAttemptsOnly": "{count}回トライ",
  "@workoutLogHeadlineAttemptsOnly": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineFirstTry": "1回目で完登！",
  "workoutLogHeadlineSecondStreak": "2回目も完登！",
  "workoutLogHeadlineStreakSmall": "{count}連続完登！",
  "@workoutLogHeadlineStreakSmall": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineAllCompletedMid": "{count}回すべて完登！",
  "@workoutLogHeadlineAllCompletedMid": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineStreakFire": "{count}連続完登 🔥",
  "@workoutLogHeadlineStreakFire": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineMixedLine1": "{count}回トライ中",
  "@workoutLogHeadlineMixedLine1": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineMixedLine2": "{count}回完登",
  "@workoutLogHeadlineMixedLine2": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogMetaTotal": "累計",
```

- [ ] **Step 4: Append the same 8 keys to `app_es.arb`** (after `"workoutLogStatTotal": "Total",`)

```json
  "workoutLogStatTotal": "Total",
  "workoutLogHeadlineAttemptsOnly": "{count} intentos",
  "@workoutLogHeadlineAttemptsOnly": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineFirstTry": "¡Encadenada al primer intento!",
  "workoutLogHeadlineSecondStreak": "¡Encadenada otra vez!",
  "workoutLogHeadlineStreakSmall": "¡{count} encadenadas seguidas!",
  "@workoutLogHeadlineStreakSmall": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineAllCompletedMid": "¡{count} encadenadas, sin fallos!",
  "@workoutLogHeadlineAllCompletedMid": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineStreakFire": "{count} encadenadas seguidas 🔥",
  "@workoutLogHeadlineStreakFire": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineMixedLine1": "{count} intentos,",
  "@workoutLogHeadlineMixedLine1": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogHeadlineMixedLine2": "{count} encadenadas",
  "@workoutLogHeadlineMixedLine2": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "workoutLogMetaTotal": "Acumulado",
```

- [ ] **Step 5: Regenerate Flutter localizations**

Run from repo root:

```bash
cd apps/mobile && flutter gen-l10n
```

Expected: no output, exit code 0. If this fails, re-check JSON validity of the ARB edits (trailing commas, matching braces).

- [ ] **Step 6: Verify analyzer is clean**

Run:

```bash
cd apps/mobile && flutter analyze
```

Expected: "No issues found!" (or only pre-existing unrelated warnings — nothing new about missing l10n getters).

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/l10n/app_ko.arb apps/mobile/lib/l10n/app_en.arb apps/mobile/lib/l10n/app_ja.arb apps/mobile/lib/l10n/app_es.arb
git commit -m "feat(mobile): add workout log headline l10n strings

Adds 7 headline-variant keys and the workoutLogMetaTotal (누적) label
to all four ARB files for the workout log redesign. Existing stat keys
are left untouched."
```

---

## Phase 2 — Pure Helpers (TDD)

### Task 2: Define `HeadlineVariant` enum and `selectHeadlineVariant`

**Files:**
- Create: `apps/mobile/lib/widgets/viewers/workout_log_headline.dart`
- Test: `apps/mobile/test/widgets/viewers/workout_log_headline_test.dart`

The selector is a pure function of two integers — no Flutter, no l10n. Tests cover the full state table from the spec.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/widgets/viewers/workout_log_headline_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:besetter/widgets/viewers/workout_log_headline.dart';

void main() {
  group('selectHeadlineVariant', () {
    test('completed=0 with attempts => attemptsOnly', () {
      expect(selectHeadlineVariant(0, 1), HeadlineVariant.attemptsOnly);
      expect(selectHeadlineVariant(0, 5), HeadlineVariant.attemptsOnly);
    });

    test('completed==total==1 => firstTry', () {
      expect(selectHeadlineVariant(1, 1), HeadlineVariant.firstTry);
    });

    test('completed==total==2 => secondStreak', () {
      expect(selectHeadlineVariant(2, 2), HeadlineVariant.secondStreak);
    });

    test('completed==total in 3..5 => streakSmall', () {
      expect(selectHeadlineVariant(3, 3), HeadlineVariant.streakSmall);
      expect(selectHeadlineVariant(4, 4), HeadlineVariant.streakSmall);
      expect(selectHeadlineVariant(5, 5), HeadlineVariant.streakSmall);
    });

    test('completed==total in 6..10 => allCompletedMid', () {
      expect(selectHeadlineVariant(6, 6), HeadlineVariant.allCompletedMid);
      expect(selectHeadlineVariant(10, 10), HeadlineVariant.allCompletedMid);
    });

    test('completed==total >= 11 => streakFire', () {
      expect(selectHeadlineVariant(11, 11), HeadlineVariant.streakFire);
      expect(selectHeadlineVariant(50, 50), HeadlineVariant.streakFire);
    });

    test('0 < completed < total => mixed', () {
      expect(selectHeadlineVariant(1, 2), HeadlineVariant.mixed);
      expect(selectHeadlineVariant(12, 20), HeadlineVariant.mixed);
      expect(selectHeadlineVariant(99, 100), HeadlineVariant.mixed);
    });

    test('defensive clamp: completed > total => treated as all-completed', () {
      // Per spec: clamp C = min(C, T) before classifying. That means (5, 3) becomes (3, 3).
      expect(selectHeadlineVariant(5, 3), HeadlineVariant.streakSmall);
    });
  });
}
```

The package name `besetter` matches `apps/mobile/pubspec.yaml`.

- [ ] **Step 2: Run the test and verify it fails**

```bash
cd apps/mobile && flutter test test/widgets/viewers/workout_log_headline_test.dart
```

Expected: compile error, because `workout_log_headline.dart` doesn't exist yet.

- [ ] **Step 3: Create the helper file with the enum and function**

Create `apps/mobile/lib/widgets/viewers/workout_log_headline.dart`:

```dart
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
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
cd apps/mobile && flutter test test/widgets/viewers/workout_log_headline_test.dart
```

Expected: all 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/workout_log_headline.dart apps/mobile/test/widgets/viewers/workout_log_headline_test.dart
git commit -m "feat(mobile): add workout log headline variant selector

Pure function that maps (completedCount, totalCount) to one of 7
HeadlineVariant values per spec. Defensive clamp when C > T."
```

---

### Task 3: Add `formatDurationHuman`

**Files:**
- Modify: `apps/mobile/lib/widgets/viewers/workout_log_headline.dart`
- Modify: `apps/mobile/test/widgets/viewers/workout_log_headline_test.dart`

The existing `_formatDuration` in `workout_log_panel.dart` always returns `MM:SS.cs`. For cumulative durations that can exceed an hour, we want `Hh MM:SS` (e.g., `1h 32:45`). We add a second formatter for the new meta row — per-activity rows keep the old formatter, since each activity is short.

- [ ] **Step 1: Write the failing test** — append this `group` to the existing test file `apps/mobile/test/widgets/viewers/workout_log_headline_test.dart`:

```dart
  group('formatDurationHuman', () {
    test('under one hour shows MM:SS.cs', () {
      expect(formatDurationHuman(0), '00:00.00');
      expect(formatDurationHuman(4 * 60 + 1), '04:01.00');
      expect(formatDurationHuman(48 * 60 + 20), '48:20.00');
      expect(formatDurationHuman(3599.99), '59:59.99');
    });

    test('one hour or more shows Hh MM:SS', () {
      expect(formatDurationHuman(3600), '1h 00:00');
      expect(formatDurationHuman(1 * 3600 + 32 * 60 + 45), '1h 32:45');
      expect(formatDurationHuman(2 * 3600 + 0 * 60 + 5), '2h 00:05');
      expect(formatDurationHuman(10 * 3600 + 59 * 60 + 59), '10h 59:59');
    });

    test('fractional seconds truncate (not round) in MM:SS.cs mode', () {
      // Current _formatDuration uses floor() for cs, matching the activity-row style.
      expect(formatDurationHuman(1.999), '00:01.99');
    });
  });
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
cd apps/mobile && flutter test test/widgets/viewers/workout_log_headline_test.dart
```

Expected: compile error — `formatDurationHuman` not defined.

- [ ] **Step 3: Implement `formatDurationHuman`** — append to `apps/mobile/lib/widgets/viewers/workout_log_headline.dart`:

```dart
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
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
cd apps/mobile && flutter test test/widgets/viewers/workout_log_headline_test.dart
```

Expected: all tests pass (existing 8 + new 3 groups).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/workout_log_headline.dart apps/mobile/test/widgets/viewers/workout_log_headline_test.dart
git commit -m "feat(mobile): add formatDurationHuman helper

Renders MM:SS.cs under 1 hour and Hh MM:SS at/above 1 hour, for the
workout log meta row. Per-activity rows keep the MM:SS.cs-only
formatter since each session is short by nature."
```

---

## Phase 3 — Widget Integration

### Task 4: Replace `_buildStatsRow` with `_buildHeadlineBlock`

**Files:**
- Modify: `apps/mobile/lib/widgets/viewers/workout_log_panel.dart`

This is the main user-facing change. We:

1. Import the new helper.
2. Replace the `_buildStatsRow(l10n)` call inside `build()` with `_buildHeadlineBlock(l10n)`.
3. Delete `_buildStatsRow` and `_statTile` (the three-tile helpers).
4. Add `_buildHeadlineBlock`, `_buildHeadline`, and `_buildMetaRow` as new methods.

After this change, `_completedOnly` is only read inside `_loadActivities` / `_loadMoreActivities` — confirming the spec's scope-narrowing goal.

- [ ] **Step 1: Add the helper import**

In `apps/mobile/lib/widgets/viewers/workout_log_panel.dart`, find the existing imports block (lines 1–8):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/activity_refresh_provider.dart';
import '../../services/activity_service.dart';
import 'section_header.dart';
```

Replace with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/activity_refresh_provider.dart';
import '../../services/activity_service.dart';
import 'section_header.dart';
import 'workout_log_headline.dart';
```

- [ ] **Step 2: Swap the call in `build()`**

Find this line in `build()` (approximately line 333):

```dart
        _buildStatsRow(l10n),
```

Replace with:

```dart
        _buildHeadlineBlock(l10n),
```

- [ ] **Step 3: Delete `_buildStatsRow` and `_statTile`**

Remove the methods `_buildStatsRow` (around lines 358–399) and `_statTile` (around lines 401–433) entirely.

- [ ] **Step 4: Add `_buildHeadlineBlock` and its helpers**

Insert the following methods in the same position the deleted methods occupied (still inside `_WorkoutLogPanelState`):

```dart
  Widget _buildHeadlineBlock(AppLocalizations l10n) {
    final completed = _stats == null ? 0 : (_stats!['completedCount'] as num).toInt();
    final total = _stats == null ? 0 : (_stats!['totalCount'] as num).toInt();
    final completedDuration = _stats == null ? 0.0 : (_stats!['completedDuration'] as num).toDouble();
    final totalDuration = _stats == null ? 0.0 : (_stats!['totalDuration'] as num).toDouble();
    final variant = selectHeadlineVariant(completed, total);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 2, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeadline(variant, completed, total, l10n),
          const SizedBox(height: 10),
          Container(height: 1, color: const Color(0xFFEFF1F2)),
          const SizedBox(height: 10),
          _buildMetaRow(
            completed: completed,
            total: total,
            completedDuration: completedDuration,
            totalDuration: totalDuration,
            l10n: l10n,
          ),
        ],
      ),
    );
  }

  Widget _buildHeadline(
    HeadlineVariant variant,
    int completed,
    int total,
    AppLocalizations l10n,
  ) {
    const baseStyle = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w800,
      color: Color(0xFF111827),
      letterSpacing: -0.3,
      height: 1.25,
    );
    const primaryNum = TextStyle(color: Color(0xFF0052D0));
    const dimNum = TextStyle(color: Color(0xFF6B7280));

    String text;
    switch (variant) {
      case HeadlineVariant.attemptsOnly:
        text = l10n.workoutLogHeadlineAttemptsOnly(total);
        break;
      case HeadlineVariant.firstTry:
        text = l10n.workoutLogHeadlineFirstTry;
        break;
      case HeadlineVariant.secondStreak:
        text = l10n.workoutLogHeadlineSecondStreak;
        break;
      case HeadlineVariant.streakSmall:
        text = l10n.workoutLogHeadlineStreakSmall(completed);
        break;
      case HeadlineVariant.allCompletedMid:
        text = l10n.workoutLogHeadlineAllCompletedMid(completed);
        break;
      case HeadlineVariant.streakFire:
        text = l10n.workoutLogHeadlineStreakFire(completed);
        break;
      case HeadlineVariant.mixed:
        final line1 = l10n.workoutLogHeadlineMixedLine1(total);
        final line2 = l10n.workoutLogHeadlineMixedLine2(completed);
        return Text.rich(
          TextSpan(
            style: baseStyle,
            children: [
              ..._numberColoredSpans(line1, total.toString(), dimNum),
              const TextSpan(text: '\n'),
              ..._numberColoredSpans(line2, completed.toString(), primaryNum),
            ],
          ),
        );
    }
    return Text(text, style: baseStyle);
  }

  /// Split `source` around the first occurrence of `number` and colour that
  /// occurrence with `numberStyle`. If the digit string isn't found (should
  /// not happen for ARB placeholders), return the whole source as a plain span.
  List<InlineSpan> _numberColoredSpans(
    String source,
    String number,
    TextStyle numberStyle,
  ) {
    final idx = source.indexOf(number);
    if (idx < 0) return [TextSpan(text: source)];
    return [
      if (idx > 0) TextSpan(text: source.substring(0, idx)),
      TextSpan(text: number, style: numberStyle),
      if (idx + number.length < source.length)
        TextSpan(text: source.substring(idx + number.length)),
    ];
  }

  Widget _buildMetaRow({
    required int completed,
    required int total,
    required double completedDuration,
    required double totalDuration,
    required AppLocalizations l10n,
  }) {
    final avgCompleted = completed > 0 ? completedDuration / completed : 0.0;
    final avgTotal = total > 0 ? totalDuration / total : 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMetaChunk(
          label: l10n.workoutLogStatAvg.toUpperCase(),
          completed: completed > 0 ? formatDurationHuman(avgCompleted) : null,
          total: (completed == 0 || completed < total)
              ? formatDurationHuman(avgTotal)
              : null,
        ),
        const SizedBox(width: 18),
        _buildMetaChunk(
          label: l10n.workoutLogMetaTotal.toUpperCase(),
          completed: completed > 0 ? formatDurationHuman(completedDuration) : null,
          total: (completed == 0 || completed < total)
              ? formatDurationHuman(totalDuration)
              : null,
        ),
      ],
    );
  }

  /// A single label + values chunk. `completed` is the primary (blue) value;
  /// `total` is the dim secondary value. Pass `null` to omit either side.
  /// - Both non-null: renders `completed · total` with a `·` separator.
  /// - Only completed: renders `completed` alone.
  /// - Only total: renders `total` alone in dim colour.
  Widget _buildMetaChunk({
    required String label,
    required String? completed,
    required String? total,
  }) {
    const labelStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: Color(0xFF9CA3AF),
      letterSpacing: 0.6,
    );
    const primaryValue = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0052D0),
      fontFeatures: [FontFeature.tabularFigures()],
    );
    const dimValue = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Color(0xFF9CA3AF),
      fontFeatures: [FontFeature.tabularFigures()],
    );
    const sepStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Color(0xFFD1D5DB),
    );

    final children = <InlineSpan>[];
    if (completed != null) {
      children.add(TextSpan(text: completed, style: primaryValue));
    }
    if (completed != null && total != null) {
      children.add(const TextSpan(text: ' · ', style: sepStyle));
    }
    if (total != null) {
      children.add(TextSpan(text: total, style: dimValue));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 3),
        Text.rich(TextSpan(children: children)),
      ],
    );
  }
```

- [ ] **Step 5: Run the analyzer**

```bash
cd apps/mobile && flutter analyze
```

Expected: "No issues found!" (or only pre-existing warnings). Any warning pointing at `workout_log_panel.dart` or `workout_log_headline.dart` is a regression to fix before moving on.

- [ ] **Step 6: Run the unit tests**

```bash
cd apps/mobile && flutter test test/widgets/viewers/workout_log_headline_test.dart
```

Expected: all tests still pass.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/workout_log_panel.dart
git commit -m "feat(mobile): redesign workout log stats as narrative headline

Replaces the 3-tile stats row with a narrative headline + meta block.
Headline copy varies by state: attempts-only, first send, streaks, or
mixed. Meta row always shows 평균 and 누적, collapsing to a single
value when the completed/total distinction is redundant. The 완등만
toggle now only affects the activity list below."
```

---

## Phase 4 — Verification

### Task 5: End-to-end checks

- [ ] **Step 1: Full analyzer pass**

```bash
cd apps/mobile && flutter analyze
```

Expected: "No issues found!" (or only pre-existing unrelated warnings).

- [ ] **Step 2: Full test run**

```bash
cd apps/mobile && flutter test
```

Expected: all tests pass, including the new `workout_log_headline_test.dart`.

- [ ] **Step 3: Visual smoke-test handoff to user**

The mobile build/run commands are off-limits per `apps/mobile/CLAUDE.md`. Summarize to the user what visual cases to check on-device:

- A route with `totalCount == 0`: the section is still hidden.
- A route with `C == 0, T == 1`: `1번 시도` headline, only dim (total) side in meta.
- A route with `C == 1, T == 1`: `1번 만에 완등!` — only blue (completed) side in meta.
- A route with `C == 12, T == 20`: `20번 시도 중 / 12번 완등` two-line headline, both sides in meta (`4:01 · 4:38`, etc.).
- A route with `C == 11, T == 11`: `11번 연속 완등 🔥` headline, only blue side in meta.
- Creating/deleting an activity while on the route viewer should update the headline immediately (optimistic path in `addActivity` / `_deleteActivity`).

No further commit needed — this phase is verification only.

---

## Self-Review Checklist

- Spec's 7 headline states all covered: ✅ tested in Task 2, wired in Task 4.
- Meta duplication-collapse rule covered: ✅ Task 4 `_buildMetaRow` passes `null` appropriately for completed-only (`C == T`) and attempts-only (`C == 0`) cases.
- Duration formatter `Hh MM:SS` threshold covered: ✅ Task 3 tests 3599.99 vs 3600 boundary.
- `_completedOnly` scope narrowed to activity list: ✅ Task 4 step 3 deletes the stat path's read of `_completedOnly`; remaining reads are in `_loadActivities` / `_loadMoreActivities` only.
- L10n keys in all four ARB files: ✅ Task 1 steps 1–4.
- 🔥 emoji preserved in all four locales: ✅ present verbatim in ko/en/ja/es Task 1 edits.
- No new backend or API changes (per spec's Non-Goals): ✅ plan touches only mobile files.
- Existing `_formatDuration` (activity-row formatter) untouched: ✅ new helper is additive.
