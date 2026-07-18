import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/geometry/trace_point_generator.dart';

void main() {
  group('generateTracePoints', () {
    test('a straight 100px path at 25px spacing yields 5 evenly spaced points', () {
      final result = generateTracePoints(
        const [Offset(0, 0), Offset(100, 0)],
        spacing: 25,
      );

      expect(result, [
        const Offset(0, 0),
        const Offset(25, 0),
        const Offset(50, 0),
        const Offset(75, 0),
        const Offset(100, 0),
      ]);
    });

    test(
      'preserves the exact start and end even when the final leftover '
      'segment is shorter than the spacing',
      () {
        final result = generateTracePoints(
          const [Offset(0, 0), Offset(90, 0)],
          spacing: 25,
        );

        expect(result.first, const Offset(0, 0));
        expect(result.last, const Offset(90, 0));
        // 0, 25, 50, 75, then the true (shorter) tail back to 90.
        expect(result, hasLength(5));
        expect(result[3], const Offset(75, 0));
      },
    );

    test('resamples across several raw segments as one continuous path, not per-segment', () {
      // An "L" shape: right 60px, then down 60px — a dense raw path (as a
      // real gesture would report), resampled at 40px spacing regardless of
      // where the original segment boundaries fell.
      final result = generateTracePoints(
        const [
          Offset(0, 0),
          Offset(20, 0),
          Offset(40, 0),
          Offset(60, 0),
          Offset(60, 20),
          Offset(60, 40),
          Offset(60, 60),
        ],
        spacing: 40,
      );

      expect(result, [
        const Offset(0, 0),
        const Offset(40, 0),
        const Offset(60, 20),
        const Offset(60, 60),
      ]);
    });

    test('a short stroke shorter than one spacing still keeps its start and end', () {
      final result = generateTracePoints(
        const [Offset(0, 0), Offset(10, 0)],
        spacing: 40,
      );

      expect(result, [const Offset(0, 0), const Offset(10, 0)]);
    });

    test('a path that doubles back on itself is resampled along its full walked length', () {
      // Right 100px, then back left 100px: total arc length 200px, not the
      // net displacement (0).
      final result = generateTracePoints(
        const [Offset(0, 0), Offset(100, 0), Offset(0, 0)],
        spacing: 50,
      );

      expect(result, [
        const Offset(0, 0),
        const Offset(50, 0),
        const Offset(100, 0),
        const Offset(50, 0),
        const Offset(0, 0),
      ]);
    });

    test('zero-length (paused-finger) segments contribute no extra samples', () {
      final result = generateTracePoints(
        const [
          Offset(0, 0),
          Offset(0, 0),
          Offset(0, 0),
          Offset(50, 0),
        ],
        spacing: 50,
      );

      expect(result, [const Offset(0, 0), const Offset(50, 0)]);
    });

    test('fewer than 2 raw points returns a copy of the input unchanged', () {
      expect(generateTracePoints(const [], spacing: 10), isEmpty);
      expect(
        generateTracePoints(const [Offset(5, 5)], spacing: 10),
        [const Offset(5, 5)],
      );
    });

    test('every point in the raw path being identical collapses to a single point', () {
      final result = generateTracePoints(
        const [Offset(3, 3), Offset(3, 3), Offset(3, 3)],
        spacing: 10,
      );

      expect(result, [const Offset(3, 3)]);
    });

    test('asserts spacing must be positive', () {
      expect(
        () => generateTracePoints(const [Offset(0, 0), Offset(1, 1)], spacing: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
