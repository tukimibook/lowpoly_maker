import 'dart:typed_data';

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/artwork_document.dart';
import 'package:polygon_art_app/models/artwork_index.dart';
import 'package:polygon_art_app/models/artwork_summary.dart';
import 'package:polygon_art_app/models/polygon_shape.dart';
import 'package:polygon_art_app/models/underlay_layout.dart';
import 'package:polygon_art_app/models/vertex.dart';
import 'package:polygon_art_app/repositories/artwork_repository.dart';

/// Stand-in for a PNG's worth of bytes — real thumbnail encoding is a
/// UI/rendering concern outside this repository (see its class doc); the
/// repository only needs to move bytes around correctly.
final Uint8List _fakePngBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

Artwork _sampleArtwork({String id = 'artwork-1'}) {
  return Artwork(
    id: id,
    title: 'テスト作品',
    vertices: const {
      'v1': Vertex(id: 'v1', position: Offset(0, 0)),
      'v2': Vertex(id: 'v2', position: Offset(100, 0)),
      'v3': Vertex(id: 'v3', position: Offset(50, 100)),
    },
    polygons: const [
      PolygonShape(
        id: 'p1',
        vertexIds: ['v1', 'v2', 'v3'],
        fillColor: Color(0xFFEF5350),
        strokeColor: Color(0xFF212121),
        strokeWidth: 2.5,
      ),
    ],
  );
}

ArtworkDocument _sampleDocument({
  String id = 'artwork-1',
  String? underlayImagePath,
  UnderlayLayout? underlayLayout,
}) {
  return ArtworkDocument(
    artwork: _sampleArtwork(id: id),
    underlayImagePath: underlayImagePath,
    underlayLayout: underlayLayout,
  );
}

