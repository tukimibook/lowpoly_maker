import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/vertex.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';

void main() {
  group('CanvasNotifier.loadArtwork (Phase Hγ — gallery 新規作成/開く)', () {
    test('replaces state with the given artwork verbatim', () {
      final notifier = CanvasNotifier();
      final loaded = Artwork(
        id: 'loaded-id',
        title: '読み込んだ作品',
        vertices: const {'v1': Vertex(id: 'v1', position: Offset(1, 2))},
        draftVertexIds: const ['v1'],
      );

      notifier.loadArtwork(loaded);

      expect(notifier.state, loaded);
    });

    test('clears the undo stack — undo() after loading has nothing to revert to', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
      expect(notifier.canUndo, isTrue);

      notifier.loadArtwork(Artwork.empty(id: 'new-id'));

      expect(notifier.canUndo, isFalse);
      expect(notifier.undo(), isFalse);
    });

    test(
      'a later undo() never reaches back into the artwork that was open before loadArtwork',
      () {
        final notifier = CanvasNotifier();
        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
        final previousState = notifier.state;

        notifier.loadArtwork(Artwork.empty(id: 'new-id'));
        notifier.handleDrawTap(const Offset(10, 10), fillColor: Colors.blue);
        notifier.undo();

        expect(notifier.state.id, isNot(previousState.id));
        expect(notifier.state.vertices, isEmpty);
      },
    );

    test('resets pending-tap bookkeeping so a stray double-tap cannot straddle the swap', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);

      notifier.loadArtwork(Artwork.empty(id: 'new-id'));
      // A single tap right after loading must behave as a first tap, not
      // as the second half of a pseudo double-tap referring to the old
      // artwork's point.
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);

      expect(notifier.state.draftVertexIds, hasLength(1));
    });
  });
}
