import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/polygon_shape.dart';
import 'package:polygon_art_app/providers/polygon_edit_target_provider.dart';

PolygonShape _polygon(String id, List<String> vertexIds) {
  return PolygonShape(
    id: id,
    vertexIds: vertexIds,
    fillColor: const Color(0xFF000000),
    strokeColor: const Color(0xFF000000),
    strokeWidth: 1,
  );
}

void main() {
  group('polygonCycleIndexProvider', () {
    test('starts at -1 (nothing chosen yet)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(polygonCycleIndexProvider), -1);
    });
  });

  group('edgeCycleIndexProvider', () {
    test('starts at -1 (nothing chosen yet)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(edgeCycleIndexProvider), -1);
    });
  });

  group('resolvePolygonTarget', () {
    test('returns null for the initial -1 sentinel', () {
      final target = resolvePolygonTarget(
        polygons: [_polygon('p1', const ['a', 'b', 'c'])],
        rawCycleIndex: -1,
      );

      expect(target, isNull);
    });

    test('returns null when there are no polygons at all', () {
      final target = resolvePolygonTarget(polygons: const [], rawCycleIndex: 0);

      expect(target, isNull);
    });

    test('resolves in list order for in-range indices', () {
      final polygons = [
        _polygon('p1', const ['a', 'b', 'c']),
        _polygon('p2', const ['d', 'e', 'f']),
        _polygon('p3', const ['g', 'h', 'i']),
      ];

      expect(resolvePolygonTarget(polygons: polygons, rawCycleIndex: 0), 'p1');
      expect(resolvePolygonTarget(polygons: polygons, rawCycleIndex: 1), 'p2');
      expect(resolvePolygonTarget(polygons: polygons, rawCycleIndex: 2), 'p3');
    });

    test('wraps back to the first polygon once past the last one', () {
      final polygons = [
        _polygon('p1', const ['a', 'b', 'c']),
        _polygon('p2', const ['d', 'e', 'f']),
      ];

      expect(resolvePolygonTarget(polygons: polygons, rawCycleIndex: 2), 'p1');
      expect(resolvePolygonTarget(polygons: polygons, rawCycleIndex: 5), 'p2');
    });

    test('a stale index from a larger previous polygon set never goes out of range', () {
      final target = resolvePolygonTarget(
        polygons: [_polygon('only', const ['a', 'b', 'c'])],
        rawCycleIndex: 4,
      );

      expect(target, 'only');
    });
  });

  group('resolveEdgeTarget', () {
    test('returns null for the initial -1 sentinel', () {
      final target = resolveEdgeTarget(
        polygon: _polygon('p1', const ['a', 'b', 'c']),
        rawCycleIndex: -1,
      );

      expect(target, isNull);
    });

    test('returns null for a degenerate ring of fewer than 2 vertices', () {
      final target = resolveEdgeTarget(
        polygon: _polygon('p1', const ['a']),
        rawCycleIndex: 0,
      );

      expect(target, isNull);
    });

    test('resolves each edge, including ringIndex, in ring order', () {
      final polygon = _polygon('p1', const ['a', 'b', 'c']);

      expect(
        resolveEdgeTarget(polygon: polygon, rawCycleIndex: 0),
        (startVertexId: 'a', endVertexId: 'b', ringIndex: 0),
      );
      expect(
        resolveEdgeTarget(polygon: polygon, rawCycleIndex: 1),
        (startVertexId: 'b', endVertexId: 'c', ringIndex: 1),
      );
    });

    test('the last index resolves the closing edge, wrapping back to the first vertex', () {
      final polygon = _polygon('p1', const ['a', 'b', 'c']);

      expect(
        resolveEdgeTarget(polygon: polygon, rawCycleIndex: 2),
        (startVertexId: 'c', endVertexId: 'a', ringIndex: 2),
      );
    });

    test('wraps back to the first edge once past the last one', () {
      final polygon = _polygon('p1', const ['a', 'b', 'c']);

      expect(
        resolveEdgeTarget(polygon: polygon, rawCycleIndex: 3),
        (startVertexId: 'a', endVertexId: 'b', ringIndex: 0),
      );
    });
  });
}
