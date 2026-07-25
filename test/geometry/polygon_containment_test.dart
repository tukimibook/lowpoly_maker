import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/polygon_containment.dart';

void main() {
  group('ringBounds / ringAbsArea', () {
    test('ringAbsArea of a 10×10 square is 100', () {
      const square = [
        Offset(0, 0),
        Offset(10, 0),
        Offset(10, 10),
        Offset(0, 10),
      ];
      expect(ringAbsArea(square), closeTo(100, 1e-9));
    });

    test('boundsContainsBounds rejects a box that sticks out', () {
      final outer = ringBounds(const [
        Offset(0, 0),
        Offset(10, 0),
        Offset(10, 10),
        Offset(0, 10),
      ]);
      final innerOk = ringBounds(const [
        Offset(2, 2),
        Offset(4, 2),
        Offset(4, 4),
        Offset(2, 4),
      ]);
      final innerOut = ringBounds(const [
        Offset(8, 8),
        Offset(12, 8),
        Offset(12, 12),
        Offset(8, 12),
      ]);
      expect(boundsContainsBounds(outer, innerOk), isTrue);
      expect(boundsContainsBounds(outer, innerOut), isFalse);
    });
  });

  group('isRingFullyContained', () {
    const outer = [
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, 100),
      Offset(0, 100),
    ];

    test('accepts a strictly interior smaller square', () {
      const inner = [
        Offset(20, 20),
        Offset(40, 20),
        Offset(40, 40),
        Offset(20, 40),
      ];
      expect(isRingFullyContained(outer: outer, inner: inner), isTrue);
    });

    test('rejects when areas are equal or inner is larger (area filter)', () {
      expect(isRingFullyContained(outer: outer, inner: outer), isFalse);
      const huge = [
        Offset(-10, -10),
        Offset(200, -10),
        Offset(200, 200),
        Offset(-10, 200),
      ];
      expect(isRingFullyContained(outer: outer, inner: huge), isFalse);
    });

    test('rejects AABB that is not contained (AABB filter)', () {
      const stickingOut = [
        Offset(80, 80),
        Offset(120, 80),
        Offset(120, 120),
        Offset(80, 120),
      ];
      expect(isRingFullyContained(outer: outer, inner: stickingOut), isFalse);
    });

    test('rejects partial overlap (fail-safe)', () {
      // Half inside the outer square, half outside.
      const partial = [
        Offset(80, 40),
        Offset(120, 40),
        Offset(120, 60),
        Offset(80, 60),
      ];
      expect(isRingFullyContained(outer: outer, inner: partial), isFalse);
    });

    test('rejects rings that only touch the outer boundary', () {
      // Shares the left edge of the outer square — vertices on boundary
      // are outside for isPointInPolygon.
      const touching = [
        Offset(0, 20),
        Offset(20, 20),
        Offset(20, 40),
        Offset(0, 40),
      ];
      expect(isRingFullyContained(outer: outer, inner: touching), isFalse);
    });

    test('rejects when edges properly cross even if some vertices are inside', () {
      // A thin diagonal slash that crosses the outer (bow-like relative).
      const crossing = [
        Offset(50, -10),
        Offset(60, -10),
        Offset(60, 110),
        Offset(50, 110),
      ];
      expect(isRingFullyContained(outer: outer, inner: crossing), isFalse);
    });
  });

  group('collectFullyContainedHoleRings', () {
    test('keeps only fully contained candidates, in input order', () {
      const outer = [
        Offset(0, 0),
        Offset(100, 0),
        Offset(100, 100),
        Offset(0, 100),
      ];
      const holeA = [
        Offset(10, 10),
        Offset(20, 10),
        Offset(20, 20),
        Offset(10, 20),
      ];
      const holeB = [
        Offset(70, 70),
        Offset(80, 70),
        Offset(80, 80),
        Offset(70, 80),
      ];
      const partial = [
        Offset(90, 40),
        Offset(110, 40),
        Offset(110, 50),
        Offset(90, 50),
      ];

      final holes = collectFullyContainedHoleRings(
        outer: outer,
        candidates: [holeA, partial, holeB],
      );

      expect(holes, [holeA, holeB]);
    });
  });
}
