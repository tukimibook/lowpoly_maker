import 'dart:typed_data';

import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/artwork_document.dart';
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

ArtworkDocument _document({String id = 'artwork-1', String title = '無題の作品'}) {
  return ArtworkDocument(artwork: Artwork(id: id, title: title));
}

void main() {
  late MemoryFileSystem fs;
  late ArtworkRepository repository;

  setUp(() {
    fs = MemoryFileSystem();
    repository = ArtworkRepository(fileSystem: fs, documentsPath: '/documents');
  });

  group('AutoSaveService.scheduleSave', () {
    test('does not save immediately — only after the debounce period elapses', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_document());

      expect(await repository.readArtwork('artwork-1'), isNull);
    });

    test('saves the artwork document once the debounce period elapses', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_document());
      await Future<void>.delayed(_afterDebounce);

      final restored = await repository.readArtwork('artwork-1');
      expect(restored, isNotNull);
      expect(restored!.artwork.title, '無題の作品');
    });

    test('adds a new 索引ファイル entry for a first-time save', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_document(id: 'artwork-1', title: 'はじめての作品'));
      await Future<void>.delayed(_afterDebounce);

      final index = await repository.readIndex();
      expect(index.artworks, hasLength(1));
      expect(index.artworks.single.id, 'artwork-1');
      expect(index.artworks.single.title, 'はじめての作品');
      expect(index.artworks.single.documentPath, repository.documentPathFor('artwork-1'));
    });

    test('a burst of calls within the debounce window results in exactly one save, '
        'of the LATEST artwork', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_document(title: '1回目'));
      service.scheduleSave(_document(title: '2回目'));
      service.scheduleSave(_document(title: '3回目 (最新)'));
      await Future<void>.delayed(_afterDebounce);

      final restored = await repository.readArtwork('artwork-1');
      expect(restored!.artwork.title, '3回目 (最新)');

      // Exactly one entry in the index too — not three.
      final index = await repository.readIndex();
      expect(index.artworks, hasLength(1));
    });

    test('saving the same artwork id again updates its existing index entry '
        'in place, rather than appending a duplicate', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_document(title: '編集前'));
      await Future<void>.delayed(_afterDebounce);

      service.scheduleSave(_document(title: '編集後'));
      await Future<void>.delayed(_afterDebounce);

      final index = await repository.readIndex();
      expect(index.artworks, hasLength(1));
      expect(index.artworks.single.title, '編集後');
    });

    test('a later scheduleSave for a DIFFERENT artwork keeps both index entries', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_document(id: 'artwork-1', title: '1作目'));
      await Future<void>.delayed(_afterDebounce);
      service.scheduleSave(_document(id: 'artwork-2', title: '2作目'));
      await Future<void>.delayed(_afterDebounce);

      final index = await repository.readIndex();
      expect(index.artworks.map((a) => a.id), containsAll(['artwork-1', 'artwork-2']));
    });
  });

  group('AutoSaveService.flush', () {
    test('saves immediately, without waiting for the debounce period', () async {
      final service = AutoSaveService(repository: repository, debounce: const Duration(minutes: 5));
      addTearDown(service.dispose);

      service.scheduleSave(_document(title: 'kill前の編集'));
      await service.flush();

      final restored = await repository.readArtwork('artwork-1');
      expect(restored!.artwork.title, 'kill前の編集');
    });

    test('an explicit document argument overrides whatever was last scheduled', () async {
      final service = AutoSaveService(repository: repository, debounce: const Duration(minutes: 5));
      addTearDown(service.dispose);

      service.scheduleSave(_document(title: 'スケジュール済み'));
      await service.flush(_document(title: '明示的な引数'));

      final restored = await repository.readArtwork('artwork-1');
      expect(restored!.artwork.title, '明示的な引数');
    });

    test('with nothing ever scheduled and no argument, is a no-op', () async {
      final service = AutoSaveService(repository: repository);
      addTearDown(service.dispose);

      await service.flush();

      expect(await repository.readIndex(), isA<Object>()); // did not throw
      final anyDocumentsDir = await fs.directory('/documents/artworks').exists();
      expect(anyDocumentsDir, isFalse);
    });

    test('cancels a still-pending debounced save so it does not also fire later', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_document(title: '最初の編集'));
      await service.flush(_document(title: 'flush時点の内容'));

      // Wait past where the original debounce would have fired, to prove
      // it was really cancelled rather than merely racing flush's own save.
      await Future<void>.delayed(_afterDebounce);

      final index = await repository.readIndex();
      expect(index.artworks, hasLength(1));
    });
  });

  group('AutoSaveService.cancel / dispose', () {
    test('cancel prevents a pending scheduled save from ever running', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);

      service.scheduleSave(_document());
      service.cancel();
      await Future<void>.delayed(_afterDebounce);

      expect(await repository.readArtwork('artwork-1'), isNull);
    });

    test('dispose prevents a pending scheduled save from ever running', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);

      service.scheduleSave(_document());
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

        service.scheduleSave(_document());
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

      await service.flush(_document());
      // Reaching this line at all is the assertion — flush must not throw.
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

      service.scheduleSave(_document());
      await Future<void>.delayed(_afterDebounce);

      expect(
        await fs.file(repository.thumbnailPathFor('artwork-1')).readAsBytes(),
        bytes,
      );
    });

    test('a null capture result (e.g. canvas not mounted) skips the thumbnail without failing', () async {
      final service = AutoSaveService(
        repository: repository,
        debounce: _testDebounce,
        captureThumbnail: () async => null,
      );
      addTearDown(service.dispose);

      service.scheduleSave(_document());
      await Future<void>.delayed(_afterDebounce);

      expect(await fs.file(repository.thumbnailPathFor('artwork-1')).exists(), isFalse);
      // The document itself still saved successfully.
      expect(await repository.readArtwork('artwork-1'), isNotNull);
    });

    test('a thumbnail capture that throws does not stop the document from saving', () async {
      Object? capturedError;
      final service = AutoSaveService(
        repository: repository,
        debounce: _testDebounce,
        captureThumbnail: () async => throw Exception('render tree not ready'),
        onError: (error, stackTrace) => capturedError = error,
      );
      addTearDown(service.dispose);

      service.scheduleSave(_document());
      await Future<void>.delayed(_afterDebounce);

      expect(await repository.readArtwork('artwork-1'), isNotNull);
      expect(await fs.file(repository.thumbnailPathFor('artwork-1')).exists(), isFalse);
      expect(capturedError, isNotNull);
    });

    test('with no captureThumbnail callback at all, no thumbnail file is written', () async {
      final service = AutoSaveService(repository: repository, debounce: _testDebounce);
      addTearDown(service.dispose);

      service.scheduleSave(_document());
      await Future<void>.delayed(_afterDebounce);

      expect(await fs.file(repository.thumbnailPathFor('artwork-1')).exists(), isFalse);
    });
  });
}
