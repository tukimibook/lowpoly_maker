import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/vertex_hit_test.dart';

void main() {
  group('LinearVertexHitTest', () {
    test('returns null before rebuild is ever called', () {
      final hitTest = LinearVertexHitTest<String>();
      expect(hitTest.nearest(const Offset(0, 0), maxDistance: 100), isNull);
    });

    test('finds the nearest candidate within maxDistance after rebuild', () {
      final hitTest = LinearVertexHitTest<String>()
        ..rebuild(const [('far', Offset(100, 100)), ('near', Offset(3, 4))]);

      expect(
        hitTest.nearest(const Offset(0, 0), maxDistance: 20),
        ('near', const Offset(3, 4)),
      );
    });

    test('returns null when every candidate is farther than maxDistance', () {
      final hitTest = LinearVertexHitTest<String>()
        ..rebuild(const [('a', Offset(100, 0))]);

      expect(hitTest.nearest(const Offset(0, 0), maxDistance: 20), isNull);
    });

    test('forwards preferredId to break an exact tie, matching findNearestPoint', () {
      final hitTest = LinearVertexHitTest<String>()
        ..rebuild(const [('a', Offset(10, 0)), ('b', Offset(10, 0))]);

      expect(
        hitTest.nearest(const Offset(0, 0), maxDistance: 20, preferredId: 'a'),
        ('a', const Offset(10, 0)),
      );
    });

    test('a later rebuild fully replaces the previous candidate set', () {
      final hitTest = LinearVertexHitTest<String>()
        ..rebuild(const [('old', Offset(1, 0))]);
      hitTest.rebuild(const [('new', Offset(5, 0))]);

      expect(
        hitTest.nearest(const Offset(0, 0), maxDistance: 20),
        ('new', const Offset(5, 0)),
      );
    });

    test('rebuilding with an empty iterable clears prior candidates', () {
      final hitTest = LinearVertexHitTest<String>()
        ..rebuild(const [('a', Offset(1, 0))]);
      hitTest.rebuild(const []);

      expect(hitTest.nearest(const Offset(0, 0), maxDistance: 20), isNull);
    });

    test('is agnostic to what the identifier type represents', () {
      final hitTest = LinearVertexHitTest<int>()
        ..rebuild(const [(1, Offset(5, 0)), (2, Offset(1, 0))]);

      expect(hitTest.nearest(const Offset(0, 0), maxDistance: 20), (2, const Offset(1, 0)));
    });
  });
}
