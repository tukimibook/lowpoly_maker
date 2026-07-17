import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';

void main() {
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

  group('CanvasNotifier vertex edit (Phase D)', () {
    test('findVertexNear matches draft vertices as well as confirmed ones', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.red);

      final draftId = notifier.findVertexNear(const Offset(100, 0));
      expect(draftId, notifier.state.draftVertexIds.last);

      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.red);
      notifier.closePolygon(Colors.red);
      final confirmedId = notifier.findVertexNear(const Offset(0, 0));
      expect(confirmedId, isNotNull);
      expect(
        notifier.state.polygons.single.vertexIds,
        contains(confirmedId),
      );
    });

    test('moveVertex updates the shared pool entry in place', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.blue);
      notifier.closePolygon(Colors.blue);

      final vertexId = notifier.state.polygons.single.vertexIds.first;
      notifier.moveVertex(vertexId, const Offset(10, 10));

      expect(notifier.state.vertices[vertexId]!.position, const Offset(10, 10));
    });

    test(
      'moving a welded corner updates every polygon that references that vertex ID',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final sharedId = notifier.state.polygons.single.vertexIds[1];

        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(150, 100), fillColor: Colors.purple);
        notifier.closePolygon(Colors.purple);

        expect(
          notifier.state.polygons.every((p) => p.vertexIds.contains(sharedId)),
          isTrue,
        );

        notifier.moveVertex(sharedId, const Offset(100, 40));

        expect(notifier.state.vertices[sharedId]!.position, const Offset(100, 40));
        for (final polygon in notifier.state.polygons) {
          expect(polygon.vertexIds, contains(sharedId));
        }
      },
    );

    test('undo restores a vertex position after moveVertex', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.orange);
      notifier.closePolygon(Colors.orange);

      final vertexId = notifier.state.polygons.single.vertexIds.first;
      final original = notifier.state.vertices[vertexId]!.position;

      notifier.moveVertex(vertexId, const Offset(25, 25));
      notifier.undo();

      expect(notifier.state.vertices[vertexId]!.position, original);
    });
  });

  group('CanvasNotifier detach and weld (Phase E)', () {
    test(
      'detaching a shared vertex from one polygon lets that polygon move independently',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final sharedId =
            notifier.state.polygons.single.vertexIds[1]; // (100, 0)

        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(
          const Offset(150, 100),
          fillColor: Colors.purple,
        );
        notifier.closePolygon(Colors.purple);
        final purplePolygon = notifier.state.polygons[1];

        final copyId = notifier.detachVertexFromPolygon(
          sharedId,
          purplePolygon.id,
        );
        expect(copyId, isNotNull);
        expect(notifier.state.polygons[0].vertexIds, contains(sharedId));
        expect(notifier.state.polygons[1].vertexIds, contains(copyId));
        expect(notifier.state.polygons[1].vertexIds, isNot(contains(sharedId)));

        notifier.moveVertex(copyId!, const Offset(120, 0));

        expect(
          notifier.state.vertices[sharedId]!.position,
          const Offset(100, 0),
        );
        expect(
          notifier.state.vertices[copyId]!.position,
          const Offset(120, 0),
        );
      },
    );

    test('weldVertices merges two vertices and prunes the removed ID', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.blue);
      notifier.closePolygon(Colors.blue);
      final keepId = notifier.state.polygons.single.vertexIds[1]; // (100, 0)

      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(150, 100), fillColor: Colors.red);
      notifier.closePolygon(Colors.red);
      final mergeId = notifier.detachVertexFromPolygon(
        keepId,
        notifier.state.polygons[1].id,
      )!;

      expect(notifier.weldVertices(keepId, mergeId), isTrue);
      expect(notifier.state.vertices.containsKey(mergeId), isFalse);
      for (final polygon in notifier.state.polygons) {
        expect(polygon.vertexIds, isNot(contains(mergeId)));
        expect(polygon.vertexIds, contains(keepId));
      }
    });

    test('weldVertices rejects merges that would dissolve a polygon', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.teal);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.teal);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.teal);
      notifier.closePolygon(Colors.teal);
      final polygon = notifier.state.polygons.single;
      final keepId = polygon.vertexIds[0];
      final mergeId = polygon.vertexIds[1];

      expect(notifier.weldVertices(keepId, mergeId), isFalse);
      expect(notifier.state.polygons.single.vertexIds, polygon.vertexIds);
      expect(notifier.state.vertices.containsKey(mergeId), isTrue);
    });

    test('undo restores artwork after detach', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
      notifier.closePolygon(Colors.green);
      final sharedId = notifier.state.polygons.single.vertexIds[1];

      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.purple);
      notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.purple);
      notifier.handleDrawTap(
        const Offset(150, 100),
        fillColor: Colors.purple,
      );
      notifier.closePolygon(Colors.purple);
      final beforeDetach = notifier.state;

      notifier.detachVertexFromPolygon(
        sharedId,
        notifier.state.polygons[1].id,
      );
      expect(notifier.undo(), isTrue);
      expect(notifier.state, beforeDetach);
    });

    test('undo restores artwork after weld', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.blue);
      notifier.closePolygon(Colors.blue);
      final keepId = notifier.state.polygons.single.vertexIds[1];

      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(150, 100), fillColor: Colors.red);
      notifier.closePolygon(Colors.red);
      final mergeId = notifier.detachVertexFromPolygon(
        keepId,
        notifier.state.polygons[1].id,
      )!;
      final beforeWeld = notifier.state;

      expect(notifier.weldVertices(keepId, mergeId), isTrue);
      expect(notifier.undo(), isTrue);
      expect(notifier.state, beforeWeld);
    });

    test(
      'detaching a vertex absorbed along a closing edge lets that polygon move independently',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(50, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(90, 300), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(10, 300), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final onLineVertexId =
            notifier.state.polygons.single.vertexIds.first;

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
        final endVertexId = notifier.state.polygons[1].vertexIds.first;

        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
        notifier.handleDrawTap(
          const Offset(0, 300),
          fillColor: Colors.orange,
        );
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
        notifier.closePolygon(Colors.orange);
        final orangePolygon = notifier.state.polygons.last;

        expect(orangePolygon.vertexIds, contains(onLineVertexId));
        expect(notifier.isVertexShared(onLineVertexId), isTrue);

        final copyId = notifier.detachVertexFromPolygon(
          onLineVertexId,
          orangePolygon.id,
        );
        expect(copyId, isNotNull);
        expect(notifier.state.polygons[0].vertexIds, contains(onLineVertexId));
        expect(
          notifier.state.polygons.last.vertexIds,
          isNot(contains(onLineVertexId)),
        );
        expect(notifier.state.polygons.last.vertexIds, contains(copyId));

        notifier.moveVertex(copyId!, const Offset(55, 5));

        expect(
          notifier.state.vertices[onLineVertexId]!.position,
          const Offset(50, 0),
        );
        expect(
          notifier.state.vertices[copyId]!.position,
          const Offset(55, 5),
        );
        expect(
          notifier.state.vertices[endVertexId]!.position,
          const Offset(100, 0),
        );
      },
    );
  });

  group('CanvasNotifier weldVertices figure-8 guard (Phase E+, #7)', () {
    test(
      'weldVertices rejects a merge that would pinch a quadrilateral into '
      'a self-touching figure-8/bowtie',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.teal);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.teal);
        notifier.handleDrawTap(
          const Offset(100, 100),
          fillColor: Colors.teal,
        );
        notifier.handleDrawTap(const Offset(0, 100), fillColor: Colors.teal);
        notifier.closePolygon(Colors.teal);
        final ids = notifier.state.polygons.single.vertexIds;
        final keepId = ids[1]; // (100, 0)
        final mergeId = ids[3]; // (0, 100) — the opposite corner

        expect(notifier.weldVertices(keepId, mergeId), isFalse);
        // Nothing changed: the ring, and both vertices, are left intact.
        expect(notifier.state.polygons.single.vertexIds, ids);
        expect(notifier.state.vertices.containsKey(keepId), isTrue);
        expect(notifier.state.vertices.containsKey(mergeId), isTrue);
      },
    );

    test(
      'weldVertices still allows an ordinary merge between two otherwise '
      'unrelated polygons (no figure-8 introduced)',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.blue);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.blue);
        notifier.closePolygon(Colors.blue);
        final keepId = notifier.state.polygons.single.vertexIds[1];

        notifier.handleDrawTap(const Offset(300, 0), fillColor: Colors.red);
        notifier.handleDrawTap(const Offset(400, 0), fillColor: Colors.red);
        notifier.handleDrawTap(
          const Offset(350, 100),
          fillColor: Colors.red,
        );
        notifier.closePolygon(Colors.red);
        final mergeId = notifier.state.polygons[1].vertexIds[0];

        expect(notifier.weldVertices(keepId, mergeId), isTrue);
        expect(notifier.state.vertices.containsKey(mergeId), isFalse);
      },
    );
  });

  group(
    'CanvasNotifier detachVertexFromDraft coverage (Phase E+, #16)',
    () {
      test(
        'detaching a vertex shared between a confirmed polygon and the '
        'draft lets the draft move independently',
        () {
          final notifier = CanvasNotifier();
          notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
          notifier.handleDrawTap(
            const Offset(100, 0),
            fillColor: Colors.green,
          );
          notifier.handleDrawTap(
            const Offset(50, 100),
            fillColor: Colors.green,
          );
          notifier.closePolygon(Colors.green);
          final sharedId =
              notifier.state.polygons.single.vertexIds[1]; // (100, 0)

          // A brand new draft starts by snapping onto that same vertex —
          // now shared between the confirmed polygon and the in-progress
          // draft.
          notifier.handleDrawTap(
            const Offset(100, 0),
            fillColor: Colors.purple,
          );
          expect(notifier.state.draftVertexIds, [sharedId]);
          expect(notifier.isVertexShared(sharedId), isTrue);

          final copyId = notifier.detachVertexFromDraft(sharedId);
          expect(copyId, isNotNull);
          expect(notifier.state.draftVertexIds, [copyId]);
          expect(
            notifier.state.polygons.single.vertexIds,
            contains(sharedId),
          );
          expect(
            notifier.state.polygons.single.vertexIds,
            isNot(contains(copyId)),
          );

          notifier.moveVertex(copyId!, const Offset(120, 20));

          expect(
            notifier.state.vertices[sharedId]!.position,
            const Offset(100, 0),
          );
          expect(
            notifier.state.vertices[copyId]!.position,
            const Offset(120, 20),
          );
        },
      );

      test(
        'detachVertexFromDraft is a no-op when the vertex is not shared',
        () {
          final notifier = CanvasNotifier();
          notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
          final onlyId = notifier.state.draftVertexIds.single;

          expect(notifier.detachVertexFromDraft(onlyId), isNull);
          expect(notifier.state.draftVertexIds, [onlyId]);
        },
      );

      test(
        'detachVertexFromDraft is a no-op when the draft does not '
        'reference the vertex at all',
        () {
          final notifier = CanvasNotifier();
          notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
          notifier.handleDrawTap(
            const Offset(100, 0),
            fillColor: Colors.green,
          );
          notifier.handleDrawTap(
            const Offset(50, 100),
            fillColor: Colors.green,
          );
          notifier.closePolygon(Colors.green);
          final polygonOnlyId = notifier.state.polygons.single.vertexIds[0];

          notifier.handleDrawTap(
            const Offset(500, 500),
            fillColor: Colors.orange,
          );

          expect(notifier.detachVertexFromDraft(polygonOnlyId), isNull);
        },
      );

      test('undo restores artwork after detachVertexFromDraft', () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(
          const Offset(50, 100),
          fillColor: Colors.green,
        );
        notifier.closePolygon(Colors.green);
        final sharedId = notifier.state.polygons.single.vertexIds[1];

        notifier.handleDrawTap(
          const Offset(100, 0),
          fillColor: Colors.purple,
        );
        final beforeDetach = notifier.state;

        notifier.detachVertexFromDraft(sharedId);
        expect(notifier.undo(), isTrue);
        expect(notifier.state, beforeDetach);
      });
    },
  );

  group(
    'CanvasNotifier findVertexNear preferredVertexId tie-break (2026-07-16)',
    () {
      test(
        'without preferredVertexId, a hit-test right after detaching a '
        'shared vertex can resolve to the ORIGINAL rather than the copy — '
        'reproducing the reported bug (whichever one is referenced by the '
        'later polygon in Artwork.polygons wins the tie)',
        () {
          final notifier = CanvasNotifier();
          notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
          notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
          notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
          notifier.closePolygon(Colors.green);
          final greenPolygon = notifier.state.polygons[0];
          final sharedId = greenPolygon.vertexIds[1]; // (100, 0)

          notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.purple);
          notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.purple);
          notifier.handleDrawTap(const Offset(150, 100), fillColor: Colors.purple);
          notifier.closePolygon(Colors.purple);
          // Purple ends up *after* green in `state.polygons`, and detaching
          // from green (below) leaves purple as the one still holding the
          // original `sharedId` — i.e. purple is the "later" owner.
          expect(notifier.state.polygons[1].vertexIds, contains(sharedId));

          final copyId = notifier.detachVertexFromPolygon(sharedId, greenPolygon.id)!;

          // Both vertices now sit at the exact same spot (100, 0). Without
          // a preference, the hit-test's default "last one wins" resolves
          // to whichever polygon comes later in the list — purple's
          // original `sharedId` — not the copy the artist just created.
          final hit = notifier.findVertexNear(const Offset(100, 0));
          expect(hit, sharedId);
          expect(hit, isNot(copyId));
        },
      );

      test(
        'passing the just-detached copy as preferredVertexId resolves the '
        'coincidence tie toward it, regardless of Artwork.polygons order',
        () {
          final notifier = CanvasNotifier();
          notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
          notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
          notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
          notifier.closePolygon(Colors.green);
          final greenPolygon = notifier.state.polygons[0];
          final sharedId = greenPolygon.vertexIds[1]; // (100, 0)

          notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.purple);
          notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.purple);
          notifier.handleDrawTap(const Offset(150, 100), fillColor: Colors.purple);
          notifier.closePolygon(Colors.purple);

          final copyId = notifier.detachVertexFromPolygon(sharedId, greenPolygon.id)!;

          final hit = notifier.findVertexNear(
            const Offset(100, 0),
            preferredVertexId: copyId,
          );
          expect(hit, copyId);
          expect(hit, isNot(sharedId));
        },
      );

      test(
        'preferredVertexId that is not among the tied candidates does not '
        'change which vertex a genuinely unambiguous hit-test returns',
        () {
          final notifier = CanvasNotifier();
          notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
          notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.blue);
          notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.blue);
          notifier.closePolygon(Colors.blue);
          final onlyVertexId = notifier.state.polygons.single.vertexIds.first;

          final hit = notifier.findVertexNear(
            const Offset(0, 0),
            preferredVertexId: 'does-not-exist',
          );

          expect(hit, onlyVertexId);
        },
      );
    },
  );

  group('CanvasNotifier translatePolygon (edit mode whole-shape drag, 2026-07-16)', () {
    test('shifts every one of the polygon\'s vertices by the same delta', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.blue);
      notifier.closePolygon(Colors.blue);
      final polygonId = notifier.state.polygons.single.id;

      notifier.translatePolygon(polygonId, const Offset(10, 20));

      final positions = notifier.state.polygons.single.vertexIds
          .map((id) => notifier.state.vertices[id]!.position);
      expect(positions, [
        const Offset(10, 20),
        const Offset(110, 20),
        const Offset(60, 120),
      ]);
    });

    test(
      'a corner welded to a neighboring polygon moves for both shapes',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final greenId = notifier.state.polygons.single.id;
        final sharedId = notifier.state.polygons.single.vertexIds[1]; // (100, 0)

        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(150, 100), fillColor: Colors.purple);
        notifier.closePolygon(Colors.purple);
        final purplePolygon = notifier.state.polygons[1];
        final purpleOnlyId = purplePolygon.vertexIds[1]; // (200, 0)

        notifier.translatePolygon(greenId, const Offset(0, 50));

        // The shared corner moved (both shapes now see it at its new spot)...
        expect(notifier.state.vertices[sharedId]!.position, const Offset(100, 50));
        // ...but the purple polygon's *own* unshared vertex did not, since
        // only the green polygon's own vertices were translated.
        expect(notifier.state.vertices[purpleOnlyId]!.position, const Offset(200, 0));
      },
    );

    test('is a no-op for an unknown polygon ID or a zero delta', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.teal);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.teal);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.teal);
      notifier.closePolygon(Colors.teal);
      final before = notifier.state;

      notifier.translatePolygon('does-not-exist', const Offset(5, 5));
      expect(notifier.state, before);

      notifier.translatePolygon(notifier.state.polygons.single.id, Offset.zero);
      expect(notifier.state, before);
    });

    test('undo restores every vertex to its pre-translation position', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.orange);
      notifier.closePolygon(Colors.orange);
      final before = notifier.state;

      notifier.translatePolygon(notifier.state.polygons.single.id, const Offset(30, -10));
      expect(notifier.undo(), isTrue);
      expect(notifier.state, before);
    });
  });

  group('CanvasNotifier insertVertexAtEdge (edit mode "➕", 2026-07-16)', () {
    test('splices a new vertex at the edge\'s midpoint', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(100, 100), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(0, 100), fillColor: Colors.blue);
      notifier.closePolygon(Colors.blue);
      final polygonId = notifier.state.polygons.single.id;
      final originalIds = notifier.state.polygons.single.vertexIds;

      // Edge 0 runs from vertexIds[0] (0,0) to vertexIds[1] (100,0).
      final newId = notifier.insertVertexAtEdge(polygonId, 0);

      expect(newId, isNotNull);
      expect(notifier.state.vertices[newId]!.position, const Offset(50, 0));
      expect(
        notifier.state.polygons.single.vertexIds,
        [originalIds[0], newId, originalIds[1], originalIds[2], originalIds[3]],
      );
    });

    test('wraps around: the last ring index subdivides the closing edge', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(0, 100), fillColor: Colors.green);
      notifier.closePolygon(Colors.green);
      final polygon = notifier.state.polygons.single;
      final lastIndex = polygon.vertexIds.length - 1;

      final newId = notifier.insertVertexAtEdge(polygon.id, lastIndex);

      // The closing edge runs from the last vertex (0,100) back to the
      // first (0,0).
      expect(newId, isNotNull);
      expect(notifier.state.vertices[newId]!.position, const Offset(0, 50));
      expect(notifier.state.polygons.single.vertexIds.last, newId);
    });

    test('the new vertex is unshared, so it belongs only to this polygon', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.blue);
      notifier.closePolygon(Colors.blue);
      final polygonId = notifier.state.polygons.single.id;

      final newId = notifier.insertVertexAtEdge(polygonId, 0)!;

      expect(notifier.isVertexShared(newId), isFalse);
    });

    test('returns null for an unknown polygon or an out-of-range ring index', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.red);
      notifier.closePolygon(Colors.red);
      final polygonId = notifier.state.polygons.single.id;

      expect(notifier.insertVertexAtEdge('does-not-exist', 0), isNull);
      expect(notifier.insertVertexAtEdge(polygonId, -1), isNull);
      expect(notifier.insertVertexAtEdge(polygonId, 99), isNull);
    });

    test('undo removes the inserted vertex and restores the original ring', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.purple);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.purple);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.purple);
      notifier.closePolygon(Colors.purple);
      final before = notifier.state;

      final newId = notifier.insertVertexAtEdge(notifier.state.polygons.single.id, 0);
      expect(notifier.undo(), isTrue);
      expect(notifier.state, before);
      expect(notifier.state.vertices.containsKey(newId), isFalse);
    });
  });

  group('CanvasNotifier deletePolygon (edit mode "🗑️", 2026-07-16)', () {
    test('removes the polygon and prunes its now-unreferenced vertices', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.blue);
      notifier.closePolygon(Colors.blue);
      final polygon = notifier.state.polygons.single;

      notifier.deletePolygon(polygon.id);

      expect(notifier.state.polygons, isEmpty);
      for (final vertexId in polygon.vertexIds) {
        expect(notifier.state.vertices.containsKey(vertexId), isFalse);
      }
    });

    test(
      'a corner welded to another polygon survives deletion for that polygon',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.green);
        notifier.closePolygon(Colors.green);
        final greenPolygon = notifier.state.polygons.single;
        final sharedId = greenPolygon.vertexIds[1]; // (100, 0)

        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(200, 0), fillColor: Colors.purple);
        notifier.handleDrawTap(const Offset(150, 100), fillColor: Colors.purple);
        notifier.closePolygon(Colors.purple);

        notifier.deletePolygon(greenPolygon.id);

        expect(notifier.state.polygons, hasLength(1));
        expect(notifier.state.polygons.single.vertexIds, contains(sharedId));
        expect(notifier.state.vertices.containsKey(sharedId), isTrue);
      },
    );

    test('is a no-op for an unknown polygon ID', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.teal);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.teal);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.teal);
      notifier.closePolygon(Colors.teal);
      final before = notifier.state;

      notifier.deletePolygon('does-not-exist');

      expect(notifier.state, before);
    });

    test('undo restores the deleted polygon and its vertices', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.orange);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.orange);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.orange);
      notifier.closePolygon(Colors.orange);
      final before = notifier.state;

      notifier.deletePolygon(notifier.state.polygons.single.id);
      expect(notifier.undo(), isTrue);
      expect(notifier.state, before);
    });
  });
}
