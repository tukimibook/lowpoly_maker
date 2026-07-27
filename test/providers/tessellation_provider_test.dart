import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/point_in_polygon.dart';
import 'package:polygon_art_app/geometry/tessellation_input.dart';
import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/polygon_shape.dart';
import 'package:polygon_art_app/models/vertex.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/providers/tessellation_provider.dart';

void main() {
  group('TessellationController.tessellate', () {
    test('rejects with tooFewVertices when the polygon does not exist', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final reason = await container.read(tessellationControllerProvider).tessellate(
        'does-not-exist',
        maxEdge: 50,
        minEdge: 20,
      );

      expect(reason, TessellationRejectReason.tooFewVertices);
      expect(container.read(isTessellatingProvider), isFalse);
    });

    test('rejects with selfIntersecting without ever flipping isTessellating', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(canvasProvider.notifier);

      // Bowtie quadrilateral: opposite edges cross. Injected via loadArtwork
      // because closePolygon now refuses to confirm a self-intersecting ring.
      const polygonId = 'bowtie';
      notifier.loadArtwork(
        Artwork(
          id: 'art',
          title: 'bowtie',
          vertices: {
            'a': const Vertex(id: 'a', position: Offset(0, 0)),
            'b': const Vertex(id: 'b', position: Offset(10, 10)),
            'c': const Vertex(id: 'c', position: Offset(10, 0)),
            'd': const Vertex(id: 'd', position: Offset(0, 10)),
          },
          polygons: [
            const PolygonShape(
              id: polygonId,
              vertexIds: ['a', 'b', 'c', 'd'],
              fillColor: Colors.red,
              strokeColor: Colors.black,
              strokeWidth: 1,
            ),
          ],
        ),
      );

      final flags = <bool>[];
      container.listen(isTessellatingProvider, (previous, next) => flags.add(next));

      final reason = await container.read(tessellationControllerProvider).tessellate(
        polygonId,
        maxEdge: 50,
        minEdge: 20,
      );

      expect(reason, TessellationRejectReason.selfIntersecting);
      expect(flags, isEmpty); // rejected before ever touching isTessellating
      expect(container.read(isTessellatingProvider), isFalse);
    });

    test(
      'a valid boundary reaches compute(), flips isTessellating true then false, '
      'and commits the triangulated result as a single undo entry',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(canvasProvider.notifier);

        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
        notifier.handleDrawTap(const Offset(10, 0), fillColor: Colors.blue);
        notifier.handleDrawTap(const Offset(10, 10), fillColor: Colors.blue);
        notifier.closePolygon(Colors.blue);
        final polygonId = notifier.state.polygons.single.id;
        final stateBefore = notifier.state;

        final flags = <bool>[];
        container.listen(isTessellatingProvider, (previous, next) => flags.add(next));

        final reason = await container.read(tessellationControllerProvider).tessellate(
          polygonId,
          maxEdge: 50,
          minEdge: 20,
        );

        expect(reason, isNull);
        expect(flags, [true, false]);
        expect(container.read(isTessellatingProvider), isFalse);
        // Committed as exactly one undo entry, replacing the original polygon.
        expect(notifier.state.polygons.any((p) => p.id == polygonId), isFalse);
        expect(notifier.canUndo, isTrue);
        notifier.undo();
        expect(notifier.state, stateBefore);
      },
    );

    // Note: `computeFailed` (triangulate()/compute() throwing) has no
    // reliable trigger left to test end-to-end now that `triangulate` is
    // implemented — it doesn't throw for any degenerate input (collinear or
    // duplicate points, etc.) reachable past `sanitizeTessellationBoundary`,
    // and forcing an actual `compute()`/Isolate failure isn't practical
    // without mocking `compute()` itself. The `catch` branch that surfaces
    // it stays in place as defensive-only code.

    test('a call while already in flight is an immediate no-op', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(isTessellatingProvider.notifier).state = true;

      final reason = await container.read(tessellationControllerProvider).tessellate(
        'irrelevant',
        maxEdge: 50,
        minEdge: 20,
      );

      expect(reason, isNull);
    });

    test(
      'fully contained inner polygon becomes a hole: it survives commit and '
      'no output triangle centroid falls inside it; partial overlap is ignored',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(canvasProvider.notifier);

        // Outer square.
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
        notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.blue);
        notifier.handleDrawTap(const Offset(200, 200), fillColor: Colors.blue);
        notifier.handleDrawTap(const Offset(0, 200), fillColor: Colors.blue);
        notifier.closePolygon(Colors.blue);
        final outerId = notifier.state.polygons.single.id;

        // Fully contained inner triangle.
        notifier.handleDrawTap(const Offset(70, 70), fillColor: Colors.red);
        notifier.handleDrawTap(const Offset(130, 70), fillColor: Colors.red);
        notifier.handleDrawTap(const Offset(100, 130), fillColor: Colors.red);
        notifier.closePolygon(Colors.red);
        final innerId = notifier.state.polygons
            .firstWhere((p) => p.id != outerId)
            .id;

        // Partial-overlap rectangle (must NOT become a hole / must not crash).
        notifier.handleDrawTap(const Offset(180, 80), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(220, 80), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(220, 120), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(180, 120), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final partialId = notifier.state.polygons
            .firstWhere((p) => p.fillColor == Colors.green)
            .id;

        final reason = await container.read(tessellationControllerProvider).tessellate(
          outerId,
          maxEdge: 80,
          minEdge: 15,
        );

        expect(reason, isNull);
        expect(notifier.state.polygons.any((p) => p.id == outerId), isFalse);
        expect(notifier.state.polygons.any((p) => p.id == innerId), isTrue);
        expect(notifier.state.polygons.any((p) => p.id == partialId), isTrue);

        final inner = notifier.state.polygons.firstWhere((p) => p.id == innerId);
        final holeRing = [
          for (final id in inner.vertexIds) notifier.state.vertices[id]!.position,
        ];

        for (final polygon in notifier.state.polygons) {
          if (polygon.id == innerId || polygon.id == partialId) continue;
          // Output mesh triangles from the outer tessellation.
          final positions = [
            for (final id in polygon.vertexIds)
              notifier.state.vertices[id]!.position,
          ];
          if (positions.length < 3) continue;
          final centroid = Offset(
            (positions[0].dx + positions[1].dx + positions[2].dx) / 3,
            (positions[0].dy + positions[1].dy + positions[2].dy) / 3,
          );
          expect(
            isPointInPolygon(centroid, holeRing),
            isFalse,
            reason: 'mesh triangle must not sit inside the hole',
          );
        }
      },
    );
  });
}
