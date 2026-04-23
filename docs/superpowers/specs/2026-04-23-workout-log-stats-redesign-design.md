# Workout Log Stats Redesign — Design

**Date:** 2026-04-23
**Scope:** The stats block at the top of `WorkoutLogPanel` (`apps/mobile/lib/widgets/viewers/workout_log_panel.dart`), plus small API/localization touch-ups required to power the new copy.
**Status:** Draft — pending user approval.

## Problem

The route-detail Workout Log currently shows three gray tiles (Sessions, Avg, Total) that swap between "completed only" and "all attempts" based on a toggle in the section header. The toggle controls both the stats *and* the activity list, so the user can only see one view at a time.

Limitations:

- Both figures (시도 vs 완등) are interesting on the same route, but today they're hidden behind a toggle.
- The tile labels and numbers are purely quantitative; they don't communicate anything about how the user is doing on the route (e.g., "first try!" vs "1 of 20 sends").
- There's no average-vs-total distinction; the "Total" tile is actually the sum of durations under whichever filter is active.

## Goal

Replace the three-tile row with a **narrative headline + meta** block that:

1. Always shows both 완등 and 시도 numbers — no more toggle-hides-data.
2. Celebrates perfect runs (all attempts completed) with varying copy from 1 through 10, topping out at a 🔥 line beyond 10.
3. Reports mixed runs (some failures) with a calm "N번 시도 중 M번 완등" headline.
4. Exposes both 평균 and 누적 (for both 완등 and 전체) in a compact meta row, instead of just one of them.
5. Keeps the existing `완등만` toggle, but narrows its scope to **filtering the activity list only** — the stats block becomes toggle-independent.

## Non-Goals

- No change to the activity list (grouping by date, row layout, delete behavior, infinite scroll).
- No change to the `/activity-stats/me` API response shape or the stats fields it returns.
- No change to the optimistic stat updates in `addActivity` / `_deleteActivity` (they still mutate `_stats` in place; only the rendering layer changes).
- No change to how the section is hidden when `totalCount == 0` (the early return at `workout_log_panel.dart:278-280` stays).
- Emoji audit / fun copy for **other** sections (verified completers, etc.) — out of scope.

## Decisions (from brainstorming)

