import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/geometry/vendor/poly2tri/poly2tri.dart';

void main() {
  group('orient2d', () {
    test('detects CCW, CW, and collinear', () {
      final a = P2tPoint(0, 0);
      final b = P2tPoint(1, 0);
      final cCcw = P2tPoint(0, 1);
      final cCw = P2tPoint(0, -1);
      final cCol = P2tPoint(2, 0);

      expect(orient2d(a, b, cCcw), P2tOrientation.ccw);
      expect(orient2d(a, b, cCw), P2tOrientation.cw);
      expect(orient2d(a, b, cCol), P2tOrientation.collinear);
    });
  });

  group('inCircle', () {
    test('point inside unit circumcircle of right triangle', () {
      // Right triangle (0,0)-(1,0)-(0,1); circumcircle center (0.5,0.5) r=√0.5
      final pa = P2tPoint(0, 0);
      final pb = P2tPoint(1, 0);
      final pc = P2tPoint(0, 1);
      final inside = P2tPoint(0.5, 0.4);
      final outside = P2tPoint(2, 2);

      expect(inCircle(pa, pb, pc, inside), isTrue);
      expect(inCircle(pa, pb, pc, outside), isFalse);
    });
  });

  group('identity', () {
    test('same coordinates are distinct points; Edge rejects duplicates', () {
      final a = P2tPoint(1, 1);
      final b = P2tPoint(1, 1);
      expect(identical(a, b), isFalse);
      expect(a.coordinatesEqual(b), isTrue);

      final lo = P2tPoint(0, 0);
      final hi = P2tPoint(0, 2);
      final edge = P2tEdge(hi, lo);
      expect(identical(edge.p, lo), isTrue);
      expect(identical(edge.q, hi), isTrue);
      expect(hi.edgeList, contains(edge));

      expect(() => P2tEdge(a, b), throwsArgumentError);
    });

    test('Triangle.containsPoint uses reference identity', () {
      final a = P2tPoint(0, 0);
      final b = P2tPoint(1, 0);
      final c = P2tPoint(0, 1);
      final twin = P2tPoint(0, 0);
      final t = P2tTriangle(a, b, c);

      expect(t.containsPoint(a), isTrue);
      expect(t.containsPoint(twin), isFalse);
    });
  });
}
