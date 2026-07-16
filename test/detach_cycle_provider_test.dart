import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/polygon_shape.dart';
import 'package:polygon_art_app/providers/detach_cycle_provider.dart';

PolygonShape _polygon(String id) {
  return PolygonShape(
    id: id,
    vertexIds: const ['a', 'b', 'c'],
    fillColor: const Color(0xFF000000),
    strokeColor: const Color(0xFF000000),
    strokeWidth: 1,
  );
}

void main() {
  group('detachCycleIndexProvider', () {
    test('starts at 0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(detachCycleIndexProvider), 0);
    });
  });

  group('resolveDetachTarget', () {
    test('returns null when there is nothing to detach from at all', () {
      final target = resolveDetachTarget(
        referencingPolygons: const [],
        draftReferences: false,
        rawCycleIndex: 0,
      );

      expect(target, isNull);
    });

    test('a single referencing polygon is always the target, regardless of index', () {
      final polygon = _polygon('p1');

      for (final index in [0, 1, 5, 100]) {
        final target = resolveDetachTarget(
          referencingPolygons: [polygon],
          draftReferences: false,
          rawCycleIndex: index,
        );
        expect(target, (polygonId: 'p1', isDraft: false));
      }
    });

    test('cycles through multiple referencing polygons in list order', () {
      final polygons = [_polygon('p1'), _polygon('p2'), _polygon('p3')];

      expect(
        resolveDetachTarget(referencingPolygons: polygons, draftReferences: false, rawCycleIndex: 0),
        (polygonId: 'p1', isDraft: false),
      );
      expect(
        resolveDetachTarget(referencingPolygons: polygons, draftReferences: false, rawCycleIndex: 1),
        (polygonId: 'p2', isDraft: false),
      );
      expect(
        resolveDetachTarget(referencingPolygons: polygons, draftReferences: false, rawCycleIndex: 2),
        (polygonId: 'p3', isDraft: false),
      );
    });

    test('wraps back to the first candidate once past the last one', () {
      final polygons = [_polygon('p1'), _polygon('p2')];

      final target = resolveDetachTarget(
        referencingPolygons: polygons,
        draftReferences: false,
        rawCycleIndex: 2, // one past the last index (0, 1)
      );

      expect(target, (polygonId: 'p1', isDraft: false));
    });

    test('the draft is appended after every referencing polygon in the cycle', () {
      final polygons = [_polygon('p1'), _polygon('p2')];

      expect(
        resolveDetachTarget(referencingPolygons: polygons, draftReferences: true, rawCycleIndex: 0),
        (polygonId: 'p1', isDraft: false),
      );
      expect(
        resolveDetachTarget(referencingPolygons: polygons, draftReferences: true, rawCycleIndex: 1),
        (polygonId: 'p2', isDraft: false),
      );
      final draftTarget = resolveDetachTarget(
        referencingPolygons: polygons,
        draftReferences: true,
        rawCycleIndex: 2,
      );
      expect(draftTarget!.isDraft, isTrue);
      expect(draftTarget.polygonId, isNull);

      // Wraps back to the first polygon after the draft.
      expect(
        resolveDetachTarget(referencingPolygons: polygons, draftReferences: true, rawCycleIndex: 3),
        (polygonId: 'p1', isDraft: false),
      );
    });

    test('the draft alone (no referencing polygons) is the only candidate', () {
      final target = resolveDetachTarget(
        referencingPolygons: const [],
        draftReferences: true,
        rawCycleIndex: 0,
      );

      expect(target, isNotNull);
      expect(target!.isDraft, isTrue);
      expect(target.polygonId, isNull);
    });

    test('a stale index from a larger previous candidate set never goes out of range', () {
      // Simulates: user was cycling through 5 candidates, detached one down
      // to 1, and the raw counter is still sitting at a large value.
      final target = resolveDetachTarget(
        referencingPolygons: [_polygon('only')],
        draftReferences: false,
        rawCycleIndex: 4,
      );

      expect(target, (polygonId: 'only', isDraft: false));
    });
  });
}
