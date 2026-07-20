import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/services/tessellation_service.dart';

double _edgeLength(Offset a, Offset b) => (a - b).distance;

Iterable<(Offset, Offset)> _edgesOf(TessellationResult result) {
  return [
    for (final (a, b, c) in result.triangleIndices) ...[
      (result.points[a], result.points[b]),
      (result.points[b], result.points[c]),
      (result.points[c], result.points[a]),
    ],
  ];
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

  group('triangulate', () {
    test('a triangle already within maxEdge is triangulated as-is, with no new points', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(10, 0), Offset(5, 10)],
        maxEdge: 100,
        minEdge: 1,
      );

      final result = triangulate(request);

      expect(result.points, request.boundary);
      expect(result.triangleIndices, hasLength(1));
    });

    test('a square is split into 2 triangles when no edge needs subdividing', () {
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
    });

    test('subdivides until every edge is within maxEdge (plus small jitter slack)', () {
      // maxEdge/boundary-size ratio chosen with headroom: this naive
      // (unconstrained, batch-retriangulated) refinement can stall just
      // shy of full convergence for tighter ratios — that's exactly what
      // `tessellation_tuning_spike.dart` exists to explore per-shape.
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)],
        maxEdge: 70,
        minEdge: 1,
      );

      final result = triangulate(request);

      for (final (a, b) in _edgesOf(result)) {
        expect(_edgeLength(a, b), lessThanOrEqualTo(request.maxEdge + 2 * kTessellationJitter));
      }
      // Actually subdivided (started from 2 triangles).
      expect(result.triangleIndices.length, greaterThan(2));
    });

    test('never subdivides an edge into halves shorter than minEdge, even past maxEdge', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(200, 0), Offset(200, 200), Offset(0, 200)],
        maxEdge: 5,
        minEdge: 20,
      );

      final result = triangulate(request);

      // minEdge (20) blocks subdivision well before edges shrink to maxEdge
      // (5) — some over-maxEdge edges must remain, proving the guard fired
      // rather than the mesh happening to fully converge anyway.
      final hasOverMaxEdgeEdge = _edgesOf(
        result,
      ).any((edge) => _edgeLength(edge.$1, edge.$2) > request.maxEdge);
      expect(hasOverMaxEdgeEdge, isTrue);
    });

    test('kTessellationMaxIterations caps subdivision even when minEdge would not have blocked it', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(100, 0), Offset(50, 100)],
        maxEdge: 0.001,
        minEdge: 0.0001,
      );

      final result = triangulate(request);

      // Converging every edge below 0.001 from ~100-unit edges would need
      // far more than kTessellationMaxIterations halvings — some edge must
      // still exceed maxEdge, proving the iteration cap (not minEdge) is
      // what stopped the loop.
      final hasOverMaxEdgeEdge = _edgesOf(
        result,
      ).any((edge) => _edgeLength(edge.$1, edge.$2) > request.maxEdge);
      expect(hasOverMaxEdgeEdge, isTrue);
    });

    test('handles a non-convex (star-shaped) boundary without throwing', () {
      const request = TessellationRequest(
        boundary: [
          Offset(50, 0),
          Offset(63, 35),
          Offset(100, 35),
          Offset(70, 57),
          Offset(82, 95),
          Offset(50, 72),
          Offset(18, 95),
          Offset(30, 57),
          Offset(0, 35),
          Offset(37, 35),
        ],
        maxEdge: 40,
        minEdge: 5,
      );

      final result = triangulate(request);

      expect(result.triangleIndices, isNotEmpty);
      for (final (a, b, c) in result.triangleIndices) {
        expect({a, b, c}, hasLength(3)); // no degenerate triangle
      }
    });
  });
}
