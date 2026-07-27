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
}
