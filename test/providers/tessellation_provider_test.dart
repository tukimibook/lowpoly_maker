import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/tessellation_input.dart';
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

      // Bowtie quadrilateral: opposite edges cross.
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(10, 10), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(10, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(0, 10), fillColor: Colors.red);
      notifier.closePolygon(Colors.red);
      final polygonId = notifier.state.polygons.single.id;

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
  });
}
