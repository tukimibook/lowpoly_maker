import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';

void main() {
  group('CanvasNotifier shared-boundary closure', () {
    test(
      'closing a draft whose start and end are both corners of the same polygon '
      "follows that polygon's shorter boundary arc instead of a straight edge",
      () {
        final notifier = CanvasNotifier();
        // Polygon A: a pentagon. The shorter arc between its (0,0) and
        // (100,100) corners passes through the (100,0) corner in between.
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 100), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 150), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(0, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final aIds = notifier.state.polygons.single.vertexIds;
        final aOrigin = aIds[0]; // (0, 0)
        final aTopRight = aIds[1]; // (100, 0)  — the in-between corner
        final aRight = aIds[2]; // (100, 100)

        // Polygon B: start on A's (0,0), arc far outside, end on A's (100,100).
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(
          const Offset(-100, -100),
          fillColor: Colors.orange,
        );
        notifier.handleDrawTap(
          const Offset(100, 100),
          fillColor: Colors.orange,
        );
        notifier.closePolygon(Colors.orange);

        expect(notifier.state.polygons, hasLength(2));
        final closed = notifier.state.polygons.last;
        // start, freehand, end, then A's in-between corner spliced in so the
        // closing path runs end -> (100,0) -> start along A's own edge.
        expect(closed.vertexIds, [
          aOrigin,
          closed.vertexIds[1], // the freehand (-100,-100) point
          aRight,
          aTopRight,
        ]);
        expect(
          notifier.state.vertices[closed.vertexIds[1]]!.position,
          const Offset(-100, -100),
        );
        // The spliced corner is A's own vertex, reused (welded), not a copy.
        expect(aIds, contains(aTopRight));
        // Polygon A itself is left completely untouched.
        expect(notifier.state.polygons.first.vertexIds, aIds);
      },
    );

    test(
      'closing a draft whose start and end belong to different polygons uses a '
      'plain straight edge when nothing else sits on it (no boundary to follow, '
      'nothing to weld)',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final aCorner = notifier.state.polygons.single.vertexIds[1]; // (100,0)

        notifier.handleDrawTap(const Offset(400, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(500, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(
          const Offset(450, 100),
          fillColor: Colors.purple,
        );
        notifier.closePolygon(Colors.purple);
        final bCorner = notifier.state.polygons[1].vertexIds[0]; // (400,0)

        // A draft bridging A's corner to B's corner — no single polygon owns
        // both, so there's no shared arc to trace, and nothing else sits on
        // the straight line between them to weld onto either.
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(
          const Offset(250, 300),
          fillColor: Colors.orange,
        );
        notifier.handleDrawTap(const Offset(400, 0), fillColor: Colors.orange);
        notifier.closePolygon(Colors.orange);

        final closed = notifier.state.polygons.last;
        expect(closed.vertexIds, hasLength(3));
        expect(closed.vertexIds.first, aCorner);
        expect(closed.vertexIds.last, bCorner);
      },
    );

    test(
      'closing a draft whose start and end belong to different polygons welds '
      'onto an existing vertex sitting on the straight closing line, instead of '
      'cutting straight through it',
      () {
        final notifier = CanvasNotifier();
        // Polygon A supplies a vertex sitting exactly where the future
        // closing edge (from the draft's end back to its start) will pass.
        // Its other corners are spaced well away so placing them doesn't
        // get folded into anything else.
        notifier.handleDrawTap(const Offset(50, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(90, 300), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(10, 300), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final onLineVertexId =
            notifier.state.polygons.single.vertexIds.first; // (50, 0)

        // Polygon B supplies the vertex the draft's end will weld onto.
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(
          const Offset(140, 300),
          fillColor: Colors.purple,
        );
        notifier.handleDrawTap(
          const Offset(60, 300),
          fillColor: Colors.purple,
        );
        notifier.closePolygon(Colors.purple);
        final endVertexId = notifier.state.polygons[1].vertexIds.first; // (100,0)

        // Draft C: starts at a brand-new point and docks its end onto B's
        // vertex. Neither of C's own drawn segments passes near (50, 0), so
        // only the implicit closing edge (end -> start) can pick it up.
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        final startVertexId = notifier.state.draftVertexIds.single;
        notifier.handleDrawTap(
          const Offset(0, 300),
          fillColor: Colors.orange,
        );
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        expect(notifier.state.draftVertexIds.last, endVertexId);

        notifier.closePolygon(Colors.orange);

        final closed = notifier.state.polygons.last;
        expect(closed.vertexIds, hasLength(4));
        expect(closed.vertexIds.first, startVertexId);
        expect(closed.vertexIds, contains(endVertexId));
        // The absorbed vertex is spliced in right after the draft's own
        // end, so the closing path runs end -> (50,0) -> start.
        expect(closed.vertexIds.last, onLineVertexId);
        expect(
          closed.vertexIds[closed.vertexIds.indexOf(endVertexId) + 1],
          onLineVertexId,
        );

        // Both source polygons remain completely untouched.
        expect(notifier.state.polygons[0].vertexIds, hasLength(3));
        expect(notifier.state.polygons[1].vertexIds, hasLength(3));
      },
    );

    test(
      'closing a draft that spans two different, already-adjacent polygons '
      'routes through their shared (welded) vertex instead of cutting a '
      'straight line back to its own start',
      () {
        final notifier = CanvasNotifier();
        // Polygon A: a triangle. Its (200,200) corner is about to be shared
        // with polygon B.
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(0, 200), fillColor: Colors.green);
        notifier.handleDrawTap(
          const Offset(200, 200),
          fillColor: Colors.green,
        );
        notifier.closePolygon(Colors.green);
        final aIds = notifier.state.polygons.single.vertexIds;
        final aOrigin = aIds[0]; // (0, 0)
        final sharedCorner = aIds[2]; // (200, 200)

        // Polygon B starts right on A's shared corner (welds onto it), then
        // continues on its own.
        notifier.handleDrawTap(
          const Offset(200, 200),
          fillColor: Colors.purple,
        );
        notifier.handleDrawTap(
          const Offset(400, 200),
          fillColor: Colors.purple,
        );
        notifier.handleDrawTap(
          const Offset(400, 400),
          fillColor: Colors.purple,
        );
        notifier.handleDrawTap(
          const Offset(200, 400),
          fillColor: Colors.purple,
        );
        notifier.closePolygon(Colors.purple);
        final bIds = notifier.state.polygons[1].vertexIds;
        expect(bIds.first, sharedCorner);
        final bFarCorner = bIds[1]; // (400, 200)

        // Draft C: starts on A's (0,0), then a freehand point placed well
        // away from everything, then welds its end onto B's (400,200). The
        // *straight* line from there back to (0,0) passes nowhere near the
        // shared corner (it's off to the side), so only a real graph search
        // along the existing boundaries — not simple straight-line
        // absorption — can find the shorter path through it.
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(
          const Offset(-400, -400),
          fillColor: Colors.orange,
        );
        final freehandId = notifier.state.draftVertexIds[1];
        notifier.handleDrawTap(
          const Offset(400, 200),
          fillColor: Colors.orange,
        );
        expect(notifier.state.draftVertexIds.last, bFarCorner);

        notifier.closePolygon(Colors.orange);

        final closed = notifier.state.polygons.last;
        // end -> sharedCorner -> start: B's own edge (bFarCorner-sharedCorner)
        // followed by A's own edge (sharedCorner-aOrigin), not a straight cut.
        expect(closed.vertexIds, [
          aOrigin,
          freehandId,
          bFarCorner,
          sharedCorner,
        ]);

        // Both source polygons remain completely untouched.
        expect(notifier.state.polygons[0].vertexIds, aIds);
        expect(notifier.state.polygons[1].vertexIds, bIds);
      },
    );

    test(
      'a double-tap between two different polygons that share no boundary '
      'or welded chain does not close — it would silently cut an unwelded '
      'gap; the explicit close button still can',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final aCorner = notifier.state.polygons.single.vertexIds[1]; // (100,0)

        notifier.handleDrawTap(const Offset(400, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(500, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(
          const Offset(450, 100),
          fillColor: Colors.purple,
        );
        notifier.closePolygon(Colors.purple);
        final bCorner = notifier.state.polygons[1].vertexIds[0]; // (400,0)

        // A draft bridging A's corner to B's corner — no shared boundary,
        // and nothing sits on the straight line between them either.
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(
          const Offset(250, 300),
          fillColor: Colors.orange,
        );
        // Single tap welds the draft's end onto B's corner...
        notifier.handleDrawTap(const Offset(400, 0), fillColor: Colors.orange);
        expect(notifier.state.draftVertexIds.last, bCorner);

        // ...but a quick second tap in the same spot must NOT close: closing
        // now would silently cut a straight, unwelded gap between A and B.
        notifier.handleDrawTap(const Offset(400, 0), fillColor: Colors.orange);

        expect(notifier.state.polygons, hasLength(2));
        // The tap was kept as an ordinary point instead of closing.
        expect(notifier.state.draftVertexIds, hasLength(4));

        // The explicit "close" toolbar button still allows it — the artist
        // deliberately decided to force a plain straight edge.
        notifier.closePolygon(Colors.orange);

        expect(notifier.state.polygons, hasLength(3));
        final closed = notifier.state.polygons.last;
        expect(closed.vertexIds.first, aCorner);
        expect(closed.vertexIds, contains(bCorner));
      },
    );
  });
}
