import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/geometry/nearest_point.dart';

void main() {
  group('findNearestPoint', () {
    test('returns the closest candidate within maxDistance', () {
      final result = findNearestPoint<String>(
        const Offset(0, 0),
        const [('far', Offset(100, 100)), ('near', Offset(3, 4))],
        maxDistance: 20,
      );

      expect(result, ('near', const Offset(3, 4)));
    });

    test('returns null when every candidate is farther than maxDistance', () {
      final result = findNearestPoint<String>(
        const Offset(0, 0),
        const [('a', Offset(100, 0)), ('b', Offset(0, 100))],
        maxDistance: 20,
      );

      expect(result, isNull);
    });

    test('returns null for an empty candidate list', () {
      final result = findNearestPoint<String>(
        const Offset(0, 0),
        const <(String, Offset)>[],
        maxDistance: 20,
      );

      expect(result, isNull);
    });

    test('a candidate exactly at maxDistance still counts (inclusive bound)', () {
      final result = findNearestPoint<String>(
        const Offset(0, 0),
        const [('edge', Offset(20, 0))],
        maxDistance: 20,
      );

      expect(result, ('edge', const Offset(20, 0)));
    });

    test('is agnostic to what the identifier type represents', () {
      final result = findNearestPoint<int>(
        const Offset(0, 0),
        const [(1, Offset(5, 0)), (2, Offset(1, 0))],
        maxDistance: 20,
      );

      expect(result, (2, const Offset(1, 0)));
    });

    group('preferredId tie-break (2026-07-16)', () {
      test(
        'without preferredId, an exact tie still falls back to "last one wins"',
        () {
          final result = findNearestPoint<String>(
            const Offset(0, 0),
            const [('a', Offset(10, 0)), ('b', Offset(10, 0))],
            maxDistance: 20,
          );

          expect(result, ('b', const Offset(10, 0)));
        },
      );

      test(
        'when preferredId is the earlier of two tied candidates, it still wins',
        () {
          final result = findNearestPoint<String>(
            const Offset(0, 0),
            const [('a', Offset(10, 0)), ('b', Offset(10, 0))],
            maxDistance: 20,
            preferredId: 'a',
          );

          expect(result, ('a', const Offset(10, 0)));
        },
      );

      test(
        'when preferredId is the later of two tied candidates, it wins '
        '(same outcome as the default, but for the reason of the preference)',
        () {
          final result = findNearestPoint<String>(
            const Offset(0, 0),
            const [('a', Offset(10, 0)), ('b', Offset(10, 0))],
            maxDistance: 20,
            preferredId: 'b',
          );

          expect(result, ('b', const Offset(10, 0)));
        },
      );

      test(
        'preferredId wins a three-way tie no matter its position among them',
        () {
          const candidates = [
            ('a', Offset(10, 0)),
            ('b', Offset(10, 0)),
            ('c', Offset(10, 0)),
          ];

          final result = findNearestPoint<String>(
            const Offset(0, 0),
            candidates,
            maxDistance: 20,
            preferredId: 'b',
          );

          expect(result, ('b', const Offset(10, 0)));
        },
      );

      test(
        'preferredId that is not one of the tied candidates has no effect '
        '(still falls back to "last one wins")',
        () {
          final result = findNearestPoint<String>(
            const Offset(0, 0),
            const [('a', Offset(10, 0)), ('b', Offset(10, 0))],
            maxDistance: 20,
            preferredId: 'not-a-candidate-at-all',
          );

          expect(result, ('b', const Offset(10, 0)));
        },
      );

      test(
        'preferredId does not override a genuinely closer, non-tied candidate',
        () {
          final result = findNearestPoint<String>(
            const Offset(0, 0),
            const [('far-but-preferred', Offset(15, 0)), ('near', Offset(1, 0))],
            maxDistance: 20,
            preferredId: 'far-but-preferred',
          );

          expect(result, ('near', const Offset(1, 0)));
        },
      );

      test('preferredId is irrelevant when there is only one candidate at all', () {
        final result = findNearestPoint<String>(
          const Offset(0, 0),
          const [('only', Offset(5, 0))],
          maxDistance: 20,
          preferredId: 'only',
        );

        expect(result, ('only', const Offset(5, 0)));
      });
    });
  });
}
