import 'package:file/memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/artwork_document.dart';
import 'package:polygon_art_app/models/artwork_index.dart';
import 'package:polygon_art_app/models/artwork_summary.dart';
import 'package:polygon_art_app/models/canvas_mode.dart';
import 'package:polygon_art_app/models/draw_mode.dart';
import 'package:polygon_art_app/models/underlay_layout.dart';
import 'package:polygon_art_app/models/underlay_ref.dart';
import 'package:polygon_art_app/providers/artwork_repository_provider.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/providers/detach_cycle_provider.dart';
import 'package:polygon_art_app/providers/gallery_provider.dart';
import 'package:polygon_art_app/providers/polygon_edit_target_provider.dart';
import 'package:polygon_art_app/providers/selected_vertex_provider.dart';
import 'package:polygon_art_app/providers/tessellation_provider.dart';
import 'package:polygon_art_app/providers/underlay_layout_provider.dart';
import 'package:polygon_art_app/providers/underlay_provider.dart';
import 'package:polygon_art_app/repositories/artwork_repository.dart';

ProviderContainer _containerWithRepository(ArtworkRepository repository) {
  final container = ProviderContainer(
    overrides: [artworkRepositoryProvider.overrideWith((ref) async => repository)],
  );
  return container;
}

Artwork _savedArtwork(String id) => Artwork.empty(id: id, title: '保存済み作品');

