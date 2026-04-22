# Route Viewer Redesign — Design

**Date:** 2026-04-22
**Scope:** `lib/pages/viewers/route_viewer.dart` and the scrolling content below the image.
**Status:** Draft — pending user approval.

## Problem

The route viewer page below the route image stacks several sub-sections
(Hold Sequence, Slide-to-start, Workout Log, Verified Completers, Grade,
Meta rows, Description) that each invent their own visual rules:

- Containers are inconsistent — Workout Log is a rounded gray card, every other section is flat.
- Section titles mix four styles — `Hold Sequence` (bold title case), `WORKOUT LOG` (small caps inside a card), `Verified Completers 🏅 · 0` (bold + emoji + bullet count), `CURRENT GRADE` (blue small caps).
- Hold Sequence header is left-aligned but the thumbnails are right-aligned, leaving an awkward empty block.
- Slide-to-start is a floating pill with no section frame, visually competing with the Workout Log card beneath it.
- Dividers appear between some sections (Completers ↔ Grade) but not others.
- Verified Completers empty state has no enclosing container.

The page reads as a pile of independently-styled widgets rather than a coherent screen.

## Goal

Adopt a single, consistent "section grammar" for the body of the route viewer so that the screen scans cleanly and the user can predict where each piece of information lives.

## Non-Goals

- No change to the image viewer, polygon rendering, or hold-highlight logic.
- No change to the `RouteViewer` state-management, data loading, or `_loadImage` code.
- No change to the Grade block, meta rows (gym/sector/expiry), or description box — user wants to keep their current design.
- Workout Log's green date header (`APRIL 19, 2026`) and Description header promotion are **deferred**.
- No copy/text changes other than what's needed for the new timer-completion format.

## Decisions (from brainstorming)

1. **Visual style:** flat with thin dividers between sections. No cards wrapping whole sections.
2. **Section order:** unchanged from today — image → Hold Sequence → Slide-to-start → Workout Log → Verified Completers → Grade → Meta rows → Description.
3. **Section header style:** small caps, blue (`#0052D0`), letter-spacing ~1.5px, left side. Right side shows optional gray meta text (counts, state).
4. **Grade section and below:** unchanged.
5. **Timer completion precision:** `ActivityConfirmation` must show duration with 2-decimal seconds using a new l10n key.

## Section Grammar (applies to Hold Sequence, Workout Log, Verified Completers only)

A section is a column with this header + body structure. No card wrapping.

```
┌ padding 24/14 ─────────────────────────────────┐
│ [SECTION TITLE]             [right-meta text]  │   ← 10px/w700/letter-spacing 1.5/#0052D0 uppercase
│                                                │
│ <section body>                                 │
└────────────────────────────────────────────────┘
── 1px inset divider #ECEFF2 ──
```

- Section padding: `EdgeInsets.fromLTRB(24, 14, 24, 14)` (matches the other existing sections).
- Divider: `Container(height: 1, margin: EdgeInsets.symmetric(horizontal: 24), color: Color(0xFFECEFF2))` — **inset**, not edge-to-edge, keeping the 24px horizontal rhythm consistent with the existing Grade/Meta separators.
- Header row: `Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.baseline, children: [title, meta])` followed by `SizedBox(height: 8)` before the body.
- Title style: `TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF0052D0), letterSpacing: 1.5)` with the text uppercased (to match `CURRENT GRADE`).
- Meta style: `TextStyle(fontSize: 10, color: Color(0xFF6B7280), letterSpacing: 0.5)`.
- Meta can be omitted; when present it replaces ad-hoc trailing text (like `23 Holds Total`).

This grammar is the single visual contract every redesigned section must satisfy.

## Per-Section Changes

### Hold Sequence (`bouldering_route_holds.dart`, `endurance_route_holds.dart`)

