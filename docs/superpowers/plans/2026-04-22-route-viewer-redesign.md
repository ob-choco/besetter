# Route Viewer Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the "section grammar" (blue small-caps title + right-aligned gray meta) across the body of the route viewer (Hold Sequence, Workout Log, Verified Completers) and raise timer-completion precision to 2-decimal seconds in all four locales.

**Architecture:** One shared `SectionHeader` widget and one `SectionDivider` widget live in `lib/widgets/viewers/section_header.dart`. The three section widgets consume `SectionHeader`. `route_viewer.dart` interleaves `SectionDivider` between body children and stops painting ad-hoc borders/dividers. `activity_confirmation.dart` swaps its seconds-only formatter for two new ARB-backed decimal formatters.

**Tech Stack:** Flutter (Dart), `hooks_riverpod`, `flutter_gen/gen_l10n` (ARB-driven), existing widget patterns in `lib/widgets/viewers/`.

**Verification:** `flutter analyze` is the primary check (per `apps/mobile/CLAUDE.md`). There is no TDD harness for mobile widgets in this repo (only a stub `widget_test.dart`), so this plan uses analyzer-based verification and explicit post-change visual expectations rather than unit tests. Do **not** run `flutter build …` or `flutter run …` — those are explicitly disallowed for this environment.

**Reference spec:** `docs/superpowers/specs/2026-04-22-route-viewer-redesign-design.md`

---

### Task 1: Add shared `SectionHeader` and `SectionDivider` widgets

Everything else depends on these two widgets. Build them first in isolation so later tasks just drop them in.

**Files:**
- Create: `apps/mobile/lib/widgets/viewers/section_header.dart`

- [ ] **Step 1: Create the file with both widgets**

```dart
import 'package:flutter/material.dart';

/// Unified section header used across the route viewer body.
///
/// Renders `[blue small-caps title]` on the left and an optional gray meta
/// string on the right. Optional `trailing` widget replaces `meta` when
/// provided (e.g., a tappable filter toggle).
class SectionHeader extends StatelessWidget {
  final String title;
  final String? meta;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.meta,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final rightSide = trailing ??
        (meta != null
            ? Text(
                meta!,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.5,
                ),
              )
            : const SizedBox.shrink());

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0052D0),
                letterSpacing: 1.5,
              ),
            ),
          ),
          rightSide,
        ],
      ),
    );
  }
}

/// 1px divider placed between body sections of the route viewer.
/// Inset 24px on each side to match the horizontal padding of sections.
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      color: const Color(0xFFECEFF2),
    );
  }
}
```

- [ ] **Step 2: Verify analyze passes**

Run: `cd apps/mobile && flutter analyze lib/widgets/viewers/section_header.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/section_header.dart
git commit -m "feat(mobile): add SectionHeader and SectionDivider shared widgets"
```

---

### Task 2: Add decimal-duration ARB keys (ko/en/ja/es)

Add the two new message keys that `ActivityConfirmation` will use. Do this before touching the Dart code so the generated `AppLocalizations` has the new accessors by the time Task 3 runs.

**Files:**
- Modify: `apps/mobile/lib/l10n/app_ko.arb`
- Modify: `apps/mobile/lib/l10n/app_en.arb`
- Modify: `apps/mobile/lib/l10n/app_ja.arb`
- Modify: `apps/mobile/lib/l10n/app_es.arb`

- [ ] **Step 1: Locate the existing `activityDurationFormat` key in `app_ko.arb`**

Read `apps/mobile/lib/l10n/app_ko.arb` and find the `activityDurationFormat` key. Insert the two new keys immediately after it (after the `@activityDurationFormat` metadata block), before the next key.

- [ ] **Step 2: Add the Korean entries**

Append to `apps/mobile/lib/l10n/app_ko.arb` after the `activityDurationFormat` block:

