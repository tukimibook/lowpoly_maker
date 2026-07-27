import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';

void main() {
  group('CanvasNotifier.commitTraceStroke', () {
    test('a no-op for an empty point list — no undo entry recorded', () {
      final notifier = CanvasNotifier();
      notifier.commitTraceStroke(const []);

      expect(notifier.state.draftVertexIds, isEmpty);
      expect(notifier.canUndo, isFalse);
    });

    test(
      'appends every point as a new freehand draft vertex, in order, as '
      'exactly one undo entry',
      () {
        final notifier = CanvasNotifier();
        notifier.commitTraceStroke(const [
          Offset(0, 0),
          Offset(40, 0),
          Offset(80, 0),
          Offset(80, 40),
        ]);

        expect(notifier.state.draftVertexIds, hasLength(4));
        expect(
          notifier.state.draftVertexIds
              .map((id) => notifier.state.vertices[id]!.position)
              .toList(),
          const [Offset(0, 0), Offset(40, 0), Offset(80, 0), Offset(80, 40)],
        );

        expect(notifier.canUndo, isTrue);
        notifier.undo();
        expect(notifier.state.draftVertexIds, isEmpty);
        expect(notifier.canUndo, isFalse);
      },
    );

    test(
      'a single big batch is exactly one undo entry regardless of point count',
      () {
        final notifier = CanvasNotifier();
        final points = [for (var i = 0; i < 50; i++) Offset(i * 5.0, 0)];
        notifier.commitTraceStroke(points);

        expect(notifier.state.draftVertexIds, hasLength(50));
        expect(notifier.canUndo, isTrue);
        // Exactly one snapshot pushed: a single undo restores the empty
        // draft in one step, not 50 partial ones.
        notifier.undo();
        expect(notifier.state.draftVertexIds, isEmpty);
        expect(notifier.canUndo, isFalse);
      },
    );

    test(
      'the first point snaps onto (and shares the ID of) a nearby existing '
      'confirmed-polygon vertex, exactly like a plain tap would',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final sharedVertexId = notifier.state.polygons.single.vertexIds[1]; // (100, 0)

        notifier.commitTraceStroke(const [
          Offset(100, 2), // within default hitRadius of the shared vertex
          Offset(200, 100),
        ]);

        expect(notifier.state.draftVertexIds, hasLength(2));
        expect(notifier.state.draftVertexIds.first, sharedVertexId);
        // The polygon itself is untouched.
        expect(notifier.state.polygons, hasLength(1));
        expect(notifier.state.polygons.single.vertexIds, hasLength(3));
      },
    );

    test(
      'a later point snapping onto an existing vertex welds onto it instead '
      'of creating a duplicate point at the same spot',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(300, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(400, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(350, 100), fillColor: Colors.purple);
        notifier.closePolygon(Colors.purple);
        final targetVertexId = notifier.state.polygons.single.vertexIds.first; // (300, 0)

        notifier.commitTraceStroke(const [
          Offset(0, 0),
          Offset(150, 0),
          Offset(300, 1), // within hitRadius of targetVertexId
        ]);

        expect(notifier.state.draftVertexIds, hasLength(3));
        expect(notifier.state.draftVertexIds.last, targetVertexId);
      },
    );

    test(
      'absorbs an existing vertex sitting almost exactly on the segment '
      'between two consecutive trace points, same as a drawn segment would',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(50, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(90, 150), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(10, 150), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final absorbedVertexId = notifier.state.polygons.single.vertexIds.first; // (50, 0)

        notifier.commitTraceStroke(const [Offset(0, 0), Offset(100, 0)]);

        expect(notifier.state.draftVertexIds, hasLength(3));
        expect(notifier.state.draftVertexIds[1], absorbedVertexId);
      },
    );

    test(
      'never triggers a pseudo double-tap close, no matter how the stroke '
      'loops back near its own start',
      () {
        final notifier = CanvasNotifier();
        notifier.commitTraceStroke(const [
          Offset(0, 0),
          Offset(100, 0),
          Offset(100, 100),
          Offset(2, 2), // right back near the start
        ]);

        expect(notifier.state.polygons, isEmpty);
        expect(notifier.state.draftVertexIds, hasLength(4));
      },
    );

    test('continues appending to an already-in-progress draft rather than replacing it', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
      notifier.handleDrawTap(const Offset(50, 50), fillColor: Colors.orange);
      final existingCount = notifier.state.draftVertexIds.length;

      notifier.commitTraceStroke(const [Offset(200, 200), Offset(250, 250)]);

      expect(notifier.state.draftVertexIds, hasLength(existingCount + 2));
    });

    test(
      'a stroke followed immediately by a plain tap is never misread as a '
      'pseudo double-tap referencing the trace\'s own last point',
      () {
        final notifier = CanvasNotifier();
        notifier.commitTraceStroke(const [Offset(0, 0), Offset(4, 4)]);
        // A tap landing extremely close to (and immediately after) the
        // trace's last point must not be read as the second half of a
        // double-tap self-close — `_resetPendingTap` inside
        // `commitTraceStroke` must have cleared that bookkeeping.
        notifier.handleDrawTap(const Offset(5, 5), fillColor: Colors.orange);

        expect(notifier.state.polygons, isEmpty);
        expect(notifier.state.draftVertexIds, hasLength(3));
      },
    );

    test(
      'respects a scaled-down hitRadius exactly like handleDrawTap does',
      () {
        void buildTarget(CanvasNotifier notifier) {
          // (300, 12) sits ~23.3px from the trace's end point below — far
          // enough off the y=0 line (perpendicular distance 12) that the
          // separate line-absorption tolerance (default 10px) never
          // absorbs it as a pass-through point, isolating this test to
          // hitRadius alone. The other two corners are far away so they
          // can't be confused for the target either.
          notifier.handleDrawTap(const Offset(300, 12), fillColor: Colors.purple);
          notifier.handleDrawTap(const Offset(500, 300), fillColor: Colors.purple);
          notifier.handleDrawTap(const Offset(200, 300), fillColor: Colors.purple);
          notifier.closePolygon(Colors.purple);
        }

        final atDefault = CanvasNotifier();
        buildTarget(atDefault);
        final targetVertexId = atDefault.state.polygons.single.vertexIds.first;
        // ~23.3px from (300, 12): within the default 30px hitRadius, so
        // the trace's end point snaps onto (and shares the ID of) it.
        atDefault.commitTraceStroke(const [Offset(0, 0), Offset(320, 0)]);
        expect(atDefault.state.draftVertexIds, hasLength(2));
        expect(atDefault.state.draftVertexIds.last, targetVertexId);

        final scaledDown = CanvasNotifier();
        buildTarget(scaledDown);
        // Same ~23.3px gap, but scaled down to a tighter screen distance
        // (scale 2 → hitRadius 15) exceeds it, so this must place an
        // ordinary freehand point instead of snapping.
        scaledDown.commitTraceStroke(
          const [Offset(0, 0), Offset(320, 0)],
          hitRadius: kVertexHitRadius / 2,
        );
        expect(scaledDown.state.draftVertexIds, hasLength(2));
        expect(
          scaledDown.state.vertices[scaledDown.state.draftVertexIds.last]!.position,
          const Offset(320, 0),
        );
      },
    );
  });
}
