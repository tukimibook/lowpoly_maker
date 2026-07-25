import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/point_in_polygon.dart';
import 'package:polygon_art_app/services/tessellation_service.dart';

double _edgeLength(Offset a, Offset b) => (a - b).distance;

Offset _centroid(List<Offset> points, (int, int, int) triangle) {
  final (i, j, k) = triangle;
  final a = points[i];
  final b = points[j];
  final c = points[k];
  return Offset((a.dx + b.dx + c.dx) / 3, (a.dy + b.dy + c.dy) / 3);
}

double _distToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.distanceSquared;
  if (len2 == 0) return (p - a).distance;
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
  t = t.clamp(0.0, 1.0);
  return (p - Offset(a.dx + t * ab.dx, a.dy + t * ab.dy)).distance;
}

double _minDistToRingEdges(Offset p, List<Offset> ring) {
  var best = double.infinity;
  for (var i = 0; i < ring.length; i++) {
    final d = _distToSegment(p, ring[i], ring[(i + 1) % ring.length]);
    if (d < best) best = d;
  }
  return best;
}

/// Extras that are deep inside the ring (true interior Steiners), excluding
/// edge-split inserts that may sit just inside after micro-jitter.
List<Offset> _deepInteriorExtras(
  TessellationResult result,
  List<Offset> boundary, {
  required double minEdge,
}) {
  return [
    for (final p in result.points.skip(boundary.length))
      if (isPointInPolygon(p, boundary) &&
          _minDistToRingEdges(p, boundary) >= minEdge)
        p,
  ];
}

void main() {
  group('defaults', () {
    test('minEdge is ratio-linked to maxEdge (1:8)', () {
      expect(kTessellationDefaultMaxEdge, 120.0);
      expect(kTessellationMinToMaxEdgeRatio, 8.0);
      expect(
        kTessellationDefaultMinEdge,
        kTessellationDefaultMaxEdge / kTessellationMinToMaxEdgeRatio,
      );
      expect(kTessellationDefaultMinEdge, 15.0);
    });
  });

  group('TessellationRequest', () {
    test('holds the boundary, maxEdge, and minEdge it was constructed with', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
        maxEdge: 50,
        minEdge: 20,
      );

      expect(request.boundary, [const Offset(0, 0), const Offset(10, 0), const Offset(10, 10)]);
      expect(request.maxEdge, 50);
      expect(request.minEdge, 20);
    });
  });

  group('TessellationResult', () {
    test('holds the points and triangle indices it was constructed with', () {
      const result = TessellationResult(
        points: [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
        triangleIndices: [(0, 1, 2)],
      );

      expect(result.points, hasLength(3));
      expect(result.triangleIndices, [(0, 1, 2)]);
    });
  });

  group('triangulate (CDT + edge-split + Steiner)', () {
    test('a triangle with large maxEdge needs no extra points', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(10, 0), Offset(5, 10)],
        maxEdge: 100,
        minEdge: 1,
      );

      final result = triangulate(request);

      expect(result.points, request.boundary);
      expect(result.triangleIndices, hasLength(1));
    });

    test('a square with large maxEdge is two triangles and no extras', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(50, 0), Offset(50, 50), Offset(0, 50)],
        maxEdge: 100,
        minEdge: 1,
      );

      final result = triangulate(request);

      expect(result.points, request.boundary);
      expect(result.triangleIndices, hasLength(2));
    });

    test('the boundary ring is preserved as an exact, unmodified, in-order prefix', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(200, 0), Offset(200, 200), Offset(0, 200)],
        maxEdge: 30,
        minEdge: 5,
      );

      final result = triangulate(request);

      expect(result.points.sublist(0, request.boundary.length), request.boundary);
      expect(result.points.length, greaterThan(request.boundary.length));
    });

    test('densifies with edge-splits and/or Steiners when maxEdge is small', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)],
        maxEdge: 30,
        minEdge: 5,
      );

      final result = triangulate(request);

      expect(result.points.length, greaterThan(request.boundary.length));
      expect(result.triangleIndices.length, greaterThan(2));

      final interiors = _deepInteriorExtras(
        result,
        request.boundary,
        minEdge: request.minEdge,
      );
      for (final s in interiors) {
        for (final v in request.boundary) {
          expect(_edgeLength(s, v), greaterThanOrEqualTo(request.minEdge));
        }
      }
    });

    test('minEdge keeps interior Steiners from clustering too tightly', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)],
        maxEdge: 20,
        minEdge: 25,
      );

      final result = triangulate(request);
      final interiors = _deepInteriorExtras(
        result,
        request.boundary,
        minEdge: request.minEdge,
      );

      for (var i = 0; i < interiors.length; i++) {
        for (var j = i + 1; j < interiors.length; j++) {
          expect(
            _edgeLength(interiors[i], interiors[j]),
            greaterThanOrEqualTo(request.minEdge),
          );
        }
      }
    });

    test('handles a non-convex simple (arrow) boundary without throwing', () {
      const request = TessellationRequest(
        boundary: [
          Offset(0, 40),
          Offset(60, 40),
          Offset(60, 20),
          Offset(100, 50),
          Offset(60, 80),
          Offset(60, 60),
          Offset(0, 60),
        ],
        maxEdge: 40,
        minEdge: 5,
      );

      final result = triangulate(request);

      expect(result.triangleIndices, isNotEmpty);
      for (final (a, b, c) in result.triangleIndices) {
        expect({a, b, c}, hasLength(3));
      }
      for (final triangle in result.triangleIndices) {
        expect(
          isPointInPolygon(_centroid(result.points, triangle), request.boundary),
          isTrue,
        );
      }
    });

    test(
      'keeps only interior triangles for a concave (L-shaped) boundary',
      () {
        const lShape = [
          Offset(0, 0),
          Offset(100, 0),
          Offset(100, 50),
          Offset(50, 50),
          Offset(50, 100),
          Offset(0, 100),
        ];
        const request = TessellationRequest(
          boundary: lShape,
          maxEdge: 200,
          minEdge: 1,
        );

        final result = triangulate(request);

        expect(result.triangleIndices, isNotEmpty);
        expect(result.points.sublist(0, lShape.length), lShape);
        for (final triangle in result.triangleIndices) {
          expect(
            isPointInPolygon(_centroid(result.points, triangle), lShape),
            isTrue,
          );
        }
        expect(isPointInPolygon(const Offset(75, 75), lShape), isFalse);
        for (final triangle in result.triangleIndices) {
          final centroid = _centroid(result.points, triangle);
          expect(centroid.dx > 50 && centroid.dy > 50, isFalse);
        }
      },
    );

    test('densified L-shape still drops exterior bay triangles', () {
      const lShape = [
        Offset(0, 0),
        Offset(200, 0),
        Offset(200, 100),
        Offset(100, 100),
        Offset(100, 200),
        Offset(0, 200),
      ];
      const request = TessellationRequest(
        boundary: lShape,
        maxEdge: 40,
        minEdge: 8,
      );

      final result = triangulate(request);

      expect(result.triangleIndices, isNotEmpty);
      expect(result.points.length, greaterThan(lShape.length));
      for (final triangle in result.triangleIndices) {
        expect(
          isPointInPolygon(_centroid(result.points, triangle), lShape),
          isTrue,
        );
      }
    });
  });
}
