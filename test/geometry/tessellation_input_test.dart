import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/tessellation_input.dart';
import 'package:polygon_art_app/models/vertex.dart';

Vertex _vertex(String id, Offset position) => Vertex(id: id, position: position);

void main() {
  group('weldCoincidentRingVertices', () {
    test('leaves a ring with no coincident positions unchanged', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(10, 0)),
        'c': _vertex('c', const Offset(5, 10)),
      };
      expect(
        weldCoincidentRingVertices(const ['a', 'b', 'c'], vertices: vertices),
        ['a', 'b', 'c'],
      );
    });

    test('replaces a later ID with the earlier one when they sit at the exact same position', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(10, 0)),
        'c': _vertex('c', const Offset(5, 10)),
        'd': _vertex('d', const Offset(0, 0)), // same position as 'a'
      };
      expect(
        weldCoincidentRingVertices(const ['a', 'b', 'c', 'd'], vertices: vertices),
        ['a', 'b', 'c', 'a'],
      );
    });

    test('welds every ID sharing a position, not just one pair', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(0, 0)),
        'c': _vertex('c', const Offset(0, 0)),
      };
      expect(
        weldCoincidentRingVertices(const ['a', 'b', 'c'], vertices: vertices),
        ['a', 'a', 'a'],
      );
    });
  });

  group('sanitizeTessellationBoundary', () {
    Map<String, Vertex> squareVertices() => {
      'a': _vertex('a', const Offset(0, 0)),
      'b': _vertex('b', const Offset(10, 0)),
      'c': _vertex('c', const Offset(10, 10)),
      'd': _vertex('d', const Offset(0, 10)),
    };

    test('accepts a simple, already-clean ring unchanged', () {
      final result = sanitizeTessellationBoundary(
        const ['a', 'b', 'c', 'd'],
        vertices: squareVertices(),
      );

      expect(result, isA<TessellationBoundaryOk>());
      expect((result as TessellationBoundaryOk).vertexIds, ['a', 'b', 'c', 'd']);
    });

    test('welds a coincident-but-unwelded vertex and accepts the result', () {
      final vertices = {
        ...squareVertices(),
        'e': _vertex('e', const Offset(0, 0)), // coincides with 'a'
      };
      // Ring a-b-c-d-e: 'e' sits exactly on 'a', collapsing the ring back
      // down to a clean square once welded + consecutive-collapsed.
      final result = sanitizeTessellationBoundary(
        const ['a', 'b', 'c', 'd', 'e'],
        vertices: vertices,
      );

      expect(result, isA<TessellationBoundaryOk>());
      expect((result as TessellationBoundaryOk).vertexIds, ['a', 'b', 'c', 'd']);
    });

    test('rejects as tooFewVertices when welding collapses below the minimum', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(10, 0)),
        'c': _vertex('c', const Offset(0, 0)), // coincides with 'a'
      };
      final result = sanitizeTessellationBoundary(
        const ['a', 'b', 'c'],
        vertices: vertices,
      );

      expect(result, isA<TessellationBoundaryRejected>());
      expect(
        (result as TessellationBoundaryRejected).reason,
        TessellationRejectReason.tooFewVertices,
      );
    });

    test('rejects a non-consecutive duplicate (diagonal weld / figure-8) as selfIntersecting', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(10, 0)),
        'c': _vertex('c', const Offset(10, 10)),
        'd': _vertex('d', const Offset(0, 10)),
      };
      // Ring a-b-a-c-d: 'a' revisited non-consecutively.
      final result = sanitizeTessellationBoundary(
        const ['a', 'b', 'a', 'c', 'd'],
        vertices: vertices,
      );

      expect(result, isA<TessellationBoundaryRejected>());
      expect(
        (result as TessellationBoundaryRejected).reason,
        TessellationRejectReason.selfIntersecting,
      );
    });

    test('rejects a geometrically self-intersecting (bowtie) ring', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(10, 10)),
        'c': _vertex('c', const Offset(10, 0)),
        'd': _vertex('d', const Offset(0, 10)),
      };
      final result = sanitizeTessellationBoundary(
        const ['a', 'b', 'c', 'd'],
        vertices: vertices,
      );

      expect(result, isA<TessellationBoundaryRejected>());
      expect(
        (result as TessellationBoundaryRejected).reason,
        TessellationRejectReason.selfIntersecting,
      );
    });

    test('respects a custom minVertices threshold', () {
      final result = sanitizeTessellationBoundary(
        const ['a', 'b', 'c', 'd'],
        vertices: squareVertices(),
        minVertices: 5,
      );

      expect(result, isA<TessellationBoundaryRejected>());
      expect(
        (result as TessellationBoundaryRejected).reason,
        TessellationRejectReason.tooFewVertices,
      );
    });
  });
}
