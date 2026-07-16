import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/edge_midpoint.dart';

void main() {
  group('edgeMidpoint', () {
    test('returns the exact halfway point between two horizontally offset points', () {
      expect(edgeMidpoint(const Offset(0, 0), const Offset(100, 0)), const Offset(50, 0));
    });

    test('returns the exact halfway point for a diagonal segment', () {
      expect(edgeMidpoint(const Offset(0, 0), const Offset(100, 200)), const Offset(50, 100));
    });

    test('is symmetric: order of start/end does not matter', () {
      const a = Offset(10, 20);
      const b = Offset(90, 140);
      expect(edgeMidpoint(a, b), edgeMidpoint(b, a));
    });

    test('a degenerate (zero-length) segment returns that same point', () {
      const point = Offset(42, 7);
      expect(edgeMidpoint(point, point), point);
    });

    test('handles negative coordinates correctly', () {
      expect(
        edgeMidpoint(const Offset(-50, -50), const Offset(50, 50)),
        const Offset(0, 0),
      );
    });
  });
}
