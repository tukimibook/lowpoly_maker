import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/geometry/vendor/poly2tri/poly2tri.dart';

void main() {
  group('CDT — simple square (no hole)', () {
    test('produces two triangles covering the square', () {
      final a = P2tPoint(0, 0);
      final b = P2tPoint(100, 0);
      final c = P2tPoint(100, 100);
      final d = P2tPoint(0, 100);

      final cdt = CDT([a, b, c, d]);
      cdt.triangulate();
      final triangles = cdt.getTriangles();

      expect(triangles, hasLength(2));

      final used = <P2tPoint>{};
      for (final t in triangles) {
        used.add(t.getPoint(0));
        used.add(t.getPoint(1));
        used.add(t.getPoint(2));
        expect(_triangleArea(t), greaterThan(0));
      }
      expect(used, unorderedEquals(<P2tPoint>[a, b, c, d]));
    });
  });

  group('CDT — square with fully contained square hole', () {
    test('respects hole constraints and leaves hole empty', () {
      final outer = [
        P2tPoint(0, 0),
        P2tPoint(100, 0),
        P2tPoint(100, 100),
        P2tPoint(0, 100),
      ];
      // Opposite winding relative to outer (common poly2tri convention).
      final hole = [
        P2tPoint(25, 25),
        P2tPoint(25, 75),
        P2tPoint(75, 75),
        P2tPoint(75, 25),
      ];

      final cdt = CDT(outer);
      cdt.addHole(hole);
      cdt.triangulate();
      final triangles = cdt.getTriangles();

      // Rectangle-with-rectangular-hole → 8 triangles.
      expect(triangles, hasLength(8));

      final meshEdges = <_EdgeKey>{};
      for (final t in triangles) {
        final p0 = t.getPoint(0);
        final p1 = t.getPoint(1);
        final p2 = t.getPoint(2);
        meshEdges.add(_EdgeKey(p0, p1));
        meshEdges.add(_EdgeKey(p1, p2));
        meshEdges.add(_EdgeKey(p2, p0));

        final cx = (p0.x + p1.x + p2.x) / 3;
        final cy = (p0.y + p1.y + p2.y) / 3;
        expect(
          _pointInRing(cx, cy, hole),
          isFalse,
          reason: 'triangle centroid ($cx,$cy) must not lie inside the hole',
        );
        expect(_triangleArea(t), greaterThan(0));
      }

      // Every hole boundary edge must appear in the mesh (constrained).
      for (var i = 0; i < hole.length; i++) {
        final e = _EdgeKey(hole[i], hole[(i + 1) % hole.length]);
        expect(meshEdges.contains(e), isTrue, reason: 'missing hole edge $e');
      }

      // Outer boundary edges must also be present.
      for (var i = 0; i < outer.length; i++) {
        final e = _EdgeKey(outer[i], outer[(i + 1) % outer.length]);
        expect(meshEdges.contains(e), isTrue, reason: 'missing outer edge $e');
      }
    });
  });
}

double _triangleArea(P2tTriangle t) {
  final a = t.getPoint(0);
  final b = t.getPoint(1);
  final c = t.getPoint(2);
  return ((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)).abs() * 0.5;
}

/// Even-odd point-in-polygon for a closed ring (not needing dart:ui).
bool _pointInRing(double x, double y, List<P2tPoint> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i].x;
    final yi = ring[i].y;
    final xj = ring[j].x;
    final yj = ring[j].y;
    final intersect =
        ((yi > y) != (yj > y)) &&
        (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

/// Undirected edge key by point **reference** identity.
class _EdgeKey {
  _EdgeKey(P2tPoint a, P2tPoint b)
      : p = identical(a, b)
            ? a
            : (identityHashCode(a) <= identityHashCode(b) ? a : b),
        q = identical(a, b)
            ? b
            : (identityHashCode(a) <= identityHashCode(b) ? b : a);

  final P2tPoint p;
  final P2tPoint q;

  @override
  bool operator ==(Object other) =>
      other is _EdgeKey && identical(p, other.p) && identical(q, other.q);

  @override
  int get hashCode => Object.hash(identityHashCode(p), identityHashCode(q));

  @override
  String toString() => 'Edge($p-$q)';
}
