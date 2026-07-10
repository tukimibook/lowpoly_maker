import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';

void main() {
  group('CanvasNotifier draw mode', () {
    test('closing a triangle creates one polygon and clears the draft', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.red);
      notifier.closePolygon(Colors.red);

      expect(notifier.state.polygons, hasLength(1));
      expect(notifier.state.draftVertexIds, isEmpty);
      expect(notifier.state.polygons.single.vertexIds, hasLength(3));
    });

    test(
      'a single tap near the first vertex never closes the polygon by itself — closing is double-tap-only',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
        notifier.handleDrawTap(const Offset(500, 0), fillColor: Colors.blue);
        notifier.handleDrawTap(const Offset(250, 500), fillColor: Colors.blue);
        // Far enough from the previous tap to avoid being mistaken for a
        // pseudo double-tap, but well within the *old* 24px close radius.
        notifier.handleDrawTap(const Offset(2, 2), fillColor: Colors.blue);

        expect(notifier.state.polygons, isEmpty);
        expect(notifier.state.draftVertexIds, hasLength(4));
      },
    );

    test(
      'tapping a confirmed polygon vertex starts a new draft that shares its exact ID, without altering the polygon',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        expect(notifier.state.polygons, hasLength(1));
        final originalVertexIds = notifier.state.polygons.single.vertexIds;
        final sharedVertexId = originalVertexIds[1]; // the (100, 0) corner

        final matchedColor = notifier.handleDrawTap(
          const Offset(100, 0),
          fillColor: Colors.black,
        );

        expect(matchedColor, Colors.green);
        // The original polygon must remain fully intact: same IDs, same order.
        expect(notifier.state.polygons, hasLength(1));
        expect(notifier.state.polygons.single.vertexIds, originalVertexIds);

        // The new draft's single point IS that same vertex ID — not merely a
        // new point placed at a matching coordinate.
        expect(notifier.state.draftVertexIds, [sharedVertexId]);
        expect(
          notifier.state.vertices[sharedVertexId]!.position,
          const Offset(100, 0),
        );
      },
    );

    test(
      'continuing from an existing vertex builds a brand new polygon that shares that exact vertex',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final sharedVertexId = notifier.state.polygons.single.vertexIds[1];

        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(
          const Offset(150, 100),
          fillColor: Colors.purple,
        );
        notifier.closePolygon(Colors.purple);

        expect(notifier.state.polygons, hasLength(2));
        expect(notifier.state.draftVertexIds, isEmpty);
        // Original polygon is unchanged.
        expect(notifier.state.polygons.first.vertexIds, hasLength(3));
        expect(notifier.state.polygons.first.fillColor, Colors.green);
        // New polygon's first point IS the shared vertex ID from polygon A —
        // the same entry in the pool, not a different point at the same spot.
        expect(notifier.state.polygons.last.vertexIds, hasLength(3));
        expect(notifier.state.polygons.last.vertexIds.first, sharedVertexId);
        expect(notifier.state.polygons.last.fillColor, Colors.purple);
        expect(
          notifier.state.vertices[sharedVertexId]!.position,
          const Offset(100, 0),
        );
      },
    );

    test('findPolygonVertexNear returns null when nothing is close enough', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.orange);
      notifier.closePolygon(Colors.orange);

      final hit = notifier.findPolygonVertexNear(const Offset(500, 500));
      expect(hit, isNull);
    });

    test(
      'snapping onto an existing vertex never closes the shape by itself, no matter how many points',
      () {
        final notifier = CanvasNotifier();
        // Polygon A (the "start" corner).
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final startVertexId =
            notifier.state.polygons[0].vertexIds[1]; // (100, 0)

        // Polygon B (will supply the "end" corner to snap onto).
        notifier.handleDrawTap(const Offset(300, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(400, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(
          const Offset(350, 100),
          fillColor: Colors.purple,
        );
        notifier.closePolygon(Colors.purple);
        final endVertexId = notifier.state.polygons[1].vertexIds[0]; // (300, 0)

        expect(notifier.state.polygons, hasLength(2));

        // Start a brand new draft from polygon A's vertex...
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(
          const Offset(200, 200),
          fillColor: Colors.orange,
        );
        // ...and dock its end onto polygon B's vertex. This completes 3
        // points, but snapping alone must NOT close the shape — the artist
        // may still want to keep tracing further existing corners before
        // deciding the shape is done.
        notifier.handleDrawTap(const Offset(300, 0), fillColor: Colors.orange);

        expect(notifier.state.polygons, hasLength(2));
        expect(notifier.state.draftVertexIds, hasLength(3));
        expect(notifier.state.draftVertexIds.first, startVertexId);
        expect(notifier.state.draftVertexIds.last, endVertexId);

        // Closing is an explicit, separate step (the toolbar's "close"
        // button, wired directly to closePolygon).
        notifier.closePolygon(Colors.orange);

        expect(notifier.state.draftVertexIds, isEmpty);
        expect(notifier.state.polygons, hasLength(3));

        final newPolygon = notifier.state.polygons.last;
        expect(newPolygon.fillColor, Colors.orange);
        expect(newPolygon.vertexIds, hasLength(3));
        // Both ends are literally the same vertex IDs as A's and B's corners
        // — polygon C shares its start and end with them, with no gap.
        expect(newPolygon.vertexIds.first, startVertexId);
        expect(newPolygon.vertexIds.last, endVertexId);

        // Both source polygons remain completely untouched.
        expect(notifier.state.polygons[0].vertexIds, hasLength(3));
        expect(notifier.state.polygons[0].fillColor, Colors.green);
        expect(notifier.state.polygons[1].vertexIds, hasLength(3));
        expect(notifier.state.polygons[1].fillColor, Colors.purple);
      },
    );

    test(
      'a shape can dock onto several existing vertices in a row before being closed explicitly',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 100), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(0, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final aTopRight =
            notifier.state.polygons.single.vertexIds[1]; // (100, 0)
        final aBottomRight =
            notifier.state.polygons.single.vertexIds[2]; // (100, 100)

        // A new shape docks onto two of polygon A's vertices in a row —
        // this must not close after the first snap just because it reached
        // 3 points; it should only close once explicitly told to.
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(200, 50), fillColor: Colors.purple);
        notifier.handleDrawTap(
          const Offset(100, 100),
          fillColor: Colors.purple,
        );

        expect(notifier.state.polygons, hasLength(1));
        expect(notifier.state.draftVertexIds, [
          aTopRight,
          notifier.state.draftVertexIds[1],
          aBottomRight,
        ]);

        notifier.closePolygon(Colors.purple);

        expect(notifier.state.polygons, hasLength(2));
        expect(notifier.state.polygons.last.vertexIds.first, aTopRight);
        expect(notifier.state.polygons.last.vertexIds.last, aBottomRight);
      },
    );

    test(
      "double-tapping the draft's own start closes it into a clean loop, "
      'dropping the throwaway first tap of the pair',
      () {
        final notifier = CanvasNotifier();
        // A standalone draft: a start plus two more real points.
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        final startId = notifier.state.draftVertexIds.first;
        notifier.handleDrawTap(const Offset(300, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(
          const Offset(150, 300),
          fillColor: Colors.orange,
        );

        // Double-tap right on the start. The first tap drops a throwaway point
        // next to the start (own points are excluded from drawing-time snaps);
        // the second recognizes the start as the close target, removes that
        // throwaway point, and closes into a clean 3-point loop.
        notifier.handleDrawTap(const Offset(4, 4), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(4, 4), fillColor: Colors.orange);

        expect(notifier.state.polygons, hasLength(1));
        expect(notifier.state.draftVertexIds, isEmpty);
        final closed = notifier.state.polygons.single;
        expect(closed.vertexIds, hasLength(3));
        expect(closed.vertexIds.first, startId);
        expect(
          notifier.state.vertices[closed.vertexIds[1]]!.position,
          const Offset(300, 0),
        );
        expect(
          notifier.state.vertices[closed.vertexIds[2]]!.position,
          const Offset(150, 300),
        );
        // No throwaway vertex near the start leaked into the pool.
        final leaked = notifier.state.vertices.values.any(
          (v) => (v.position - const Offset(4, 4)).distance < 1,
        );
        expect(leaked, isFalse);
      },
    );

    test(
      'double-tapping near a mid draft point (not the start) does not close; '
      'only the start or another polygon closes a shape',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(300, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(
          const Offset(300, 300),
          fillColor: Colors.orange,
        );

        // Double-tap near the (300, 0) mid point — not a valid close target,
        // so it just leaves points instead of closing.
        notifier.handleDrawTap(const Offset(305, 5), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(305, 5), fillColor: Colors.orange);

        expect(notifier.state.polygons, isEmpty);
        expect(notifier.state.draftVertexIds, hasLength(5));
      },
    );

    test(
      'undoing back to an empty draft prunes the unused vertex, and a fresh draft still closes normally via double-tap',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);

        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        final startedVertexId = notifier.state.draftVertexIds.single;
        notifier.undoLastVertex();
        expect(notifier.state.draftVertexIds, isEmpty);
        // That vertex is still shared with polygon A, so it must remain in
        // the pool even though the draft no longer references it.
        expect(notifier.state.vertices.containsKey(startedVertexId), isTrue);

        notifier.handleDrawTap(
          const Offset(500, 500),
          fillColor: Colors.orange,
        );
        final freehandVertexId = notifier.state.draftVertexIds.single;
        notifier.undoLastVertex();
        // This point was never shared with anything, so undoing it removes
        // it from the pool entirely instead of leaving it orphaned.
        expect(notifier.state.vertices.containsKey(freehandVertexId), isFalse);

        notifier.handleDrawTap(
          const Offset(500, 500),
          fillColor: Colors.orange,
        );
        notifier.handleDrawTap(
          const Offset(600, 500),
          fillColor: Colors.orange,
        );
        notifier.handleDrawTap(
          const Offset(550, 600),
          fillColor: Colors.orange,
        );
        notifier.handleDrawTap(
          const Offset(502, 502),
          fillColor: Colors.orange,
        );
        // A single tap never closes, no matter how close to the start —
        // closing only ever happens via double-tap (or the toolbar button).
        notifier.handleDrawTap(
          const Offset(502, 502),
          fillColor: Colors.orange,
        );

        expect(notifier.state.polygons, hasLength(2));
        expect(notifier.state.draftVertexIds, isEmpty);
      },
    );
  });

  group('CanvasNotifier line-segment vertex absorption', () {
    test(
      'a new segment automatically absorbs an existing vertex sitting almost exactly on its line',
      () {
        final notifier = CanvasNotifier();
        // Polygon A has a vertex sitting exactly where a later segment
        // will pass straight through. Its other two corners are spaced
        // well beyond kDoubleTapMaxDistance from each other so placing
        // them doesn't get misread as a pseudo double-tap.
        notifier.handleDrawTap(const Offset(50, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(90, 150), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(10, 150), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final absorbedVertexId =
            notifier.state.polygons.single.vertexIds.first; // (50, 0)

        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);

        expect(notifier.state.draftVertexIds, hasLength(3));
        expect(notifier.state.draftVertexIds[1], absorbedVertexId);
        expect(
          notifier.state.vertices[absorbedVertexId]!.position,
          const Offset(50, 0),
        );
      },
    );

    test('a vertex just outside the absorption tolerance is left alone', () {
      final notifier = CanvasNotifier();
      // 16px away from the (0,0)-(100,0) line: just outside the 15px
      // absorption tolerance.
      notifier.handleDrawTap(const Offset(50, 16), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(90, 150), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(10, 150), fillColor: Colors.green);
      notifier.closePolygon(Colors.green);

      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);

      expect(notifier.state.draftVertexIds, hasLength(2));
    });

    test(
      'absorption never re-inserts a vertex the draft already contains, including its own shared start',
      () {
        final notifier = CanvasNotifier();
        // None of A's other vertices sit anywhere near the (0,0)-(200,0)
        // line used below, so the only vertex that could possibly be
        // (mis-)absorbed here is (0, 0) itself.
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 50), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);

        // Start a new draft from A's vertex at (0, 0), then draw straight
        // back out along the same line. (0, 0) must never be re-inserted
        // into the middle of its own draft.
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.orange);

        expect(notifier.state.draftVertexIds, hasLength(2));
      },
    );
  });

  group('CanvasNotifier pseudo double-tap close', () {
    test(
      "a double-tap onto another polygon's vertex closes by welding onto that exact vertex "
      "(bug C: never snaps back toward the draft's own start)",
      () {
        final notifier = CanvasNotifier();
        // The target polygon supplies the vertex to close onto.
        notifier.handleDrawTap(const Offset(300, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(400, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(
          const Offset(350, 100),
          fillColor: Colors.purple,
        );
        notifier.closePolygon(Colors.purple);
        final targetVertexId =
            notifier.state.polygons.single.vertexIds.first; // (300, 0)

        // A brand new draft, started well away from the target.
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(50, 50), fillColor: Colors.orange);
        // First tap of the pair lands near the target vertex, so the normal
        // single-tap path welds the draft's end onto it (reusing its ID).
        notifier.handleDrawTap(const Offset(300, 5), fillColor: Colors.orange);
        expect(notifier.state.draftVertexIds.last, targetVertexId);

        // Quick second tap in the same spot: closes the shape as-is.
        notifier.handleDrawTap(const Offset(300, 5), fillColor: Colors.orange);

        expect(notifier.state.polygons, hasLength(2));
        expect(notifier.state.draftVertexIds, isEmpty);
        final closed = notifier.state.polygons.last;
        expect(closed.vertexIds, hasLength(3));
        // The shape closed onto the target vertex itself (the same shared
        // ID), NOT back onto its own start — this is the bug-C fix.
        expect(closed.vertexIds.last, targetVertexId);
        expect(closed.vertexIds.first, isNot(targetVertexId));
        // The target polygon is left completely untouched.
        expect(notifier.state.polygons.first.vertexIds, hasLength(3));
        expect(notifier.state.polygons.first.fillColor, Colors.purple);
      },
    );

    test(
      'a double-tap on empty canvas does not close; it just leaves points',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        // Two fast taps on empty space far from the start: no vertex to close
        // onto, so both are kept as ordinary points instead of closing.
        notifier.handleDrawTap(
          const Offset(300, 300),
          fillColor: Colors.orange,
        );
        notifier.handleDrawTap(
          const Offset(300, 300),
          fillColor: Colors.orange,
        );

        expect(notifier.state.polygons, isEmpty);
        expect(notifier.state.draftVertexIds, hasLength(4));
      },
    );

    test(
      'double-tapping the start with too few points does not close',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        // Only two real points: not enough to form a triangle, so double-
        // tapping the start must not close.
        notifier.handleDrawTap(const Offset(3, 3), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(3, 3), fillColor: Colors.orange);

        expect(notifier.state.polygons, isEmpty);
      },
    );

    test(
      'two fast taps placed far apart are treated as independent points, not a double-tap',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(50, 500), fillColor: Colors.orange);
        // Far away from the previous tap, so this must just be a fourth
        // ordinary point rather than a close-here gesture.
        notifier.handleDrawTap(
          const Offset(500, 500),
          fillColor: Colors.orange,
        );

        expect(notifier.state.polygons, isEmpty);
        expect(notifier.state.draftVertexIds, hasLength(4));
      },
    );
  });

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
      'plain straight edge (no boundary to follow)',
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
        // both, so there's no shared arc to trace.
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
  });

  group('CanvasNotifier eraser mode', () {
    test(
      'erasing a vertex from a polygon with more than 3 points shrinks it',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.red);
        notifier.handleDrawTap(const Offset(100, 100), fillColor: Colors.red);
        notifier.handleDrawTap(const Offset(0, 100), fillColor: Colors.red);
        notifier.closePolygon(Colors.red);
        expect(notifier.state.polygons.single.vertexIds, hasLength(4));
        final erasedId =
            notifier.state.polygons.single.vertexIds[2]; // (100, 100)

        notifier.handleEraseTap(const Offset(100, 100));

        expect(notifier.state.polygons, hasLength(1));
        expect(notifier.state.polygons.single.vertexIds, hasLength(3));
        expect(
          notifier.state.polygons.single.vertexIds,
          isNot(contains(erasedId)),
        );
        // Nothing else references it, so it's pruned from the shared pool too.
        expect(notifier.state.vertices.containsKey(erasedId), isFalse);
      },
    );

    test(
      'erasing a vertex from a triangle dissolves it back into the draft',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.blue);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.blue);
        notifier.closePolygon(Colors.blue);

        notifier.handleEraseTap(const Offset(50, 100));

        expect(notifier.state.polygons, isEmpty);
        expect(notifier.state.draftVertexIds, hasLength(2));
      },
    );

    test('erasing with no nearby vertex does nothing', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.teal);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.teal);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.teal);
      notifier.closePolygon(Colors.teal);

      notifier.handleEraseTap(const Offset(500, 500));

      expect(notifier.state.polygons.single.vertexIds, hasLength(3));
    });

    test(
      'erasing a vertex shared with another polygon only detaches it from the erased polygon',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final sharedVertexId =
            notifier.state.polygons.single.vertexIds[1]; // (100, 0)

        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(
          const Offset(150, 100),
          fillColor: Colors.purple,
        );
        notifier.closePolygon(Colors.purple);
        expect(notifier.state.polygons, hasLength(2));

        notifier.handleEraseTap(const Offset(100, 0));

        // One of the two polygons sharing that corner shrinks/dissolves, but
        // the vertex itself survives in the pool because the other polygon
        // (whichever it is) still references it.
        final stillReferenced =
            notifier.state.polygons.any(
              (p) => p.vertexIds.contains(sharedVertexId),
            ) ||
            notifier.state.draftVertexIds.contains(sharedVertexId);
        expect(stillReferenced, isTrue);
        expect(notifier.state.vertices.containsKey(sharedVertexId), isTrue);
      },
    );
  });
}