1. **Layout direction:** Option D from `stats-layouts-v4.html` — narrative headline + meta chunks. Tiles are dropped.
2. **Toggle scope narrows:** `completedOnly` no longer drives the stats; it only filters `_activities`.
3. **All-completed copy is hard-coded per count** for 1~10; 11+ collapses to a single celebratory template with 🔥.
4. **Meta is always shown** (when there's data to show) — no hiding 평균/누적 in celebratory states.
5. **Duplicate suppression:** when 완등 == 전체 (all completed) or 완등 == 0, only the non-redundant side is printed in meta.

## Copy Rules

Let `T` = `totalCount` (completed + failed attempts) and `C` = `completedCount`. `T ≥ 1` always (otherwise the section is hidden).

### Headline

| State | Condition | Korean headline | Shape |
|---|---|---|---|
| Attempts only | `C == 0`, `T ≥ 1` | `T번 시도` | 1 line |
| First-try send | `C == 1` and `T == 1` | `1번 만에 완등!` | 1 line |
| Second consecutive | `C == 2` and `T == 2` | `2번째도 완등!` | 1 line |
| 3~5 consecutive | `C == T` and `3 ≤ C ≤ 5` | `{C}번 연속 완등!` | 1 line |
| 6~10 all complete | `C == T` and `6 ≤ C ≤ 10` | `{C}번 전부 완등!` | 1 line |
| 11+ all complete | `C == T` and `C ≥ 11` | `{C}번 연속 완등 🔥` | 1 line |
| Mixed | `0 < C < T` | `{T}번 시도 중`<br>`{C}번 완등` | 2 lines |

Emoji (🔥) is explicitly approved by the user for the 11+ case — it's the only emoji in the block and must be preserved through localization.

### Meta row

Always two chunks side-by-side: **평균** and **누적**.

For each chunk, the value is one of:

| Chunk state | Condition | Value format |
|---|---|---|
| Comparison (both meaningful) | `0 < C < T` | `{완등값 (파랑)}` `·` `{전체값 (회색)}` |
| Completed only | `C == T` | `{완등값 (파랑)}` (single value) |
| Attempts only | `C == 0` | `{전체값 (회색)}` (single value) |

Values:

- 평균 완등 = `completedDuration / completedCount` (only shown when `C > 0`)
- 평균 전체 = `totalDuration / totalCount` (only shown when needed per rules above)
- 누적 완등 = `completedDuration` (only shown when `C > 0`)
- 누적 전체 = `totalDuration` (only shown when needed per rules above)

Duration formatting reuses the existing `_formatDuration` helper (MM:SS.cs). For spans ≥ 1 hour, fall back to `H:MM:SS` so `1h 32:45` style remains readable. (Today `_formatDuration` returns `MM:SS.cs` regardless, so this is a small new helper — see Implementation.)

## Visual Structure

```
┌ SectionHeader (title + 완등만 pill — unchanged) ┐
│                                                  │
│ 20번 시도 중                          ← 22px/800/#111  (dim-num: #6B7280 on "20")
│ 12번 완등                             ← 22px/800/#111  (num: #0052D0 on "12")
│                                                  │
│ ─ 1px #EFF1F2 ──                                │
│                                                  │
│ 평균                누적               ← 10px/w700/#9CA3AF uppercase
│ 4:01 · 4:38        48:20 · 1h 32:45  ← 13px/w700; blue/dim pair separated by #D1D5DB "·"
│                                                  │
└──────────────────────────────────────────────────┘
```

- Padding: `EdgeInsets.fromLTRB(24, 2, 24, 16)` (matches the narrative `.narr` padding in the mock).
- Headline: `Text.rich` with mixed-color spans. Line height ~1.25, letter-spacing -0.3. The two-line mixed state uses an explicit `\n`.
- Divider: `Padding(padding: EdgeInsets.only(top: 10)) + Container(height: 1, color: #EFF1F2)` inside the block, above the meta row.
- Meta row: `Row` with `spacing: 18` (use `SizedBox(width: 18)` for Flutter stable), each chunk a `Column(crossAxisAlignment: start)` of label + value.
- Color tokens: primary `#0052D0`, dim-num/text `#6B7280`, secondary `#9CA3AF`, separator `#D1D5DB`, divider `#EFF1F2`.

The three-tile `_buildStatsRow` / `_statTile` helpers are deleted.

## State Interaction

- `_completedOnly` is no longer read inside `_buildStatsRow` (removed). It continues to drive `_loadActivities` (which passes `status: 'completed'` or `null`).
- After `addActivity` or `_deleteActivity` mutates `_stats`, the new render block reads the updated numbers on the next `setState`. Optimistic updates already cover the fields we need (`totalCount`, `totalDuration`, `completedCount`, `completedDuration`); no new fields are required.

## L10n

New keys in `app_ko.arb` (primary), `app_en.arb`, `app_ja.arb`, `app_es.arb`:

| Key | `ko` (source) | Notes |
|---|---|---|
| `workoutLogHeadlineAttemptsOnly` | `{count}번 시도` | `count` placeholder |
| `workoutLogHeadlineFirstTry` | `1번 만에 완등!` | literal |
| `workoutLogHeadlineSecondStreak` | `2번째도 완등!` | literal |
| `workoutLogHeadlineStreakSmall` | `{count}번 연속 완등!` | 3–5 |
| `workoutLogHeadlineAllCompletedMid` | `{count}번 전부 완등!` | 6–10 |
| `workoutLogHeadlineStreakFire` | `{count}번 연속 완등 🔥` | 11+; emoji preserved in all locales |
| `workoutLogHeadlineMixedLine1` | `{count}번 시도 중` | first line of mixed |
| `workoutLogHeadlineMixedLine2` | `{count}번 완등` | second line of mixed |
| `workoutLogMetaAvg` | `평균` | existing `workoutLogStatAvg` is `평균` / `Avg` / `Promedio` / `平均` — **reuse** instead of adding a new key |
| `workoutLogMetaTotal` | `누적` | new — the existing `workoutLogStatTotal` is `총 시간` / `Total` / `Total` / `合計`. For ko we want `누적` specifically. Add a new key and leave the old one untouched so the rest of the app is unaffected. |

Existing keys to reuse: `workoutLogStatAvg`, `workoutLog`, `completedOnly`.

Existing keys that become unused: `workoutLogStatSessions`, `workoutLogStatTotal`. Leave them in place for now — they're not costly to keep and may be wanted for future surfaces; a separate cleanup pass can prune if desired.

## Edge Cases

- **Loading (`_statsLoading` or `_stats == null`):** early return `SizedBox.shrink()` — unchanged.
- **`totalCount == 0`:** section hidden — unchanged (line 278-280).
- **Data inconsistency (`completedCount > totalCount`):** should never happen per API; if it does, clamp `C = min(C, T)` defensively before picking a headline variant. Log nothing — the surface is read-only.
- **Very large counts (`C > 99` with 🔥 headline):** copy still fits on one line at 22px on the 340px mock frame; no special truncation needed. If it ever wraps on smaller devices, the line height handles it.
- **Durations of 0 seconds in completed-only state:** `평균 0:00.00`, `누적 0:00.00` is acceptable — no special empty-string handling.

## Implementation Sketch

In `workout_log_panel.dart`:

1. Delete `_buildStatsRow` and `_statTile`.
2. Add `_buildHeadlineBlock(AppLocalizations l10n)` returning a `Padding(EdgeInsets.fromLTRB(24, 2, 24, 16), child: Column(...))` with:
   - headline `Text.rich` (choose spans via a pure function `_pickHeadline(C, T, l10n) → List<TextSpan>`)
   - 1px divider
   - `Row` of two meta chunks, each built by `_buildMetaChunk(label, values)`
3. Add a duration formatter for hours: `_formatDurationHuman(seconds)` returning `MM:SS.cs` under 1h and `Hh MM:SS` at/above 1h. Apply only to meta values. Keep `_formatDuration` (the MM:SS.cs variant) for the per-activity rows — they're short by nature.
4. In `build()`, replace the `_buildStatsRow(l10n)` call with `_buildHeadlineBlock(l10n)`.
5. Add the new l10n keys to the four ARB files and re-run code generation (`flutter gen-l10n` runs on analyze in this project, or via build_runner per `apps/mobile/CLAUDE.md`).

The headline selector is the entire business logic; keep it pure and co-located with the widget for easy reading:

```dart
List<TextSpan> _pickHeadline(int c, int t, AppLocalizations l10n) {
  // c: completedCount, t: totalCount (both ≥ 0, t ≥ 1 when this runs)
  if (c == 0) return [TextSpan(text: l10n.workoutLogHeadlineAttemptsOnly(t))];
  if (c == t) {
    if (c == 1) return [TextSpan(text: l10n.workoutLogHeadlineFirstTry)];
    if (c == 2) return [TextSpan(text: l10n.workoutLogHeadlineSecondStreak)];
    if (c <= 5) return [TextSpan(text: l10n.workoutLogHeadlineStreakSmall(c))];
    if (c <= 10) return [TextSpan(text: l10n.workoutLogHeadlineAllCompletedMid(c))];
    return [TextSpan(text: l10n.workoutLogHeadlineStreakFire(c))];
  }
  // mixed: color the numbers
  return _mixedHeadlineSpans(c, t, l10n);
}
```

For mixed, `_mixedHeadlineSpans` splits the two ARB lines around the `{count}` placeholder and wraps the digits in the primary/dim colors.

## Verification

- `flutter analyze` clean (primary check per `apps/mobile/CLAUDE.md`).
- Visual spot-check in the browser companion (v4 mock is the canonical reference for spacing and color).
- Manual smoke: on a route, create an activity (completed + verified), delete it, verify the headline updates in place through the existing optimistic path.
- Sanity-check each of the 7 copy states by varying `_stats` temporarily (a dev-only tap-to-cycle is **not** required; visual inspection while seeding a few routes is enough).

## Open Questions

None — all variants are fixed by the decisions above.
