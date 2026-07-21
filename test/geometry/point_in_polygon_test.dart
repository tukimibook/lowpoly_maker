import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/point_in_polygon.dart';

void main() {
  group('isPointInPolygon', () {
    const square = [
      Offset(0, 0),
      Offset(10, 0),
      Offset(10, 10),
      Offset(0, 10),
    ];

    test('returns true for a point clearly inside a convex square', () {
      expect(isPointInPolygon(const Offset(5, 5), square), isTrue);
    });

    test('returns false for a point clearly outside a convex square', () {
      expect(isPointInPolygon(const Offset(15, 5), square), isFalse);
      expect(isPointInPolygon(const Offset(-1, -1), square), isFalse);
    });

    test(
      'returns false for a point in the concave "bay" of an L-shape '
      '(inside the convex hull, outside the polygon)',
      () {
        // L-shape: outer box 0..10 with the top-right 5x5 quadrant cut out.
        // Point (7, 7) sits in that cut-out — inside the hull, outside the L.
        const lShape = [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 5),
          Offset(5, 5),
          Offset(5, 10),
          Offset(0, 10),
        ];

        expect(isPointInPolygon(const Offset(2, 2), lShape), isTrue);
        expect(isPointInPolygon(const Offset(7, 7), lShape), isFalse);
      },
    );

    test('returns false when the ring has fewer than 3 vertices', () {
      expect(isPointInPolygon(const Offset(0, 0), const []), isFalse);
      expect(isPointInPolygon(const Offset(0, 0), const [Offset(0, 0)]), isFalse);
      expect(
        isPointInPolygon(const Offset(0, 0), const [Offset(0, 0), Offset(1, 0)]),
        isFalse,
      );
    });
  });
}
