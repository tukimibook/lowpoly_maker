import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/self_intersection.dart';

void main() {
  group('segmentsIntersect', () {
    test('detects two segments properly crossing each other', () {
      expect(
        segmentsIntersect(
          const Offset(0, 0),
          const Offset(10, 10),
          const Offset(0, 10),
          const Offset(10, 0),
        ),
        isTrue,
      );
    });

    test('returns false for two disjoint parallel segments', () {
      expect(
        segmentsIntersect(
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(0, 5),
          const Offset(10, 5),
        ),
        isFalse,
      );
    });

    test('returns false for two segments that come close but do not touch', () {
      expect(
        segmentsIntersect(
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(5, 1),
          const Offset(5, 10),
        ),
        isFalse,
      );
    });

    test('treats a shared endpoint as an intersection', () {
      expect(
        segmentsIntersect(
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(10, 0),
          const Offset(10, 10),
        ),
        isTrue,
      );
    });

    test('detects a collinear-overlap touch (endpoint lying exactly on the other segment)', () {
      expect(
        segmentsIntersect(
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(5, 0),
          const Offset(5, 10),
        ),
        isTrue,
      );
    });

    test('returns false for fully collinear, non-overlapping segments', () {
      expect(
        segmentsIntersect(
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(20, 0),
          const Offset(30, 0),
        ),
        isFalse,
      );
    });
  });

  group('isSelfIntersectingRing', () {
    test('returns false for a simple triangle', () {
      expect(
        isSelfIntersectingRing(const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(5, 10),
        ]),
        isFalse,
      );
    });

    test('returns false for a simple convex quadrilateral', () {
      expect(
        isSelfIntersectingRing(const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 10),
          Offset(0, 10),
        ]),
        isFalse,
      );
    });

    test('detects a bowtie / figure-8 quadrilateral (opposite edges crossing)', () {
      expect(
        isSelfIntersectingRing(const [
          Offset(0, 0),
          Offset(10, 10),
          Offset(10, 0),
          Offset(0, 10),
        ]),
        isTrue,
      );
    });

    test('does not flag adjacent edges as intersecting (shared ring vertex is expected)', () {
      expect(
        isSelfIntersectingRing(const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 10),
          Offset(0, 10),
          Offset(0, 5),
        ]),
        isFalse,
      );
    });

    test('does not flag the wrap-around adjacency between the last and first edge', () {
      // A simple pentagon where edge (last->first) is adjacent to edge (first->second).
      expect(
        isSelfIntersectingRing(const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 10),
          Offset(5, 15),
          Offset(0, 10),
        ]),
        isFalse,
      );
    });

    test('returns false for fewer than 4 points (a triangle can never self-intersect)', () {
      expect(isSelfIntersectingRing(const [Offset(0, 0), Offset(1, 0)]), isFalse);
      expect(isSelfIntersectingRing(const []), isFalse);
    });

    test('detects a non-adjacent edge crossing in a larger polygon', () {
      expect(
        isSelfIntersectingRing(const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 10),
          Offset(0, 10),
          Offset(5, -5),
        ]),
        isTrue,
      );
    });
  });
}