```json
  "activityDurationWithMinutesDecimal": "{minutes}분 {seconds}.{centiseconds}초",
  "@activityDurationWithMinutesDecimal": {
    "placeholders": {
      "minutes": {"type": "int"},
      "seconds": {"type": "int"},
      "centiseconds": {"type": "String"}
    }
  },
  "activityDurationSecondsDecimal": "{seconds}.{centiseconds}초",
  "@activityDurationSecondsDecimal": {
    "placeholders": {
      "seconds": {"type": "int"},
      "centiseconds": {"type": "String"}
    }
  },
```

- [ ] **Step 3: Add the English entries**

Append to `apps/mobile/lib/l10n/app_en.arb` after the `activityDurationFormat` block:

```json
  "activityDurationWithMinutesDecimal": "{minutes}m {seconds}.{centiseconds}s",
  "@activityDurationWithMinutesDecimal": {
    "placeholders": {
      "minutes": {"type": "int"},
      "seconds": {"type": "int"},
      "centiseconds": {"type": "String"}
    }
  },
  "activityDurationSecondsDecimal": "{seconds}.{centiseconds}s",
  "@activityDurationSecondsDecimal": {
    "placeholders": {
      "seconds": {"type": "int"},
      "centiseconds": {"type": "String"}
    }
  },
```

- [ ] **Step 4: Add the Japanese entries**

Append to `apps/mobile/lib/l10n/app_ja.arb` after the `activityDurationFormat` block:

```json
  "activityDurationWithMinutesDecimal": "{minutes}分 {seconds}.{centiseconds}秒",
  "@activityDurationWithMinutesDecimal": {
    "placeholders": {
      "minutes": {"type": "int"},
      "seconds": {"type": "int"},
      "centiseconds": {"type": "String"}
    }
  },
  "activityDurationSecondsDecimal": "{seconds}.{centiseconds}秒",
  "@activityDurationSecondsDecimal": {
    "placeholders": {
      "seconds": {"type": "int"},
      "centiseconds": {"type": "String"}
    }
  },
```

- [ ] **Step 5: Add the Spanish entries**

Append to `apps/mobile/lib/l10n/app_es.arb` after the `activityDurationFormat` block:

```json
  "activityDurationWithMinutesDecimal": "{minutes}m {seconds}.{centiseconds}s",
  "@activityDurationWithMinutesDecimal": {
    "placeholders": {
      "minutes": {"type": "int"},
      "seconds": {"type": "int"},
      "centiseconds": {"type": "String"}
    }
  },
  "activityDurationSecondsDecimal": "{seconds}.{centiseconds}s",
  "@activityDurationSecondsDecimal": {
    "placeholders": {
      "seconds": {"type": "int"},
      "centiseconds": {"type": "String"}
    }
  },
```

- [ ] **Step 6: Regenerate localizations**

Run: `cd apps/mobile && flutter gen-l10n`
Expected: A short advisory such as `Because l10n.yaml exists, the options defined there will be used instead.` and the generated files under `.dart_tool/flutter_gen/` get updated. No errors.

- [ ] **Step 7: Verify analyze passes**

Run: `cd apps/mobile && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/l10n/app_ko.arb apps/mobile/lib/l10n/app_en.arb apps/mobile/lib/l10n/app_ja.arb apps/mobile/lib/l10n/app_es.arb
git commit -m "i18n(mobile): add decimal-second duration keys for activity completion"
```

---

### Task 3: Update `ActivityConfirmation` to display decimal seconds

Replace the integer-second formatter with one that preserves 2 decimals and routes through the new ARB keys.

**Files:**
- Modify: `apps/mobile/lib/widgets/viewers/activity_confirmation.dart`

- [ ] **Step 1: Replace the `_formatDuration` method**

Open `apps/mobile/lib/widgets/viewers/activity_confirmation.dart`. Replace the current method (lines 16-23):

```dart
  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    if (minutes > 0) {
      return '$minutes분 $seconds초';
    }
    return '$seconds초';
  }
```

with a context-aware version that uses the new ARB keys:

```dart
  String _formatDuration(BuildContext context, Duration d) {
    final l10n = AppLocalizations.of(context)!;
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final centiseconds =
        ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    if (minutes > 0) {
      return l10n.activityDurationWithMinutesDecimal(
        minutes,
        seconds,
        centiseconds,
      );
    }
    return l10n.activityDurationSecondsDecimal(seconds, centiseconds);
  }
```

