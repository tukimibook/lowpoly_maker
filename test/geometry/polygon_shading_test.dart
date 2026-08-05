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

double _lightness(Color color) => HSLColor.fromColor(color).lightness;

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

      // Origin keeps the pre-jitter base ramp stop exactly.
      expect(result.colorsByPolygonId['p0'], result.ramp[0]);

      // Farther hops are darker than the origin (jittered, so not exact ramp equals).
      expect(
        _lightness(result.colorsByPolygonId['p1']!),
        lessThan(_lightness(result.colorsByPolygonId['p0']!)),
      );
      expect(
        _lightness(result.colorsByPolygonId['p2']!),
        lessThan(_lightness(result.colorsByPolygonId['p0']!)),
      );

      final lightnesses = result.ramp.map(_lightness).toList();
      for (var i = 1; i < lightnesses.length; i++) {
        expect(lightnesses[i], lessThanOrEqualTo(lightnesses[i - 1]));
      }
    });

    test('same inputs yield identical colors (deterministic jitter)', () {
      final polygons = [
        _polygon('p0', const ['a', 'x0', 'y0']),
        _polygon('p1', const ['a', 'b', 'y1']),
        _polygon('p2', const ['b', 'x2', 'y2']),
      ];

      ShadingResult run() => computeDistanceShading(
            originId: 'p0',
            targetIds: {'p0', 'p1', 'p2'},
            polygons: polygons,
            baseColor: baseColor,
          );

      final a = run();
      final b = run();
      expect(a.colorsByPolygonId, b.colorsByPolygonId);
      expect(a.ramp, b.ramp);
      expect(a.maxDistance, b.maxDistance);
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

    test('clamps distances beyond rampStops toward the darkest stop band', () {
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
      // Beyond the last stop: still in the darkest band (not as light as mid ramp).
      final midL = _lightness(result.ramp[3]);
      for (final id in ['p5', 'p6', 'p7']) {
        expect(
          _lightness(result.colorsByPolygonId[id]!),
          lessThan(midL),
          reason: '$id should sit in the far (dark) band',
        );
      }
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

    test('gamma ramp drops faster near the origin than a linear ramp would', () {
      final result = computeDistanceShading(
        originId: 'solo',
        targetIds: {'solo'},
        polygons: [_polygon('solo', const ['a', 'b', 'c'])],
        baseColor: baseColor,
      );

      final lightnesses = result.ramp.map(_lightness).toList();
      final start = lightnesses.first;
      final end = lightnesses.last;
      final range = start - end;
      // First step (index 1) should consume more than 1/(N-1) of the range.
      final firstStepShare = (start - lightnesses[1]) / range;
      expect(firstStepShare, greaterThan(1 / (kShadingRampStops - 1)));
    });
  });

  group('buildAccordionPaletteExpansion', () {
    test('places one lighter stop left of base and three darker to the right', () {
      final expansion = buildAccordionPaletteExpansion(baseColor);

      expect(expansion.darkers, hasLength(3));
      expect(_lightness(expansion.lighter), greaterThan(_lightness(baseColor)));
      expect(
        _lightness(expansion.darkers.first),
        lessThan(_lightness(baseColor)),
      );
      for (var i = 1; i < expansion.darkers.length; i++) {
        expect(
          _lightness(expansion.darkers[i]),
          lessThanOrEqualTo(_lightness(expansion.darkers[i - 1])),
        );
      }
    });
  });
}
