import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';

void main() {
  group('CanvasNotifier undo (Phase D0)', () {
    test('canUndo is false on a fresh canvas and true after the first commit', () {
      final notifier = CanvasNotifier();
      expect(notifier.canUndo, isFalse);

      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
      expect(notifier.canUndo, isTrue);
    });

    test(
      'undoing a close restores the open draft with the same vertices as before',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.red);
        notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.red);
        final draftBeforeClose = List<String>.from(
          notifier.state.draftVertexIds,
        );

        notifier.closePolygon(Colors.red);
        expect(notifier.state.polygons, hasLength(1));
        expect(notifier.state.draftVertexIds, isEmpty);

        expect(notifier.undo(), isTrue);
        expect(notifier.state.polygons, isEmpty);
        expect(notifier.state.draftVertexIds, draftBeforeClose);
      },
    );

    test('undo removes placed draft points one at a time, newest first', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(50, 100), fillColor: Colors.blue);

      expect(notifier.state.draftVertexIds, hasLength(3));

      notifier.undo();
      expect(notifier.state.draftVertexIds, hasLength(2));

      notifier.undo();
      expect(notifier.state.draftVertexIds, hasLength(1));

      notifier.undo();
      expect(notifier.state.draftVertexIds, isEmpty);
      expect(notifier.canUndo, isFalse);
    });

    test('undoing an erase restores the removed vertex on the polygon', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(100, 100), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(0, 100), fillColor: Colors.green);
      notifier.closePolygon(Colors.green);
      final vertexIdsBeforeErase = List<String>.from(
        notifier.state.polygons.single.vertexIds,
      );

      notifier.handleEraseTap(const Offset(100, 100));
      expect(notifier.state.polygons.single.vertexIds, hasLength(3));

      notifier.undo();
      expect(
        notifier.state.polygons.single.vertexIds,
        vertexIdsBeforeErase,
      );
    });
  });

  group('CanvasNotifier undo stack limit (Phase E+, #5)', () {
    test('undo stack is capped so it does not grow without bound', () {
      final notifier = CanvasNotifier();
      // Each tap lands far enough from the previous one that it's never
      // mistaken for a pseudo double-tap close — every call just grows a
      // single ever-longer draft, one undo entry each.
      for (var i = 0; i < kUndoStackLimit + 20; i++) {
        notifier.handleDrawTap(Offset(i * 100.0, 0), fillColor: Colors.red);
      }

      var undoCount = 0;
      while (notifier.undo()) {
        undoCount++;
      }

      // The oldest 20 entries were dropped, so only the cap's worth remain.
      expect(undoCount, kUndoStackLimit);
    });
  });

  group(
    'CanvasNotifier clearDraft / clearAll undo coverage (Phase E+, #15)',
    () {
      test('undo restores the draft after clearDraft', () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.red);
        final draftBeforeClear = List<String>.from(
          notifier.state.draftVertexIds,
        );

        notifier.clearDraft();
        expect(notifier.state.draftVertexIds, isEmpty);

        expect(notifier.undo(), isTrue);
        expect(notifier.state.draftVertexIds, draftBeforeClear);
      });

      test(
        'undo restores polygons, draft, and vertices after clearAll',
        () {
          final notifier = CanvasNotifier();
          notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
          notifier.handleDrawTap(
            const Offset(100, 0),
            fillColor: Colors.blue,
          );
          notifier.handleDrawTap(
            const Offset(50, 100),
            fillColor: Colors.blue,
          );
          notifier.closePolygon(Colors.blue);
          notifier.handleDrawTap(
            const Offset(300, 300),
            fillColor: Colors.orange,
          );
          final beforeClear = notifier.state;

          notifier.clearAll();
          expect(notifier.state.polygons, isEmpty);
          expect(notifier.state.draftVertexIds, isEmpty);
          expect(notifier.state.vertices, isEmpty);

          expect(notifier.undo(), isTrue);
          expect(notifier.state, beforeClear);
        },
      );

      test(
        'clearDraft and clearAll on an already-empty canvas are no-ops and '
        'push no undo entry',
        () {
          final notifier = CanvasNotifier();
          notifier.clearDraft();
          expect(notifier.canUndo, isFalse);

          notifier.clearAll();
          expect(notifier.canUndo, isFalse);
        },
      );
    },
  );
}