- Replace current inline header with the unified small-caps header: title `HOLD SEQUENCE`, meta `{n} holds total` (localized).
- Thumbnails scroll **left-aligned** within the 24px horizontal padding. Remove whatever right-aligning the existing layout imposes on the strip.
- Wrap the existing horizontal-scroll strip unchanged below the header.
- Remove the extra `Container(padding: EdgeInsets.symmetric(vertical: 4), decoration: Border(top: ...))` wrapper in `route_viewer.dart` — the section's own padding + divider handle the gap now.

### Slide-to-start band (`activity_panel.dart`, shown via `ActivityPanel`)

- Keep ActivityPanel's internal behavior (slide/timer/confirmation state machine) exactly as-is.
- When the panel is showing the `SlideToStart` child, render it inside a plain band: `Padding(EdgeInsets.fromLTRB(24, 14, 24, 14))`, no header, bottom divider only (same inset divider as the section grammar).
- Timer and confirmation children keep their existing padding (they already render their own card chrome — see out-of-scope note below).

### Workout Log (`workout_log_panel.dart`)

- Remove the outer `Container` gray rounded card (`color: Color(0xFF...), borderRadius: 12`) that currently wraps the whole panel.
- Replace the existing inner `WORKOUT LOG` + `Completed Only` pill header with the unified header grammar:
  - Title `WORKOUT LOG` using the shared style.
  - Right meta becomes a tappable text button `Completed only ▾` styled as:
    `TextStyle(fontSize: 10, color: Color(0xFF0052D0), fontWeight: FontWeight.w600, letterSpacing: 0.5)` — same blue as the title but as a tap target toggling the filter (behavior unchanged).
- Stats row: keep existing 3-tile layout, but each tile becomes a light gray background chip (`Color(0xFFF9FAFB)`, `borderRadius: 8`, padding `EdgeInsets.symmetric(horizontal: 4, vertical: 10)`) so the stats still read as "one group" even without the surrounding card.
- Activity list rows: unchanged visually except that they now sit directly on the white page (no gray backdrop).
- The existing green date header (`APRIL 19, 2026` in green) stays as-is for this iteration (deferred).

### Verified Completers (`verified_completers_row.dart`)

