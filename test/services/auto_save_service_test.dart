import 'dart:typed_data';
import 'dart:ui';

import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/artwork_document.dart';
import 'package:polygon_art_app/models/polygon_shape.dart';
import 'package:polygon_art_app/models/underlay_ref.dart';
import 'package:polygon_art_app/models/vertex.dart';
import 'package:polygon_art_app/repositories/artwork_repository.dart';
import 'package:polygon_art_app/services/auto_save_service.dart';

/// A tiny debounce used throughout so tests don't need to wait seconds —
/// real production use (`providers/auto_save_provider.dart`) keeps
/// [AutoSaveService.debounce]'s own default.
const _testDebounce = Duration(milliseconds: 20);

/// Slightly longer than [_testDebounce] so `Future.delayed` calls below are
/// guaranteed to observe the timer having already fired.
const _afterDebounce = Duration(milliseconds: 60);

/// A fake that always fails, so tests can verify [AutoSaveService] never
/// lets a save failure escape as an uncaught exception (Phase Hγ #19) —
/// subclassing (not a hand-rolled interface) matches this codebase's
/// existing fake style (e.g. `_FakeUnderlayPicker` in
/// `test/underlay_provider_test.dart`).
class _ThrowingArtworkRepository extends ArtworkRepository {
  _ThrowingArtworkRepository()
    : super(fileSystem: MemoryFileSystem(), documentsPath: '/documents');

  @override
  Future<void> saveArtwork(ArtworkDocument document) async {
    throw Exception('disk full');
  }
}

/// Empty + default title — [ArtworkDocumentBlank.isBlank] is true.
ArtworkDocument _blankDocument({String id = 'artwork-1'}) {
  return ArtworkDocument(artwork: Artwork.empty(id: id));
}

/// Non-blank by title alone (rename-ready) — still no geometry.
ArtworkDocument _renamedEmptyDocument({
  String id = 'artwork-1',
  String title = 'はじめての作品',
}) {
  return ArtworkDocument(artwork: Artwork(id: id, title: title));
}

ArtworkDocument _documentWithTriangle({String id = 'artwork-1'}) {
  return ArtworkDocument(
    artwork: Artwork(
      id: id,
      title: kDefaultArtworkTitle,
      vertices: {
        'v1': const Vertex(id: 'v1', position: Offset(0, 0)),
        'v2': const Vertex(id: 'v2', position: Offset(10, 0)),
        'v3': const Vertex(id: 'v3', position: Offset(5, 10)),
      },
      polygons: [
        const PolygonShape(
          id: 'p1',
          vertexIds: ['v1', 'v2', 'v3'],
          fillColor: Color(0xFFEF5350),
          strokeColor: Color(0xFF212121),
          strokeWidth: 2.5,
        ),
      ],
    ),
  );
}

ArtworkDocument _documentWithUnderlay({String id = 'artwork-1'}) {
  return ArtworkDocument(
    artwork: Artwork.empty(id: id),
    underlay: UnderlayRef(
      imageRelativePath: 'underlays/$id.jpg',
      layout: UnderlayLayoutPersist.initial,
    ),
  );
}

