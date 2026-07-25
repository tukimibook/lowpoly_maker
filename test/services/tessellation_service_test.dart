import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/point_in_polygon.dart';
import 'package:polygon_art_app/services/tessellation_service.dart';

Offset _centroid(List<Offset> points, (int, int, int) triangle) {
  final (i, j, k) = triangle;
  final a = points[i];
  final b = points[j];
  final c = points[k];
  return Offset((a.dx + b.dx + c.dx) / 3, (a.dy + b.dy + c.dy) / 3);
}

void main() {
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

  group('triangulate (coarse CDT)', () {
    test('a triangle is triangulated as a single triangle with no new points', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(10, 0), Offset(5, 10)],
        maxEdge: 100,
        minEdge: 1,
      );

      final result = triangulate(request);

      expect(result.points, request.boundary);
      expect(result.triangleIndices, hasLength(1));
    });

    test('a square is split into 2 triangles with no Steiner points', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(50, 0), Offset(50, 50), Offset(0, 50)],
        maxEdge: 100,
        minEdge: 1,
      );

      final result = triangulate(request);

      expect(result.points, request.boundary);
      expect(result.triangleIndices, hasLength(2));
    });

    test('the boundary ring is preserved as an exact, unmodified, in-order prefix of points', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(200, 0), Offset(200, 200), Offset(0, 200)],
        maxEdge: 30,
        minEdge: 5,
      );

      final result = triangulate(request);

      expect(result.points.sublist(0, request.boundary.length), request.boundary);
      // Coarse CDT: no Steiner points yet.
      expect(result.points, hasLength(request.boundary.length));
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
        expect(result.points, lShape);
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

    test('coarse CDT ignores maxEdge (no Steiner refinement yet)', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)],
        maxEdge: 10,
        minEdge: 1,
      );

      final result = triangulate(request);

      expect(result.points, request.boundary);
      expect(result.triangleIndices, hasLength(2));
    });
  });
}