- Replace the current header `${l10n.verifiedCompletersTitle} 🏅 · {count}` with the unified header grammar:
  - Title `VERIFIED COMPLETERS` (remove the 🏅 emoji so the small-caps rule isn't broken).
  - Right meta: the count (e.g., `0`, `3`).
- Empty-state body stays two lines (`verifiedCompletersEmpty` + `verifiedCompletersEmptyCta`) but reuses the section's 24px side padding; drop the internal `Padding(EdgeInsets.symmetric(horizontal: 24, vertical: 16))` wrapper that duplicates the section padding.
- Preserve the `_itemHeight` footprint guard so the section doesn't jump between empty/loading/populated states.

### Grade block / meta rows / description

- **Unchanged.** Keep the existing `Column` that renders `CURRENT GRADE` (48px `5.9` + right-side `NOVICE LEVEL` block + bottom thin divider), the three `_buildMetaRow` calls, and the gray `EFF1F2` description container.

## Timer Completion Precision

### Current behavior

`ActivityTimerPanel` (`activity_timer_panel.dart`) displays live elapsed time as `MM:SS.CC` using `_formatCentiseconds`. When the user taps the completion button, `ActivityConfirmation` is rendered with an `elapsed: Duration` prop and formats it via a local `_formatDuration` that returns `"${minutes}분 ${seconds}초"` or `"${seconds}초"` — dropping the milliseconds.

### Change

`ActivityConfirmation._formatDuration` must preserve 2-decimal seconds so the recorded time matches what the user saw on the timer.

- New format when minutes > 0: `"{minutes}분 {seconds}.{cc}초"` (e.g., `5분 46.32초`).
- New format when minutes == 0: `"{seconds}.{cc}초"` (e.g., `46.32초`).
- `{cc}` = `((elapsed.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0')`.

### Localization

- Add 4 new ARB keys (ko/en/ja/es) for the decimal duration formats so every locale renders naturally:
  - `activityDurationWithMinutesDecimal` — placeholders `{minutes}`, `{seconds}`, `{centiseconds}`.
  - `activityDurationSecondsDecimal` — placeholders `{seconds}`, `{centiseconds}`.
- Keep the existing `activityDurationFormat` key (used for the `statusText + duration` composition in `ActivityConfirmation`) untouched.
- `ActivityConfirmation` now calls one of the two new keys based on whether `elapsed.inMinutes > 0`, feeds the result into the existing `activityDurationFormat`.

### Locale copy

| Locale | With minutes | Seconds-only |
| --- | --- | --- |
| ko | `{minutes}분 {seconds}.{centiseconds}초` | `{seconds}.{centiseconds}초` |
| en | `{minutes}m {seconds}.{centiseconds}s` | `{seconds}.{centiseconds}s` |
| ja | `{minutes}分 {seconds}.{centiseconds}秒` | `{seconds}.{centiseconds}秒` |
| es | `{minutes}m {seconds}.{centiseconds}s` | `{seconds}.{centiseconds}s` |

## Visual Reference

The approved mockup is saved at `.superpowers/brainstorm/54874-1776858558/content/full-redesign.html`. Key invariants: left-aligned small-caps blue title, right-aligned gray meta, 24px horizontal padding, 1px `#ECEFF2` inset dividers, Grade block and below untouched.

## Implementation Notes

- Extract `lib/widgets/viewers/section_header.dart` — a single `SectionHeader` widget that renders the `[blue small-caps title] … [gray right-meta]` row. The three modified widgets (`verified_completers_row.dart`, `workout_log_panel.dart`, and the two hold-row widgets `bouldering_route_holds.dart` / `endurance_route_holds.dart`) all consume this widget so the header spec is guaranteed identical.
- **Divider ownership:** `route_viewer.dart` owns inter-section dividers. It interleaves a single reusable `SectionDivider` widget (1px `#ECEFF2`, horizontal 24px margin) between the body children (Hold Sequence → Slide band → Workout Log → Verified Completers). Individual section widgets **do not** paint their own bottom dividers. The Grade block's existing internal bottom border (`#ABADAE/0.2`) stays as-is.
- `route_viewer.dart` cleanup: remove the hold-list `Container` wrapper's `Border(top: ...)` decoration, delete the ad-hoc `Container(margin: horizontal 24, height: 1, color: grey.shade300)` before the Grade block, and drop the `SizedBox(height: 16)` that previously padded that manual divider. The new `SectionDivider` replaces both.
- `activity_confirmation.dart` change is isolated and local — update `_formatDuration` plus swap the l10n call.
- `activity_panel.dart` only needs to wrap the slide-child render in a `Padding(EdgeInsets.fromLTRB(24, 14, 24, 14))` (so its layout matches the other sections); the timer-child and confirmation-child renders are visually out-of-scope.

## Out of Scope / Deferred

- Workout Log internal `APRIL 19, 2026` green date header staying green (user chose to defer).
- Adding a `DESCRIPTION` small-caps header around the gray description box (deferred).
- Any change to the route image viewer, share handling, or the activity timer mid-flow UI.
- Timer confirmation card styling unification — user's ask was precision only; the confirmation card keeps its current green/gray success treatment.

## Success Criteria

- Opening a route and scrolling down the body shows every section using the same header pattern (left small-caps blue title, right gray meta), except Grade-and-below which remains as-is.
- The Workout Log no longer has a gray rounded container; its stats still visually group via three gray chips.
- Hold Sequence thumbnails start at the left 24px margin.
- Verified Completers header displays `VERIFIED COMPLETERS` (no emoji) with the count as right meta, and the empty state preserves section height.
- Slide-to-start appears as a band with thin dividers above and below, no card, no header.
- Finishing a climb shows completion time to 2-decimal seconds in all four locales.
- `flutter analyze` reports no issues.
