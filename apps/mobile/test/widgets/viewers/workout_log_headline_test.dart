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
      expect(selectHeadlineVariant(5, 3), HeadlineVariant.streakSmall);
    });
  });

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
      expect(formatDurationHuman(1.999), '00:01.99');
    });
  });
}
