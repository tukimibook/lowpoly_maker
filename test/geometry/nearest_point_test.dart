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
  });
}