void main() {
  late MemoryFileSystem fs;
  late ArtworkRepository repository;

  setUp(() {
    fs = MemoryFileSystem();
    repository = ArtworkRepository(fileSystem: fs, documentsPath: '/documents');
  });

  group('ArtworkRepository — index file', () {
    test('readIndex returns an empty index when index.json does not exist yet', () async {
      final index = await repository.readIndex();

      expect(index.artworks, isEmpty);
    });

    test('writeIndex then readIndex round-trips every summary', () async {
      final index = ArtworkIndex(
        artworks: [
          ArtworkSummary(
            id: 'a1',
            title: '作品1',
            updatedAt: DateTime.utc(2026, 7, 20),
            thumbnailPath: repository.thumbnailPathFor('a1'),
            documentPath: repository.documentPathFor('a1'),
          ),
        ],
      );

      await repository.writeIndex(index);
      final restored = await repository.readIndex();

      expect(restored, index);
    });

    test('writeIndex leaves no leftover .temp file after a successful write', () async {
      await repository.writeIndex(ArtworkIndex.empty());

      expect(await fs.file('/documents/index.json.temp').exists(), isFalse);
      expect(await fs.file('/documents/index.json').exists(), isTrue);
    });

    test('writeIndex overwrites a previous index rather than appending', () async {
      await repository.writeIndex(
        ArtworkIndex(
          artworks: [
            ArtworkSummary(
              id: 'old',
              title: '古い作品',
              updatedAt: DateTime.utc(2026, 1, 1),
              thumbnailPath: repository.thumbnailPathFor('old'),
              documentPath: repository.documentPathFor('old'),
            ),
          ],
        ),
      );

      await repository.writeIndex(ArtworkIndex.empty());
      final restored = await repository.readIndex();

      expect(restored.artworks, isEmpty);
    });

    test('readIndex returns an empty index (not a throw) for corrupted JSON', () async {
      await fs.file('/documents/index.json').create(recursive: true);
      await fs.file('/documents/index.json').writeAsString('{ not valid json');

      final index = await repository.readIndex();

      expect(index.artworks, isEmpty);
    });
  });

  group('ArtworkRepository — ArtworkDocument', () {
    test('readArtwork returns null when no document exists for that id', () async {
      expect(await repository.readArtwork('missing'), isNull);
    });

    test('saveArtwork then readArtwork round-trips the geometry', () async {
      final document = _sampleDocument();

      await repository.saveArtwork(document);
      final restored = await repository.readArtwork(document.artwork.id);

      expect(restored!.artwork, document.artwork);
      expect(restored.underlayImagePath, isNull);
      expect(restored.underlayLayout, isNull);
    });

    test('saveArtwork then readArtwork round-trips the underlay reference too', () async {
      const layout = UnderlayLayout(offset: Offset(10, 20), scale: 0.5, opacity: 0.7);
      final document = _sampleDocument(
        underlayImagePath: '/documents/underlays/artwork-1.jpg',
        underlayLayout: layout,
      );

      await repository.saveArtwork(document);
      final restored = await repository.readArtwork(document.artwork.id);

      expect(restored!.underlayImagePath, document.underlayImagePath);
      expect(restored.underlayLayout, layout);
    });

    test('saveArtwork creates the artworks/ directory on first save', () async {
      expect(await fs.directory('/documents/artworks').exists(), isFalse);

      await repository.saveArtwork(_sampleDocument());

      expect(await fs.directory('/documents/artworks').exists(), isTrue);
    });

    test('saveArtwork leaves no leftover .temp file after a successful write', () async {
      final document = _sampleDocument();

      await repository.saveArtwork(document);

      final id = document.artwork.id;
      expect(await fs.file('${repository.documentPathFor(id)}.temp').exists(), isFalse);
      expect(await fs.file(repository.documentPathFor(id)).exists(), isTrue);
    });

    test('saving the same id twice overwrites the document (not two files)', () async {
      await repository.saveArtwork(_sampleDocument(id: 'artwork-1'));
      final edited = ArtworkDocument(
        artwork: _sampleArtwork(id: 'artwork-1').copyWith(title: '編集後'),
      );

      await repository.saveArtwork(edited);
      final restored = await repository.readArtwork('artwork-1');

      expect(restored!.artwork.title, '編集後');
    });

    test('readArtwork returns null (not a throw) for a corrupted document', () async {
      final path = repository.documentPathFor('broken');
      await fs.file(path).create(recursive: true);
      await fs.file(path).writeAsString('not json at all');

      expect(await repository.readArtwork('broken'), isNull);
    });

    test('deleteArtworkDocument removes an existing document', () async {
      final document = _sampleDocument();
      await repository.saveArtwork(document);

      await repository.deleteArtworkDocument(document.artwork.id);

      expect(await repository.readArtwork(document.artwork.id), isNull);
    });

    test('deleteArtworkDocument on a never-saved id is a silent no-op', () async {
      await repository.deleteArtworkDocument('never-existed');
      // No exception thrown — that's the assertion.
    });
  });

  group('ArtworkRepository — thumbnail', () {
    test('saveThumbnail writes the given bytes to thumbnailPathFor(id)', () async {
      await repository.saveThumbnail('artwork-1', _fakePngBytes);

      final path = repository.thumbnailPathFor('artwork-1');
      expect(await fs.file(path).readAsBytes(), _fakePngBytes);
    });

    test('saveThumbnail leaves no leftover .temp file', () async {
      await repository.saveThumbnail('artwork-1', _fakePngBytes);

      expect(
        await fs.file('${repository.thumbnailPathFor('artwork-1')}.temp').exists(),
        isFalse,
      );
    });

    test('saveThumbnail creates the thumbnails/ directory on first save', () async {
      expect(await fs.directory('/documents/thumbnails').exists(), isFalse);

      await repository.saveThumbnail('artwork-1', _fakePngBytes);

      expect(await fs.directory('/documents/thumbnails').exists(), isTrue);
    });

    test('deleteThumbnail removes an existing thumbnail', () async {
      await repository.saveThumbnail('artwork-1', _fakePngBytes);

      await repository.deleteThumbnail('artwork-1');

      expect(await fs.file(repository.thumbnailPathFor('artwork-1')).exists(), isFalse);
    });

    test('deleteThumbnail on a never-saved id is a silent no-op', () async {
      await repository.deleteThumbnail('never-existed');
      // No exception thrown — that's the assertion.
    });
  });

  group('ArtworkRepository — deleteArtwork (composite, gallery 削除)', () {
    test('removes the document, the thumbnail, and the index entry together', () async {
      final document = _sampleDocument();
      await repository.saveArtwork(document);
      await repository.saveThumbnail(document.artwork.id, _fakePngBytes);
      await repository.writeIndex(
        ArtworkIndex(
          artworks: [
            ArtworkSummary(
              id: document.artwork.id,
              title: document.artwork.title,
              updatedAt: DateTime.utc(2026, 7, 20),
              thumbnailPath: repository.thumbnailPathFor(document.artwork.id),
              documentPath: repository.documentPathFor(document.artwork.id),
            ),
          ],
        ),
      );

      await repository.deleteArtwork(document.artwork.id);

      expect(await repository.readArtwork(document.artwork.id), isNull);
      expect(await fs.file(repository.thumbnailPathFor(document.artwork.id)).exists(), isFalse);
      expect((await repository.readIndex()).artworks, isEmpty);
    });

    test('leaves other artworks in the index untouched', () async {
      await repository.writeIndex(
        ArtworkIndex(
          artworks: [
            ArtworkSummary(
              id: 'keep',
              title: '残す作品',
              updatedAt: DateTime.utc(2026, 7, 20),
              thumbnailPath: repository.thumbnailPathFor('keep'),
              documentPath: repository.documentPathFor('keep'),
            ),
            ArtworkSummary(
              id: 'remove',
              title: '削除する作品',
              updatedAt: DateTime.utc(2026, 7, 20),
              thumbnailPath: repository.thumbnailPathFor('remove'),
              documentPath: repository.documentPathFor('remove'),
            ),
          ],
        ),
      );

      await repository.deleteArtwork('remove');

      final index = await repository.readIndex();
      expect(index.artworks.map((a) => a.id), ['keep']);
    });

    test('deleting an id that is not in the index is a silent no-op on the index itself', () async {
      await repository.deleteArtwork('never-existed');

      expect((await repository.readIndex()).artworks, isEmpty);
    });
  });

  group('ArtworkRepository — underlay photo copy', () {
    test(
      'copyUnderlayImage copies the source bytes into underlays/, preserving the extension',
      () async {
        await fs.file('/gallery/photo.jpg').create(recursive: true);
        await fs.file('/gallery/photo.jpg').writeAsBytes([9, 9, 9]);

        final destinationPath = await repository.copyUnderlayImage(
          artworkId: 'artwork-1',
          sourcePath: '/gallery/photo.jpg',
        );

        expect(destinationPath, endsWith('.jpg'));
        expect(await fs.file(destinationPath).readAsBytes(), [9, 9, 9]);
        // The original is left untouched, at its own path (a copy, not a move).
        expect(await fs.file('/gallery/photo.jpg').exists(), isTrue);
      },
    );

    test('copyUnderlayImage leaves no leftover .temp file', () async {
      await fs.file('/gallery/photo.png').create(recursive: true);
      await fs.file('/gallery/photo.png').writeAsBytes([1]);

      final destinationPath = await repository.copyUnderlayImage(
        artworkId: 'artwork-1',
        sourcePath: '/gallery/photo.png',
      );

      expect(await fs.file('$destinationPath.temp').exists(), isFalse);
    });
  });
}
