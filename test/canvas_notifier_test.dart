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
      expect(notifier.state.draftVertices, isEmpty);
      expect(notifier.state.polygons.single.vertices, hasLength(3));
    });

    test('tapping near the first vertex auto-closes the polygon', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(2, 2), fillColor: Colors.blue);

      expect(notifier.state.polygons, hasLength(1));
      expect(notifier.state.draftVertices, isEmpty);
    });

    test(
      'tapping a confirmed polygon vertex starts a new draft without altering it',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        expect(notifier.state.polygons, hasLength(1));
        final originalVertices = notifier.state.polygons.single.vertices;

        final matchedColor = notifier.handleDrawTap(
          const Offset(100, 0),
          fillColor: Colors.black,
        );

        expect(matchedColor, Colors.green);
        // The original polygon must remain fully intact: same count, same positions.
        expect(notifier.state.polygons, hasLength(1));
        expect(notifier.state.polygons.single.vertices, hasLength(originalVertices.length));
        for (var i = 0; i < originalVertices.length; i++) {
          expect(notifier.state.polygons.single.vertices[i].position, originalVertices[i].position);
        }
        // A new single-point draft starts at the tapped vertex's position.
        expect(notifier.state.draftVertices, hasLength(1));
        expect(notifier.state.draftVertices.single.position, const Offset(100, 0));
      },
    );

    test('continuing from an existing vertex builds a brand new polygon', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
      notifier.closePolygon(Colors.green);

      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.purple);
      notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.purple);
      notifier.handleDrawTap(const Offset(150, 100), fillColor: Colors.purple);
      notifier.closePolygon(Colors.purple);

      expect(notifier.state.polygons, hasLength(2));
      expect(notifier.state.draftVertices, isEmpty);
      // Original polygon is unchanged.
      expect(notifier.state.polygons.first.vertices, hasLength(3));
      expect(notifier.state.polygons.first.fillColor, Colors.green);
      // New polygon starts at the shared corner and has its own color.
      expect(notifier.state.polygons.last.vertices, hasLength(3));
      expect(notifier.state.polygons.last.vertices.first.position, const Offset(100, 0));
      expect(notifier.state.polygons.last.fillColor, Colors.purple);
    });

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
      'tapping an existing vertex to finish the shape snaps and closes it, leaving both polygons intact',
      () {
        final notifier = CanvasNotifier();
        // Polygon A (the "start" corner).
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);

        // Polygon B (will supply the "end" corner to snap onto).
        notifier.handleDrawTap(const Offset(300, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(400, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(350, 100), fillColor: Colors.purple);
        notifier.closePolygon(Colors.purple);

        expect(notifier.state.polygons, hasLength(2));

        // Start a brand new draft from polygon A's vertex...
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(200, 200), fillColor: Colors.orange);
        // ...and finish it by tapping polygon B's vertex: this should snap
        // onto it and auto-close since it completes 3 points.
        notifier.handleDrawTap(const Offset(300, 0), fillColor: Colors.orange);

        expect(notifier.state.draftVertices, isEmpty);
        expect(notifier.state.polygons, hasLength(3));

        final newPolygon = notifier.state.polygons.last;
        expect(newPolygon.fillColor, Colors.orange);
        expect(newPolygon.vertices, hasLength(3));
        expect(newPolygon.vertices.first.position, const Offset(100, 0));
        expect(newPolygon.vertices.last.position, const Offset(300, 0));

        // Both source polygons remain completely untouched.
        expect(notifier.state.polygons[0].vertices, hasLength(3));
        expect(notifier.state.polygons[0].fillColor, Colors.green);
        expect(notifier.state.polygons[1].vertices, hasLength(3));
        expect(notifier.state.polygons[1].fillColor, Colors.purple);
      },
    );

    test(
      'snapping onto an existing vertex does not close the shape early if too few points',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);

        notifier.handleDrawTap(const Offset(300, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(400, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(350, 100), fillColor: Colors.purple);
        notifier.closePolygon(Colors.purple);

        // Start from polygon A's vertex, then immediately snap onto polygon
        // B's vertex: only 2 points total, not enough to close.
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(300, 0), fillColor: Colors.orange);

        expect(notifier.state.polygons, hasLength(2));
        expect(notifier.state.draftVertices, hasLength(2));
        expect(notifier.state.draftVertices.last.position, const Offset(300, 0));
      },
    );

    test(
      'a draft started from an existing vertex does not auto-close near its own start',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);

        // Start a new draft from polygon A's vertex at (100, 0).
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(250, 50), fillColor: Colors.orange);

        // 22px from the start: inside the old 24px auto-close radius, but
        // outside the 20px "landed on an existing vertex" radius. This used
        // to incorrectly auto-close the shape; it must now just add a
        // normal point instead.
        notifier.handleDrawTap(const Offset(122, 0), fillColor: Colors.orange);

        expect(notifier.state.polygons, hasLength(1));
        expect(notifier.state.draftVertices, hasLength(3));
        expect(notifier.state.draftVertices.last.position, const Offset(122, 0));
      },
    );

    test(
      'undoing back to an empty draft re-enables auto-close for the next shape',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);

        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        notifier.undoLastVertex();
        expect(notifier.state.draftVertices, isEmpty);

        // A fresh draft (not started from an existing vertex) should still
        // support the normal "tap near start to close" shortcut.
        notifier.handleDrawTap(const Offset(500, 500), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(600, 500), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(550, 600), fillColor: Colors.orange);
        notifier.handleDrawTap(const Offset(502, 502), fillColor: Colors.orange);

        expect(notifier.state.polygons, hasLength(2));
        expect(notifier.state.draftVertices, isEmpty);
      },
    );
  });

  group('CanvasNotifier eraser mode', () {
    test('erasing a vertex from a polygon with more than 3 points shrinks it', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(100, 100), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(0, 100), fillColor: Colors.red);
      notifier.closePolygon(Colors.red);
      expect(notifier.state.polygons.single.vertices, hasLength(4));

      notifier.handleEraseTap(const Offset(100, 100));

      expect(notifier.state.polygons, hasLength(1));
      expect(notifier.state.polygons.single.vertices, hasLength(3));
      expect(
        notifier.state.polygons.single.vertices.any((v) => v.position == const Offset(100, 100)),
        isFalse,
      );
    });

    test('erasing a vertex from a triangle dissolves it back into the draft', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.blue);
      notifier.closePolygon(Colors.blue);

      notifier.handleEraseTap(const Offset(50, 100));

      expect(notifier.state.polygons, isEmpty);
      expect(notifier.state.draftVertices, hasLength(2));
    });

    test('erasing with no nearby vertex does nothing', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.teal);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.teal);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.teal);
      notifier.closePolygon(Colors.teal);

      notifier.handleEraseTap(const Offset(500, 500));

      expect(notifier.state.polygons.single.vertices, hasLength(3));
    });
  });
}