void main() {
  late MemoryFileSystem fs;
  late ArtworkRepository repository;

  setUp(() {
    fs = MemoryFileSystem();
    repository = ArtworkRepository(fileSystem: fs, documentsPath: '/documents');
  });

  group('ArtworkDocument.isBlank', () {
    test('is true for empty geometry, no underlay, and the default title', () {
      expect(_blankDocument().isBlank, isTrue);
    });

    test('is false when the title differs from kDefaultArtworkTitle', () {
      expect(_renamedEmptyDocument().isBlank, isFalse);
    });

    test('is false when there is a polygon or an underlay', () {
      expect(_documentWithTriangle().isBlank, isFalse);
      expect(_documentWithUnderlay().isBlank, isFalse);
    });
  });

  group('AutoSaveService blank skip (empty-canvas auto-save suppression)', () {
    test(
      'does not persist a blank, never-acknowledged artwork after debounce',
      () async {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.scheduleSave(_blankDocument());
        await Future<void>.delayed(_afterDebounce);

        expect(await repository.readArtwork('artwork-1'), isNull);
        expect((await repository.readIndex()).artworks, isEmpty);
      },
    );

    test('flush of a blank, never-acknowledged artwork is a no-op', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      await service.flush(_blankDocument());

      expect(await repository.readArtwork('artwork-1'), isNull);
      expect((await repository.readIndex()).artworks, isEmpty);
    });

    test('saves a renamed-but-otherwise-empty artwork (rename-ready)', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_renamedEmptyDocument(title: '夕焼け'));
      await Future<void>.delayed(_afterDebounce);

      final restored = await repository.readArtwork('artwork-1');
      expect(restored, isNotNull);
      expect(restored!.artwork.title, '夕焼け');
    });

    test('saves when the document has a polygon', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_documentWithTriangle());
      await Future<void>.delayed(_afterDebounce);

      expect(await repository.readArtwork('artwork-1'), isNotNull);
      expect((await repository.readIndex()).artworks, hasLength(1));
    });

    test('saves when the document has an underlay path only', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_documentWithUnderlay());
      await Future<void>.delayed(_afterDebounce);

      expect(await repository.readArtwork('artwork-1'), isNotNull);
    });

    test(
      'after a successful save, a later blank snapshot of the same id is still saved',
      () async {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.scheduleSave(_documentWithTriangle());
        await Future<void>.delayed(_afterDebounce);
        expect(await repository.readArtwork('artwork-1'), isNotNull);

        service.scheduleSave(_blankDocument());
        await Future<void>.delayed(_afterDebounce);

        final restored = await repository.readArtwork('artwork-1');
        expect(restored, isNotNull);
        expect(restored!.artwork.polygons, isEmpty);
      },
    );

    test(
      'acknowledgePersistedArtwork allows a blank snapshot of that id to save',
      () async {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.acknowledgePersistedArtwork('artwork-1');
        service.scheduleSave(_blankDocument());
        await Future<void>.delayed(_afterDebounce);

        expect(await repository.readArtwork('artwork-1'), isNotNull);
        expect((await repository.readIndex()).artworks.single.id, 'artwork-1');
      },
    );
  });

  group('AutoSaveService.scheduleSave', () {
    test('does not save immediately — only after the debounce period elapses', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_renamedEmptyDocument());

      expect(await repository.readArtwork('artwork-1'), isNull);
    });

    test('saves the artwork document once the debounce period elapses', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_renamedEmptyDocument(title: '保存される作品'));
      await Future<void>.delayed(_afterDebounce);

      final restored = await repository.readArtwork('artwork-1');
      expect(restored, isNotNull);
      expect(restored!.artwork.title, '保存される作品');
    });

    test('adds a new 索引ファイル entry for a first-time save', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_renamedEmptyDocument(id: 'artwork-1', title: 'はじめての作品'));
      await Future<void>.delayed(_afterDebounce);

      final index = await repository.readIndex();
      expect(index.artworks, hasLength(1));
      expect(index.artworks.single.id, 'artwork-1');
      expect(index.artworks.single.title, 'はじめての作品');
      expect(index.artworks.single.documentPath, repository.documentPathFor('artwork-1'));
    });

    test(
      'a burst of calls within the debounce window results in exactly one save, '
      'of the LATEST artwork',
      () async {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument(title: '1回目'));
        service.scheduleSave(_renamedEmptyDocument(title: '2回目'));
        service.scheduleSave(_renamedEmptyDocument(title: '3回目 (最新)'));
        await Future<void>.delayed(_afterDebounce);

        final restored = await repository.readArtwork('artwork-1');
        expect(restored!.artwork.title, '3回目 (最新)');

        final index = await repository.readIndex();
        expect(index.artworks, hasLength(1));
      },
    );

    test(
      'saving the same artwork id again updates its existing index entry '
      'in place, rather than appending a duplicate',
      () async {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument(title: '編集前'));
        await Future<void>.delayed(_afterDebounce);

        service.scheduleSave(_renamedEmptyDocument(title: '編集後'));
        await Future<void>.delayed(_afterDebounce);

        final index = await repository.readIndex();
        expect(index.artworks, hasLength(1));
        expect(index.artworks.single.title, '編集後');
      },
    );

    test('a later scheduleSave for a DIFFERENT artwork keeps both index entries', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_renamedEmptyDocument(id: 'artwork-1', title: '1作目'));
      await Future<void>.delayed(_afterDebounce);
      service.scheduleSave(_renamedEmptyDocument(id: 'artwork-2', title: '2作目'));
      await Future<void>.delayed(_afterDebounce);

      final index = await repository.readIndex();
      expect(index.artworks.map((a) => a.id), containsAll(['artwork-1', 'artwork-2']));
    });
  });

  group('AutoSaveService.flush', () {
    test('saves immediately, without waiting for the debounce period', () async {
      final service = AutoSaveService(
        repository: repository,
        debounce: const Duration(minutes: 5),
      );
      addTearDown(service.dispose);

      service.scheduleSave(_renamedEmptyDocument(title: 'kill前の編集'));
      await service.flush();

      final restored = await repository.readArtwork('artwork-1');
      expect(restored!.artwork.title, 'kill前の編集');
    });

    test('an explicit document argument overrides whatever was last scheduled', () async {
      final service = AutoSaveService(
        repository: repository,
        debounce: const Duration(minutes: 5),
      );
      addTearDown(service.dispose);

      service.scheduleSave(_renamedEmptyDocument(title: 'スケジュール済み'));
      await service.flush(_renamedEmptyDocument(title: '明示的な引数'));

      final restored = await repository.readArtwork('artwork-1');
      expect(restored!.artwork.title, '明示的な引数');
    });

    test('with nothing ever scheduled and no argument, is a no-op', () async {
      final service = AutoSaveService(repository: repository);
      addTearDown(service.dispose);

      await service.flush();

      expect(await repository.readIndex(), isA<Object>());
      final anyDocumentsDir = await fs.directory('/documents/artworks').exists();
      expect(anyDocumentsDir, isFalse);
    });

    test('cancels a still-pending debounced save so it does not also fire later', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_renamedEmptyDocument(title: '最初の編集'));
      await service.flush(_renamedEmptyDocument(title: 'flush時点の内容'));

      await Future<void>.delayed(_afterDebounce);

      final index = await repository.readIndex();
      expect(index.artworks, hasLength(1));
    });
  });

  group('AutoSaveService.cancel / dispose', () {
    test('cancel prevents a pending scheduled save from ever running', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);

      service.scheduleSave(_renamedEmptyDocument());
      service.cancel();
      await Future<void>.delayed(_afterDebounce);

      expect(await repository.readArtwork('artwork-1'), isNull);
    });

    test('dispose prevents a pending scheduled save from ever running', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);

      service.scheduleSave(_renamedEmptyDocument());
      service.dispose();
      await Future<void>.delayed(_afterDebounce);

      expect(await repository.readArtwork('artwork-1'), isNull);
    });
  });

  group('AutoSaveService error handling (Phase Hγ #19)', () {
    test(
      'a save failure is routed to onError instead of crashing (no uncaught exception)',
      () async {
        Object? capturedError;
        final service = AutoSaveService(
          repository: _ThrowingArtworkRepository(),
          debounce: _testDebounce,
          onError: (error, stackTrace) => capturedError = error,
        );
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument());
        await Future<void>.delayed(_afterDebounce);

        expect(capturedError, isNotNull);
        expect(capturedError.toString(), contains('disk full'));
      },
    );

    test('a save failure during flush does not make flush itself throw', () async {
      final service = AutoSaveService(
        repository: _ThrowingArtworkRepository(),
        onError: (error, stackTrace) {},
      );
      addTearDown(service.dispose);

      await service.flush(_renamedEmptyDocument());
    });
  });

  group('AutoSaveService thumbnail capture', () {
    test('saves the captured thumbnail bytes alongside the document', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final service = AutoSaveService(
        repository: repository,
        debounce: _testDebounce,
        captureThumbnail: () async => bytes,
      );
      addTearDown(service.dispose);

      service.scheduleSave(_renamedEmptyDocument());
      await Future<void>.delayed(_afterDebounce);

      expect(
        await fs.file(repository.thumbnailPathFor('artwork-1')).readAsBytes(),
        bytes,
      );
    });

    test(
      'a null capture result (e.g. canvas not mounted) skips the thumbnail without failing',
      () async {
        final service = AutoSaveService(
          repository: repository,
          debounce: _testDebounce,
          captureThumbnail: () async => null,
        );
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument());
        await Future<void>.delayed(_afterDebounce);

        expect(await fs.file(repository.thumbnailPathFor('artwork-1')).exists(), isFalse);
        expect(await repository.readArtwork('artwork-1'), isNotNull);
      },
    );

    test('a thumbnail capture that throws does not stop the document from saving', () async {
      Object? capturedError;
      final service = AutoSaveService(
        repository: repository,
        debounce: _testDebounce,
        captureThumbnail: () async => throw Exception('render tree not ready'),
        onError: (error, stackTrace) => capturedError = error,
      );
      addTearDown(service.dispose);

      service.scheduleSave(_renamedEmptyDocument());
      await Future<void>.delayed(_afterDebounce);

      expect(await repository.readArtwork('artwork-1'), isNotNull);
      expect(await fs.file(repository.thumbnailPathFor('artwork-1')).exists(), isFalse);
      expect(capturedError, isNotNull);
    });

    test('with no captureThumbnail callback at all, no thumbnail file is written', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_renamedEmptyDocument());
      await Future<void>.delayed(_afterDebounce);

      expect(await fs.file(repository.thumbnailPathFor('artwork-1')).exists(), isFalse);
    });
  });
}
