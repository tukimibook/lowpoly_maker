import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/polygon_hit_test.dart';

void main() {
  group('pointInRingWithAabb', () {
    const square = [
      Offset(0, 0),
      Offset(10, 0),
      Offset(10, 10),
      Offset(0, 10),
    ];

    test('rejects points outside the AABB without needing a tight interior', () {
      expect(pointInRingWithAabb(const Offset(-1, 5), square), isFalse);
      expect(pointInRingWithAabb(const Offset(11, 5), square), isFalse);
      expect(pointInRingWithAabb(const Offset(5, -1), square), isFalse);
      expect(pointInRingWithAabb(const Offset(5, 11), square), isFalse);
    });

    test('accepts a clear interior point', () {
      expect(pointInRingWithAabb(const Offset(5, 5), square), isTrue);
    });

    test('returns false for fewer than 3 vertices', () {
      expect(
        pointInRingWithAabb(const Offset(1, 1), const [Offset(0, 0), Offset(2, 0)]),
        isFalse,
      );
    });
  });

  group('findTopmostPolygonIdAt', () {
    test('returns null when no candidate contains the point', () {
      expect(
        findTopmostPolygonIdAt(
          const Offset(50, 50),
          candidates: const [
            (id: 'a', ring: [Offset(0, 0), Offset(10, 0), Offset(0, 10)]),
          ],
        ),
        isNull,
      );
    });

    test('prefers the later (front-most) candidate on overlap', () {
      // Back square [0,10]² and front square [5,15]² — tap (7,7) is in both.
      const back = [
        Offset(0, 0),
        Offset(10, 0),
        Offset(10, 10),
        Offset(0, 10),
      ];
      const front = [
        Offset(5, 5),
        Offset(15, 5),
        Offset(15, 15),
        Offset(5, 15),
      ];

      expect(
        findTopmostPolygonIdAt(
          const Offset(7, 7),
          candidates: const [
            (id: 'back', ring: back),
            (id: 'front', ring: front),
          ],
        ),
        'front',
      );

      // Only the back square covers (2,2).
      expect(
        findTopmostPolygonIdAt(
          const Offset(2, 2),
          candidates: const [
            (id: 'back', ring: back),
            (id: 'front', ring: front),
          ],
        ),
        'back',
      );
    });
  });

  group('findNearestRingEdgeIndex', () {
    const square = [
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, 100),
      Offset(0, 100),
    ];

    test('returns null for fewer than 2 vertices', () {
      expect(
        findNearestRingEdgeIndex(
          const Offset(1, 0),
          const [Offset(0, 0)],
          tolerance: 10,
        ),
        isNull,
      );
    });

    test('returns null when every edge is beyond tolerance', () {
      expect(
        findNearestRingEdgeIndex(
          const Offset(50, 50),
          square,
          tolerance: 10,
        ),
        isNull,
      );
    });

    test('hits the bottom edge (index 0) near its midpoint', () {
      expect(
        findNearestRingEdgeIndex(
          const Offset(50, 5),
          square,
          tolerance: 10,
        ),
        0,
      );
    });

    test('hits the right edge (index 1)', () {
      expect(
        findNearestRingEdgeIndex(
          const Offset(98, 50),
          square,
          tolerance: 10,
        ),
        1,
      );
    });

    test('hits the closing left edge (index 3)', () {
      expect(
        findNearestRingEdgeIndex(
          const Offset(3, 50),
          square,
          tolerance: 10,
        ),
        3,
      );
    });

    test('on a corner within tolerance, prefers the lower ringIndex', () {
      // Exactly at (0,0): distance 0 to both edge 0 and edge 3.
      expect(
        findNearestRingEdgeIndex(
          const Offset(0, 0),
          square,
          tolerance: 10,
        ),
        0,
      );
    });

    test('accepts a point exactly on the tolerance boundary', () {
      expect(
        findNearestRingEdgeIndex(
          const Offset(50, 10),
          square,
          tolerance: 10,
        ),
        0,
      );
    });
  });
}