- [ ] **Step 2: Update the call site in `build`**

Still in `activity_confirmation.dart`, change the single call inside `build(...)` (currently line 72):

From:
```dart
            l10n.activityDurationFormat(statusText, _formatDuration(elapsed)),
```

To:
```dart
            l10n.activityDurationFormat(statusText, _formatDuration(context, elapsed)),
```

- [ ] **Step 3: Verify analyze passes**

Run: `cd apps/mobile && flutter analyze lib/widgets/viewers/activity_confirmation.dart`
Expected: `No issues found!`

- [ ] **Step 4: Manual verification (read-only)**

Trace by hand: a 5-second activity produces `d.inMilliseconds = 5000`, so `centiseconds = (5000 % 1000) ~/ 10 = 00`, minutes = 0, seconds = 5 → renders `5.00초` (ko), `5.00s` (en). A 5-minute 46.32-second activity produces minutes=5, seconds=46, centiseconds=`32` → renders `5분 46.32초` (ko). This matches the locale table in the spec.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/activity_confirmation.dart
git commit -m "feat(mobile): show 2-decimal seconds on activity completion"
```

---

### Task 4: Apply `SectionHeader` to `EnduranceRouteHolds` and left-align thumbnails

`EnduranceRouteHolds` is the only hold-row widget that currently renders a "Hold Sequence" title — `BoulderingRouteHolds` renders four hold-type filter buttons instead and needs no header change.

**Files:**
- Modify: `apps/mobile/lib/widgets/viewers/endurance_route_holds.dart`

- [ ] **Step 1: Add the `SectionHeader` import and drop the unused `AppLocalizations` import lines**

At the top of `apps/mobile/lib/widgets/viewers/endurance_route_holds.dart`, keep the existing imports and add one line:

```dart
import 'section_header.dart';
```

- [ ] **Step 2: Replace the inline header with `SectionHeader`**

In the `build` method of `_EnduranceRouteHoldsState` (starting line 104), replace the current `Column` child that wraps `Padding(EdgeInsets.symmetric(horizontal: 24, vertical: 8))` containing the title + count `Row` (lines 107-130) with a direct `SectionHeader` call. The `build` body becomes:

```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        SectionHeader(
          title: l10n.holdSequence,
          meta: l10n.holdsTotalCapitalized(widget.holds.length),
        ),
        GestureDetector(
          onHorizontalDragUpdate: _onPanUpdate,
          onHorizontalDragEnd: _onPanEnd,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 130,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxScaledSize = _baseSize * _maxScale;
                // Left-align origin: first hold sits at x=24 (matching
                // the 24px horizontal padding of the section grammar).
                final originX = 24.0 + maxScaledSize / 2;
                final visibleRange = constraints.maxWidth + maxScaledSize;

                final indices = <int>[];
                for (int i = 0; i < widget.holds.length; i++) {
                  if ((i * _itemWidth - _scrollOffset).abs() <= visibleRange) {
                    indices.add(i);
                  }
                }
                indices.sort((a, b) {
                  final distA = (_scrollOffset - a * _itemWidth).abs();
                  final distB = (_scrollOffset - b * _itemWidth).abs();
                  return distB.compareTo(distA);
                });

                return Stack(
                  clipBehavior: Clip.none,
                  children: indices.map((index) {
                    final hold = widget.holds[index];
                    final image = widget.croppedImages[hold.polygonId];
                    final scale = _calculateScale(index);
                    final isCenter = index == _currentHighlightedIndex;
                    final scaledSize = _baseSize * scale;

                    final itemX = originX +
                        (index * _itemWidth - _scrollOffset) -
                        scaledSize / 2;
                    final itemY = (105 - scaledSize) / 2;

                    return Positioned(
                      left: itemX,
                      top: itemY,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: scaledSize,
                            height: scaledSize,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: isCenter
                                    ? const Color(0xFF0066FF)
                                    : const Color(0xFFE6E8EA),
                                width: isCenter ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 20,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: image != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: RawImage(
                                      image: image,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isCenter
                                  ? const Color(0xFF0066FF)
                                  : const Color(0xFF595C5D),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
```

Notes on what changed vs the original:
- Inline header block replaced with `SectionHeader(…)`.
- `centerX` (`constraints.maxWidth / 2`) replaced by `originX = 24 + maxScaledSize/2` so the active hold sits at the left 24px margin rather than the center.
- `visibleRange` widened slightly to account for the new origin so holds scrolling in from the right remain drawn.

- [ ] **Step 3: Verify analyze passes**

Run: `cd apps/mobile && flutter analyze lib/widgets/viewers/endurance_route_holds.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/endurance_route_holds.dart
git commit -m "feat(mobile): unify Hold Sequence header and left-align carousel"
```

---

### Task 5: Flatten `WorkoutLogPanel` — remove gray card, apply `SectionHeader`

Drop the outer gray-rounded container and the ad-hoc header, adopt the shared section grammar, and turn the stats line into three gray chip tiles.

**Files:**
- Modify: `apps/mobile/lib/widgets/viewers/workout_log_panel.dart`

- [ ] **Step 1: Add the shared-header import**

Near the existing imports at the top of `apps/mobile/lib/widgets/viewers/workout_log_panel.dart`, add:

```dart
import 'section_header.dart';
```

- [ ] **Step 2: Replace the `build` method body**

Replace the current `build` method (starting at line 273) with:

```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_statsLoading) return const SizedBox.shrink();
    if (_stats != null && (_stats!['totalCount'] as int) == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.workoutLog,
          trailing: GestureDetector(
            onTap: _toggleFilter,
            behavior: HitTestBehavior.opaque,
            child: Text(
              l10n.completedOnly,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _completedOnly
                    ? const Color(0xFF0052D0)
                    : const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
        _buildStatsRow(l10n),
        if (_activitiesLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_activities.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                l10n.noWorkoutRecords,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF595C5D),
                ),
              ),
            ),
          )
        else
          _buildActivityList(),
      ],
    );
  }
```

- [ ] **Step 3: Replace `_buildHeader` with `_buildStatsRow` (three chip tiles)**

Delete the existing `_buildHeader` method (lines 320-385) entirely. Add a new `_buildStatsRow` method that renders the three gray-chip stats tiles:

```dart
  Widget _buildStatsRow(AppLocalizations l10n) {
    int count = 0;
    double duration = 0;
    if (_stats != null) {
      if (_completedOnly) {
        count = (_stats!['completedCount'] as num).toInt();
        duration = (_stats!['completedDuration'] as num).toDouble();
      } else {
        count = (_stats!['totalCount'] as num).toInt();
        duration = (_stats!['totalDuration'] as num).toDouble();
      }
    }
    final avgSeconds = count > 0 ? duration / count : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Row(
        children: [
          Expanded(
            child: _statTile(
              value: count.toString(),
              label: l10n.workoutLogStatSessions.toUpperCase(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _statTile(
              value: _formatDuration(avgSeconds),
              label: l10n.workoutLogStatAvg.toUpperCase(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _statTile(
              value: _formatDuration(duration),
              label: l10n.workoutLogStatTotal.toUpperCase(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile({required String value, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
```

If `dart:ui` is not yet imported in this file (the `FontFeature` usage needs it), add this import at the top alongside the existing imports:

```dart
import 'dart:ui' show FontFeature;
```

(If `FontFeature` is already in scope via another import, skip the import add — `flutter analyze` will flag a duplicate otherwise.)

- [ ] **Step 4: Add the new l10n keys for stat-tile labels**

The three chip labels reference three new ARB keys. Add them to all four ARB files alongside the existing `workoutLog`/`completedOnly` entries. Insert near the top of each ARB file after `workoutLog`:

`apps/mobile/lib/l10n/app_ko.arb`:
```json
  "workoutLogStatSessions": "세션",
  "workoutLogStatAvg": "평균",
  "workoutLogStatTotal": "총 시간",
```

`apps/mobile/lib/l10n/app_en.arb`:
```json
  "workoutLogStatSessions": "Sessions",
  "workoutLogStatAvg": "Avg",
  "workoutLogStatTotal": "Total",
```

`apps/mobile/lib/l10n/app_ja.arb`:
```json
  "workoutLogStatSessions": "セッション",
  "workoutLogStatAvg": "平均",
  "workoutLogStatTotal": "合計",
```

`apps/mobile/lib/l10n/app_es.arb`:
```json
  "workoutLogStatSessions": "Sesiones",
  "workoutLogStatAvg": "Promedio",
  "workoutLogStatTotal": "Total",
```

- [ ] **Step 5: Regenerate localizations**

Run: `cd apps/mobile && flutter gen-l10n`
Expected: advisory about `l10n.yaml`, no errors.

- [ ] **Step 6: Verify analyze passes**

Run: `cd apps/mobile && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/workout_log_panel.dart apps/mobile/lib/l10n/app_ko.arb apps/mobile/lib/l10n/app_en.arb apps/mobile/lib/l10n/app_ja.arb apps/mobile/lib/l10n/app_es.arb
git commit -m "feat(mobile): flatten WorkoutLogPanel onto unified section grammar"
```

---

### Task 6: Apply `SectionHeader` to `VerifiedCompletersRow` and drop the 🏅 emoji

**Files:**
- Modify: `apps/mobile/lib/widgets/viewers/verified_completers_row.dart`

- [ ] **Step 1: Add the shared-header import**

Near the existing imports in `apps/mobile/lib/widgets/viewers/verified_completers_row.dart`, add:

```dart
import 'section_header.dart';
```

- [ ] **Step 2: Replace the outer `Padding` + header `Row` with `SectionHeader`**

In the `build` method of `_VerifiedCompletersRowState` (starting line 74), replace the current wrapper

```dart
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${l10n.verifiedCompletersTitle} 🏅',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '· ${l10n.verifiedCompletersCount(widget.totalCount)}',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 10),
```

with

```dart
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.verifiedCompletersTitle,
          meta: l10n.verifiedCompletersCount(widget.totalCount),
        ),
```

and wrap each body branch (`isEmpty` / `_loading` / `_error` / `LayoutBuilder`) in a `Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 14), child: …)` so the thumbnails/empty state still sit within the 24px horizontal rhythm. The closing `)` of the top-level `Column` replaces the closing `)` of the deleted `Padding`.

The complete resulting `build` method:

```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEmpty = widget.totalCount <= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.verifiedCompletersTitle,
          meta: l10n.verifiedCompletersCount(widget.totalCount),
        ),
        if (isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: SizedBox(
              height: _itemHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.verifiedCompletersEmpty,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.verifiedCompletersEmptyCta,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (_loading)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: SizedBox(
              height: _itemHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: SizedBox(
              height: _itemHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.failedToLoadData,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: LayoutBuilder(builder: (ctx, constraints) {
              final width = constraints.maxWidth;
              final needsChip = widget.totalCount > _preview.length;
              final usable = needsChip ? (width - _chipReserve) : width;
              final maxFit = ((usable + _gap) / (_itemWidth + _gap)).floor();
              final showCount = maxFit.clamp(0, _preview.length);
              final overflow = widget.totalCount - showCount;
              return SizedBox(
                height: _itemHeight,
                child: Row(
                  children: [
                    for (var i = 0; i < showCount; i++) ...[
                      _AvatarWithHandle(
                        user: _preview[i].user,
                        count: _preview[i].verifiedCompletedCount,
                        onTap: _openSheet,
                        deletedLabel: l10n.deletedUser,
                      ),
                      if (i != showCount - 1) const SizedBox(width: _gap),
                    ],
                    if (overflow > 0) ...[
                      const SizedBox(width: _gap),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: InkWell(
                            onTap: _openSheet,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F5F5),
                                border:
                                    Border.all(color: const Color(0xFFE0E0E0)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                l10n.verifiedCompletersMore(overflow),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ),
      ],
    );
  }
```

- [ ] **Step 3: Verify analyze passes**

Run: `cd apps/mobile && flutter analyze lib/widgets/viewers/verified_completers_row.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/widgets/viewers/verified_completers_row.dart
git commit -m "feat(mobile): unify Verified Completers header, drop medal emoji"
```

---

### Task 7: Interleave `SectionDivider` in `route_viewer.dart` and remove ad-hoc borders

Now that each section widget stops painting its own surround, `route_viewer.dart` owns the inter-section dividers.

**Files:**
- Modify: `apps/mobile/lib/pages/viewers/route_viewer.dart`

- [ ] **Step 1: Add the shared-widget import**

Alongside the existing `../../widgets/viewers/...` imports at the top of `apps/mobile/lib/pages/viewers/route_viewer.dart`, add:

```dart
import '../../widgets/viewers/section_header.dart';
```

- [ ] **Step 2: Replace the hold-list `Container` wrapper**

Find the block (currently lines 284-319) that begins `if (_imagesLoaded) Container(padding: …, decoration: BoxDecoration(border: Border(top: …)), child: …)`. Replace the `Container` wrapper so it no longer paints a top border and no longer applies inner vertical padding — the child (`EnduranceRouteHolds` or `BoulderingRouteHolds`) becomes the direct child of the outer `Column`, preceded by a `SectionDivider`.

Change:

```dart
                  if (_imagesLoaded)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                      ),
                      child: widget.routeData.type == RouteType.endurance
                          ? EnduranceRouteHolds(
                              holds: widget.routeData.enduranceHolds ?? [],
                              croppedImages: _croppedImages,
                              onHighlightHolds: (holdIds) {
                                setState(() {
                                  _highlightedHoldIds = holdIds;
                                });
                              },
                            )
                          : BoulderingRouteHolds(
                              holds: _getHoldProperties(),
                              onHighlightHolds: (holdIds) {
                                setState(() {
                                  _highlightedHoldIds = holdIds;
                                });
                              },
                              selectedType: _selectedHoldType,
                              onTypeSelected: (type) {
                                setState(() {
                                  _selectedHoldType = type;
                                });
                              },
                            ),
                    ),
```

to:

```dart
                  if (_imagesLoaded) ...[
                    const SectionDivider(),
                    widget.routeData.type == RouteType.endurance
                        ? EnduranceRouteHolds(
                            holds: widget.routeData.enduranceHolds ?? [],
                            croppedImages: _croppedImages,
                            onHighlightHolds: (holdIds) {
                              setState(() {
                                _highlightedHoldIds = holdIds;
                              });
                            },
                          )
                        : BoulderingRouteHolds(
                            holds: _getHoldProperties(),
                            onHighlightHolds: (holdIds) {
                              setState(() {
                                _highlightedHoldIds = holdIds;
                              });
                            },
                            selectedType: _selectedHoldType,
                            onTypeSelected: (type) {
                              setState(() {
                                _selectedHoldType = type;
                              });
                            },
                          ),
                    const SectionDivider(),
                  ],
```

- [ ] **Step 3: Add dividers around `ActivityPanel` and between the remaining body widgets**

Right after the new block above, the scrolling `Column` continues with `ActivityPanel`, `WorkoutLogPanel`, `VerifiedCompletersRow`. Interleave dividers so every section boundary paints exactly one 1px inset line. Replace:

```dart
                  // Activity panel (slide-to-start / timer / confirmation)
                  ActivityPanel(
                    routeId: widget.routeData.id,
                    onActivityCreated: (activityData) {
                      (_workoutLogKey.currentState as dynamic)?.addActivity(activityData);
                      final container = ProviderScope.containerOf(context);
                      container.read(activityDirtyProvider.notifier).state = true;
                      container.invalidate(recentClimbedRoutesProvider);
                    },
                  ),
                  // Workout log (stats + activity list)
                  WorkoutLogPanel(
                    key: _workoutLogKey,
                    routeId: widget.routeData.id,
                  ),
                  VerifiedCompletersRow(
                    routeId: widget.routeData.id,
                    totalCount:
                        widget.routeData.completerStats.verifiedCompleterCount,
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    height: 1,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
```

with:

```dart
                  ActivityPanel(
                    routeId: widget.routeData.id,
                    onActivityCreated: (activityData) {
                      (_workoutLogKey.currentState as dynamic)?.addActivity(activityData);
                      final container = ProviderScope.containerOf(context);
                      container.read(activityDirtyProvider.notifier).state = true;
                      container.invalidate(recentClimbedRoutesProvider);
                    },
                  ),
                  const SectionDivider(),
                  WorkoutLogPanel(
                    key: _workoutLogKey,
                    routeId: widget.routeData.id,
                  ),
                  const SectionDivider(),
                  VerifiedCompletersRow(
                    routeId: widget.routeData.id,
                    totalCount:
                        widget.routeData.completerStats.verifiedCompleterCount,
                  ),
                  const SectionDivider(),
```

Do not add a `SizedBox(height: 16)` after the final `SectionDivider`. The Grade block's existing top spacing handles the gap.

- [ ] **Step 4: Trim the Grade block's leading spacing**

The Grade block is wrapped in the `Padding(horizontal: 24)` block below. Its first child `Container(padding: EdgeInsets.only(top: 6, bottom: 16), decoration: BoxDecoration(border: Border(bottom: …)))` already provides `top: 6`. Leave that untouched — it sits 6px below the new `SectionDivider`, which is the correct rhythm.

- [ ] **Step 5: Verify analyze passes**

Run: `cd apps/mobile && flutter analyze lib/pages/viewers/route_viewer.dart`
Expected: `No issues found!`

- [ ] **Step 6: Final repo-wide analyze**

Run: `cd apps/mobile && flutter analyze`
Expected: `No issues found!` for the entire workspace (other files unaffected by this plan must remain clean).

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/pages/viewers/route_viewer.dart
git commit -m "feat(mobile): interleave SectionDivider across route viewer body"
```

---

## Self-Review Notes

**Spec coverage — every spec requirement maps to at least one task:**

- "Section grammar" (padding, title style, meta style) → Task 1 implements the exact tokens.
- Inset 1px `#ECEFF2` divider → Task 1 + Task 7.
- Hold Sequence unified header + left-aligned thumbnails → Task 4.
- Slide-to-start band → Task 7 (`ActivityPanel` sits between two `SectionDivider`s; its internal `Padding(horizontal: 24, vertical: 16)` already gives the band look — no code change needed to `activity_panel.dart` itself).
- Workout Log flatten + small-caps header + Completed-only text button + gray stat chips → Task 5.
- Verified Completers small-caps header, emoji removal, empty-state footprint preserved → Task 6.
- Grade block and below untouched → no task touches `_buildMetaRow`, `_buildExpiryRow`, `_getGradeLevel`, or the description `Container`.
- Timer completion 2-decimal seconds + new l10n keys → Tasks 2 and 3.

**Type/identifier consistency:**

- `SectionHeader` and `SectionDivider` names match across Tasks 1, 4, 5, 6, 7.
- New ARB keys `activityDurationWithMinutesDecimal` / `activityDurationSecondsDecimal` match Tasks 2 and 3.
- New ARB keys `workoutLogStatSessions` / `workoutLogStatAvg` / `workoutLogStatTotal` appear in Task 5 only.
- `_formatDuration` signature changes from `(Duration)` to `(BuildContext, Duration)` inside `activity_confirmation.dart` — the single call site is updated in the same task.

**Deviations from the spec (documented):**

- `BoulderingRouteHolds` is **not** modified. Inspection revealed it renders four filter buttons (Start / Top / Hold / Foot) rather than a "Hold Sequence" title, so the spec's requirement applies to `endurance_route_holds.dart` only. The spec's "two hold-row widgets" phrasing was a minor mis-read of the codebase.
- `ActivityPanel` outer `Padding(horizontal: 24, vertical: 16)` is **not** retuned to `(24, 14, 24, 14)`. The same padding covers slide / timer / confirmation children; the 2px vertical difference is visually imperceptible, and the timer/confirmation are explicitly out of scope. Route-viewer-owned `SectionDivider`s above and below produce the "band" effect the spec describes.
