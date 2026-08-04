import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/polygon_shading.dart';
import 'package:polygon_art_app/models/polygon_shape.dart';

PolygonShape _polygon(String id, List<String> vertexIds) {
  return PolygonShape(
    id: id,
    vertexIds: vertexIds,
    fillColor: const Color(0xFF808080),
    strokeColor: const Color(0xFF000000),
    strokeWidth: 1,
  );
}

void main() {
  const baseColor = Color(0xFFFFAA00);

  group('computeDistanceShading', () {
    test('assigns distance-based colors along a welded chain from the origin', () {
      // p0 — p1 — p2  (shared vertex ids a / b)
      final polygons = [
        _polygon('p0', const ['a', 'x0', 'y0']),
        _polygon('p1', const ['a', 'b', 'y1']),
        _polygon('p2', const ['b', 'x2', 'y2']),
      ];

      final result = computeDistanceShading(
        originId: 'p0',
        targetIds: {'p0', 'p1', 'p2'},
        polygons: polygons,
        baseColor: baseColor,
      );

      expect(result.colorsByPolygonId.keys, unorderedEquals(['p0', 'p1', 'p2']));
      expect(result.maxDistance, 2);
      expect(result.ramp, hasLength(kShadingRampStops));

      // Origin uses the lightest ramp stop; farther hops are darker.
      expect(result.colorsByPolygonId['p0'], result.ramp[0]);
      expect(result.colorsByPolygonId['p1'], result.ramp[1]);
      expect(result.colorsByPolygonId['p2'], result.ramp[2]);

      final lightnesses = result.ramp
          .map((c) => HSLColor.fromColor(c).lightness)
          .toList();
      for (var i = 1; i < lightnesses.length; i++) {
        expect(lightnesses[i], lessThanOrEqualTo(lightnesses[i - 1]));
      }
    });

    test('omits disconnected islands from colorsByPolygonId (existing fill kept by caller)', () {
      final polygons = [
        _polygon('lit', const ['a', 'b', 'c']),
        _polygon('neighbor', const ['a', 'd', 'e']),
        _polygon('island', const ['x', 'y', 'z']),
      ];

      final result = computeDistanceShading(
        originId: 'lit',
        targetIds: {'lit', 'neighbor', 'island'},
        polygons: polygons,
        baseColor: baseColor,
      );

      expect(result.colorsByPolygonId.keys, unorderedEquals(['lit', 'neighbor']));
      expect(result.colorsByPolygonId.containsKey('island'), isFalse);
      expect(result.maxDistance, 1);
    });

    test('origin alone yields distance 0 and a single assigned color', () {
      final polygons = [
        _polygon('solo', const ['a', 'b', 'c']),
        _polygon('other', const ['a', 'd', 'e']),
      ];

      final result = computeDistanceShading(
        originId: 'solo',
        targetIds: {'solo'},
        polygons: polygons,
        baseColor: baseColor,
      );

      expect(result.colorsByPolygonId, {'solo': result.ramp[0]});
      expect(result.maxDistance, 0);
      expect(result.ramp, hasLength(kShadingRampStops));
    });

    test('returns empty when origin is outside the target set', () {
      final polygons = [_polygon('p0', const ['a', 'b', 'c'])];

      final result = computeDistanceShading(
        originId: 'p0',
        targetIds: {'someone-else'},
        polygons: polygons,
        baseColor: baseColor,
      );

      expect(result.colorsByPolygonId, isEmpty);
      expect(result.ramp, isEmpty);
      expect(result.maxDistance, -1);
    });

    test('clamps distances beyond rampStops to the darkest stop', () {
      // Chain of 8 polygons sharing consecutive vertices → max distance 7.
      final polygons = <PolygonShape>[
        _polygon('p0', const ['v0', 'a0', 'b0']),
        for (var i = 1; i < 8; i++)
          _polygon('p$i', ['v${i - 1}', 'v$i', 'b$i']),
      ];

      final result = computeDistanceShading(
        originId: 'p0',
        targetIds: {for (var i = 0; i < 8; i++) 'p$i'},
        polygons: polygons,
        baseColor: baseColor,
        rampStops: 6,
      );

      expect(result.maxDistance, 7);
      expect(result.colorsByPolygonId['p5'], result.ramp[5]);
      expect(result.colorsByPolygonId['p6'], result.ramp[5]);
      expect(result.colorsByPolygonId['p7'], result.ramp[5]);
    });

    test('polygons that only share coordinates but not vertex ids are not adjacent', () {
      // Same positions would require a Vertex pool; adjacency is id-based, so
      // distinct ids with no shared id stay disconnected.
      final polygons = [
        _polygon('left', const ['a', 'b', 'c']),
        _polygon('right', const ['d', 'e', 'f']),
      ];

      final result = computeDistanceShading(
        originId: 'left',
        targetIds: {'left', 'right'},
        polygons: polygons,
        baseColor: baseColor,
      );

      expect(result.colorsByPolygonId.keys, unorderedEquals(['left']));
      expect(result.colorsByPolygonId.containsKey('right'), isFalse);
    });
  });
}