void main() {
  late MemoryFileSystem fs;
  late ArtworkRepository repository;

  setUp(() {
    fs = MemoryFileSystem();
    repository = ArtworkRepository(fileSystem: fs, documentsPath: '/documents');
  });

  group('artworkIndexProvider', () {
    test('reads the current index from the repository', () async {
      await repository.writeIndex(
        ArtworkIndex(
          artworks: [
            ArtworkSummary(
              id: 'a1',
              title: '作品1',
              updatedAt: DateTime.utc(2026, 7, 20),
              thumbnailPath: repository.thumbnailPathFor('a1'),
              documentPath: repository.documentPathFor('a1'),
            ),
          ],
        ),
      );
      final container = _containerWithRepository(repository);
      addTearDown(container.dispose);

      final index = await container.read(artworkIndexProvider.future);

      expect(index.artworks, hasLength(1));
      expect(index.artworks.single.id, 'a1');
    });
  });

  group('GalleryController.createNewArtwork', () {
    test('gives canvasProvider a brand new, empty artwork with a fresh id', () {
      final container = _containerWithRepository(repository);
      addTearDown(container.dispose);
      final originalId = container.read(canvasProvider).id;

      container.read(galleryControllerProvider).createNewArtwork();

      final artwork = container.read(canvasProvider);
      expect(artwork.id, isNot(originalId));
      expect(artwork.polygons, isEmpty);
      expect(artwork.vertices, isEmpty);
    });

    test('clears any underlay left over from a previously open artwork', () {
      final container = _containerWithRepository(repository);
      addTearDown(container.dispose);
      container.read(underlayProvider.notifier).setImagePath('/tmp/old.jpg');
      container.read(underlayLayoutProvider).setOpacity(0.5);

      container.read(galleryControllerProvider).createNewArtwork();

      expect(container.read(underlayProvider).imagePath, isNull);
      expect(container.read(underlayLayoutProvider).value, UnderlayLayout.initial);
    });

    test(
      'resets editor session UI (tool mode, selection, cycles) to defaults '
      '(defect-fix #5)',
      () {
        final container = _containerWithRepository(repository);
        addTearDown(container.dispose);
        container.read(canvasModeProvider.notifier).state = CanvasMode.eraser;
        container.read(drawModeProvider.notifier).state = DrawMode.trace;
        container.read(selectedVertexProvider.notifier).state = 'v1';
        container.read(editSelectionProvider.notifier).selectPolygon(3);
        container.read(editSelectionProvider.notifier).selectEdge(2);
        container.read(detachCycleIndexProvider.notifier).state = 4;
        container.read(isTessellatingProvider.notifier).state = true;

        container.read(galleryControllerProvider).createNewArtwork();

        expect(container.read(canvasModeProvider), CanvasMode.draw);
        expect(container.read(drawModeProvider), DrawMode.tap);
        expect(container.read(selectedVertexProvider), isNull);
        expect(container.read(editSelectionProvider).polygonIndex, -1);
        expect(container.read(editSelectionProvider).edgeIndex, -1);
        expect(container.read(detachCycleIndexProvider), 0);
        expect(container.read(isTessellatingProvider), isFalse);
      },
    );
  });

  group('GalleryController.openArtwork', () {
    test('restores canvasProvider from the saved document', () async {
      final document = ArtworkDocument(
        artwork: _savedArtwork('saved-1'),
      );
      await repository.saveArtwork(document);
      final container = _containerWithRepository(repository);
      addTearDown(container.dispose);

      final opened = await container.read(galleryControllerProvider).openArtwork('saved-1');

      expect(opened, isTrue);
      expect(container.read(canvasProvider).id, 'saved-1');
      expect(container.read(canvasProvider).title, '保存済み作品');
    });

    test('restores the underlay path and layout when the document has one', () async {
      const layout = UnderlayLayout(offset: Offset(3, 4), scale: 2.0, opacity: 0.4);
      final document = ArtworkDocument(
        artwork: _savedArtwork('saved-2'),
        underlay: UnderlayRef(
          imageRelativePath: 'underlays/saved-2.jpg',
          layout: UnderlayLayoutPersist.fromLayout(layout),
        ),
      );
      await repository.saveArtwork(document);
      final container = _containerWithRepository(repository);
      addTearDown(container.dispose);

      await container.read(galleryControllerProvider).openArtwork('saved-2');

      expect(container.read(underlayProvider).imagePath, '/documents/underlays/saved-2.jpg');
      expect(container.read(underlayLayoutProvider).value, layout);
    });

    test('clears any previous underlay when the opened document has none', () async {
      final document = ArtworkDocument(artwork: _savedArtwork('saved-3'));
      await repository.saveArtwork(document);
      final container = _containerWithRepository(repository);
      addTearDown(container.dispose);
      container.read(underlayProvider.notifier).setImagePath('/tmp/leftover.jpg');

      await container.read(galleryControllerProvider).openArtwork('saved-3');

      expect(container.read(underlayProvider).imagePath, isNull);
      expect(container.read(underlayLayoutProvider).value, UnderlayLayout.initial);
    });

    test(
      'resets editor session UI so a previous eraser/edit mode does not leak '
      'into the reopened artwork (defect-fix #5)',
      () async {
        final document = ArtworkDocument(artwork: _savedArtwork('saved-4'));
        await repository.saveArtwork(document);
        final container = _containerWithRepository(repository);
        addTearDown(container.dispose);
        container.read(canvasModeProvider.notifier).state = CanvasMode.edit;
        container.read(drawModeProvider.notifier).state = DrawMode.trace;
        container.read(selectedVertexProvider.notifier).state = 'stale-vertex';

        await container.read(galleryControllerProvider).openArtwork('saved-4');

        expect(container.read(canvasModeProvider), CanvasMode.draw);
        expect(container.read(drawModeProvider), DrawMode.tap);
        expect(container.read(selectedVertexProvider), isNull);
      },
    );

    test('returns false and leaves providers untouched for a missing id', () async {
      final container = _containerWithRepository(repository);
      addTearDown(container.dispose);
      final originalId = container.read(canvasProvider).id;
      container.read(canvasModeProvider.notifier).state = CanvasMode.eraser;

      final opened = await container.read(galleryControllerProvider).openArtwork('missing');

      expect(opened, isFalse);
      expect(container.read(canvasProvider).id, originalId);
      // Failed open must not clobber session UI either.
      expect(container.read(canvasModeProvider), CanvasMode.eraser);
    });
  });

  group('GalleryController.deleteArtwork', () {
    test('removes the artwork from disk and refreshes artworkIndexProvider', () async {
      await repository.saveArtwork(ArtworkDocument(artwork: _savedArtwork('to-delete')));
      await repository.writeIndex(
        ArtworkIndex(
          artworks: [
            ArtworkSummary(
              id: 'to-delete',
              title: '削除対象',
              updatedAt: DateTime.utc(2026, 7, 20),
              thumbnailPath: repository.thumbnailPathFor('to-delete'),
              documentPath: repository.documentPathFor('to-delete'),
            ),
          ],
        ),
      );
      final container = _containerWithRepository(repository);
      addTearDown(container.dispose);
      expect((await container.read(artworkIndexProvider.future)).artworks, hasLength(1));

      await container.read(galleryControllerProvider).deleteArtwork('to-delete');

      final index = await container.read(artworkIndexProvider.future);
      expect(index.artworks, isEmpty);
      expect(await repository.readArtwork('to-delete'), isNull);
    });
  });
}
