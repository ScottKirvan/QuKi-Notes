import 'package:flutter_test/flutter_test.dart';
import 'package:quki_notes/shared/relative_time.dart';

void main() {
  final now = DateTime(2026, 6, 9, 12, 0, 0); // fixed reference point

  group('relativeTime', () {
    test('returns "just now" for timestamps less than 1 minute ago', () {
      final dt = now.subtract(const Duration(seconds: 30));
      expect(relativeTime(dt, now: now), 'just now');
    });

    test('returns "just now" for the exact same timestamp', () {
      expect(relativeTime(now, now: now), 'just now');
    });

    test('returns minutes ago for 1–59 min ago', () {
      expect(relativeTime(now.subtract(const Duration(minutes: 1)), now: now),
          '1 min ago');
      expect(relativeTime(now.subtract(const Duration(minutes: 45)), now: now),
          '45 min ago');
      expect(relativeTime(now.subtract(const Duration(minutes: 59)), now: now),
          '59 min ago');
    });

    test('returns hours ago for 1–23 h ago', () {
      expect(relativeTime(now.subtract(const Duration(hours: 1)), now: now),
          '1h ago');
      expect(relativeTime(now.subtract(const Duration(hours: 23)), now: now),
          '23h ago');
    });

    test('returns "Yesterday" exactly 1 day ago', () {
      expect(relativeTime(now.subtract(const Duration(days: 1)), now: now),
          'Yesterday');
    });

    test('returns abbreviated month + day for 2–6 days ago same year', () {
      final dt = now.subtract(const Duration(days: 3));
      expect(relativeTime(dt, now: now), 'Jun 6');
    });

    test('returns abbreviated month + day + year for a different year', () {
      final dt = DateTime(2025, 3, 15);
      expect(relativeTime(dt, now: now), 'Mar 15, 2025');
    });

    test('returns month + day without year when same year as reference', () {
      final dt = DateTime(2026, 1, 1);
      expect(relativeTime(dt, now: now), 'Jan 1');
    });
  });
}
