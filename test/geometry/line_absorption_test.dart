import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/line_absorption.dart';
import 'package:polygon_art_app/models/polygon_shape.dart';
import 'package:polygon_art_app/models/vertex.dart';

PolygonShape _polygon(String id, List<String> vertexIds) {
  return PolygonShape(
    id: id,
    vertexIds: vertexIds,
    fillColor: const Color(0xFF000000),
    strokeColor: const Color(0xFF000000),
    strokeWidth: 1,
  );
}

Vertex _vertex(String id, Offset position) => Vertex(id: id, position: position);

void main() {
  group('findVerticesAlongSegment', () {
    test('absorbs a vertex sitting exactly on the segment', () {
      final vertices = {'mid': _vertex('mid', const Offset(50, 0))};
      final result = findVerticesAlongSegment(
        const Offset(0, 0),
        const Offset(100, 0),
        vertices: vertices,
        polygons: [_polygon('p1', const ['mid'])],
        draftVertexIds: const {},
        tolerance: 5,
      );

      expect(result, ['mid']);
    });

    test('absorbs a vertex within tolerance of perpendicular distance from the line', () {
      final vertices = {'near': _vertex('near', const Offset(50, 4))};
      final result = findVerticesAlongSegment(
        const Offset(0, 0),
        const Offset(100, 0),
        vertices: vertices,
        polygons: [_polygon('p1', const ['near'])],
        draftVertexIds: const {},
        tolerance: 5,
      );

      expect(result, ['near']);
    });

    test('ignores a vertex farther than tolerance from the line', () {
      final vertices = {'far': _vertex('far', const Offset(50, 6))};
      final result = findVerticesAlongSegment(
        const Offset(0, 0),
        const Offset(100, 0),
        vertices: vertices,
        polygons: [_polygon('p1', const ['far'])],
        draftVertexIds: const {},
        tolerance: 5,
      );

      expect(result, isEmpty);
    });

    test('excludes a vertex exactly at or beyond either endpoint (t<=0 or t>=1)', () {
      final vertices = {
        'start': _vertex('start', const Offset(0, 0)),
        'end': _vertex('end', const Offset(100, 0)),
        'before': _vertex('before', const Offset(-10, 0)),
        'after': _vertex('after', const Offset(110, 0)),
      };
      final result = findVerticesAlongSegment(
        const Offset(0, 0),
        const Offset(100, 0),
        vertices: vertices,
        polygons: [_polygon('p1', const ['start', 'end', 'before', 'after'])],
        draftVertexIds: const {},
        tolerance: 5,
      );

      expect(result, isEmpty);
    });

    test('orders absorbed vertices by how far along the segment they fall', () {
      final vertices = {
        'far': _vertex('far', const Offset(80, 0)),
        'near': _vertex('near', const Offset(20, 0)),
        'mid': _vertex('mid', const Offset(50, 0)),
      };
      final result = findVerticesAlongSegment(
        const Offset(0, 0),
        const Offset(100, 0),
        vertices: vertices,
        polygons: [_polygon('p1', const ['far', 'near', 'mid'])],
        draftVertexIds: const {},
        tolerance: 5,
      );

      expect(result, ['near', 'mid', 'far']);
    });

    test('excludeVertexId skips that vertex even though it otherwise qualifies', () {
      final vertices = {'mid': _vertex('mid', const Offset(50, 0))};
      final result = findVerticesAlongSegment(
        const Offset(0, 0),
        const Offset(100, 0),
        vertices: vertices,
        polygons: [_polygon('p1', const ['mid'])],
        draftVertexIds: const {},
        tolerance: 5,
        excludeVertexId: 'mid',
      );

      expect(result, isEmpty);
    });

    test('draftVertexIds are always excluded, regardless of excludeVertexId', () {
      final vertices = {'mid': _vertex('mid', const Offset(50, 0))};
      final result = findVerticesAlongSegment(
        const Offset(0, 0),
        const Offset(100, 0),
        vertices: vertices,
        polygons: [_polygon('p1', const ['mid'])],
        draftVertexIds: const {'mid'},
        tolerance: 5,
      );

      expect(result, isEmpty);
    });

    test('a vertex referenced by multiple polygons is only returned once', () {
      final vertices = {'mid': _vertex('mid', const Offset(50, 0))};
      final result = findVerticesAlongSegment(
        const Offset(0, 0),
        const Offset(100, 0),
        vertices: vertices,
        polygons: [
          _polygon('p1', const ['mid']),
          _polygon('p2', const ['mid']),
        ],
        draftVertexIds: const {},
        tolerance: 5,
      );

      expect(result, ['mid']);
    });

    test('returns empty for a degenerate (zero-length) segment', () {
      final vertices = {'mid': _vertex('mid', const Offset(0, 0))};
      final result = findVerticesAlongSegment(
        const Offset(0, 0),
        const Offset(0, 0),
        vertices: vertices,
        polygons: [_polygon('p1', const ['mid'])],
        draftVertexIds: const {},
        tolerance: 5,
      );

      expect(result, isEmpty);
    });

    test('silently skips a vertex ID missing from the vertex pool', () {
      final result = findVerticesAlongSegment(
        const Offset(0, 0),
        const Offset(100, 0),
        vertices: const {},
        polygons: [_polygon('p1', const ['missing'])],
        draftVertexIds: const {},
        tolerance: 5,
      );

      expect(result, isEmpty);
    });

    test('returns empty when there are no polygons at all', () {
      final result = findVerticesAlongSegment(
        const Offset(0, 0),
        const Offset(100, 0),
        vertices: const {},
        polygons: const [],
        draftVertexIds: const {},
        tolerance: 5,
      );

      expect(result, isEmpty);
    });
  });
}
