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
        // Freehand stays off the (0,0)-(100,100) diagonal so the draft edge
        // does not pass through the start vertex (degenerate self-touch).
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(
          const Offset(-100, 50),
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
          const Offset(-100, 50),
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

    test(
      'closing after snapping along an existing boundary returns the short '
      'arc without duplicating draft vertex IDs',
      () {
        final notifier = CanvasNotifier();
        // Square A: (0,0)-(100,0)-(100,100)-(0,100).
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 100), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(0, 100), fillColor: Colors.green);
        expect(notifier.closePolygon(Colors.green), ClosePolygonResult.closed);
        final aIds = notifier.state.polygons.single.vertexIds;
        final a = aIds[0]; // (0,0)
        final b = aIds[1]; // (100,0)
        final c = aIds[2]; // (100,100)
        final d = aIds[3]; // (0,100)

        // Trace the whole boundary by snapping every corner, then close.
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(100, 100), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(0, 100), fillColor: Colors.orange);
        expect(notifier.state.draftVertexIds, [a, b, c, d]);

        expect(notifier.closePolygon(Colors.orange), ClosePolygonResult.closed);
        expect(notifier.state.polygons, hasLength(2));
        final closed = notifier.state.polygons.last;
        // No duplicated mid IDs — the draft already held the short-arc verts,
        // and d→a is the square's own edge (nothing to splice).
        expect(closed.vertexIds, [a, b, c, d]);
        expect(closed.vertexIds.toSet(), hasLength(4));
      },
    );

    test(
      'closePolygon rejects a skewer chord that would cut through an existing '
      'polygon (draft kept, no undo)',
      () {
        final notifier = CanvasNotifier();
        // Obstacle square sitting between two distant weld targets. A plain
        // last→first chord from the left tip to the right tip runs straight
        // through its interior — that must be refused.
        notifier.handleDrawTap(const Offset(50, 50), fillColor: Colors.grey);
        notifier.handleDrawTap(const Offset(150, 50), fillColor: Colors.grey);
        notifier.handleDrawTap(const Offset(150, 150), fillColor: Colors.grey);
        notifier.handleDrawTap(const Offset(50, 150), fillColor: Colors.grey);
        expect(notifier.closePolygon(Colors.grey), ClosePolygonResult.closed);

        notifier.handleDrawTap(const Offset(0, 80), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(0, 120), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(30, 100), fillColor: Colors.green);
        expect(notifier.closePolygon(Colors.green), ClosePolygonResult.closed);
        final leftTip = notifier.state.polygons[1].vertexIds[2]; // (30,100)

        notifier.handleDrawTap(const Offset(200, 80), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(200, 120), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(170, 100), fillColor: Colors.purple);
        expect(notifier.closePolygon(Colors.purple), ClosePolygonResult.closed);
        final rightTip = notifier.state.polygons[2].vertexIds[2]; // (170,100)

        // Bridge left tip → freehand below → right tip. No shared boundary
        // chain connects the tips, so close would invent the horizontal
        // chord through the obstacle at y=100.
        notifier.handleDrawTap(const Offset(30, 100), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(170, 100), fillColor: Colors.orange);
        expect(notifier.state.draftVertexIds.first, leftTip);
        expect(notifier.state.draftVertexIds.last, rightTip);
        final draftBefore = List<String>.from(notifier.state.draftVertexIds);

        final undoAvailableBefore = notifier.canUndo;
        expect(
          notifier.closePolygon(Colors.orange),
          ClosePolygonResult.rejectedUnsafeClosingEdge,
        );
        expect(notifier.state.polygons, hasLength(3));
        expect(notifier.state.draftVertexIds, draftBefore);
        // Rejected close must not push an undo snapshot.
        expect(notifier.canUndo, undoAvailableBefore);
      },
    );

    test(
      'closing opposite corners follows the unique short boundary arc '
      'instead of the diagonal skewer',
      () {
        final notifier = CanvasNotifier();
        // Trapezoid where a→b→c (150) is clearly shorter than a→d→c (~212).
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 50), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(0, 100), fillColor: Colors.green);
        expect(notifier.closePolygon(Colors.green), ClosePolygonResult.closed);
        final aIds = notifier.state.polygons.single.vertexIds;
        final a = aIds[0]; // (0,0)
        final b = aIds[1]; // (100,0)
        final c = aIds[2]; // (100,50)
        final d = aIds[3]; // (0,100)

        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        // Off the a–c diagonal so the freehand edge does not pass through a.
        notifier.handleDrawTap(
          const Offset(-50, 25),
          fillColor: Colors.orange,
        );
        notifier.handleDrawTap(const Offset(100, 50), fillColor: Colors.orange);
        expect(notifier.closePolygon(Colors.orange), ClosePolygonResult.closed);

        final closed = notifier.state.polygons.last;
        final freehand = closed.vertexIds[1];
        expect(closed.vertexIds, [a, freehand, c, b]);
        expect(closed.vertexIds, isNot(contains(d)));
      },
    );
  });
}
