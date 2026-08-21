import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/artwork_document.dart';
import 'package:polygon_art_app/models/polygon_shape.dart';
import 'package:polygon_art_app/models/underlay_ref.dart';
import 'package:polygon_art_app/models/vertex.dart';
import 'package:polygon_art_app/repositories/artwork_repository.dart';
import 'package:polygon_art_app/models/artwork_index.dart';
import 'package:polygon_art_app/models/artwork_summary.dart';
import 'package:polygon_art_app/services/auto_save_service.dart';
import 'package:polygon_art_app/services/gallery_quota.dart';

/// A tiny debounce used throughout so tests don't need to wait seconds —
/// real production use (`providers/auto_save_provider.dart`) keeps
/// [AutoSaveService.debounce]'s own default.
const _testDebounce = Duration(milliseconds: 20);

/// [FakeAsync] のゾーン内で [future] を安全に解決するためのヘルパー。
///
/// `fakeAsync` のゾーンでは `scheduleMicrotask` がインターセプトされるため、
/// 生の `await future` はその継続がフラッシュされずハングする危険がある。
/// `.then()` で結果を退避してから明示的に [FakeAsync.flushMicrotasks] を呼ぶ
/// ことで、常に同期的・確実に結果を取り出せる（`fake_async` 公式READMEの
/// 推奨パターンと同じ）。
T resolveSync<T>(FakeAsync async, Future<T> future) {
  var completed = false;
  T? result;
  Object? error;
  StackTrace? stackTrace;
  future.then(
    (value) {
      result = value;
      completed = true;
    },
    onError: (Object e, StackTrace s) {
      error = e;
      stackTrace = s;
      completed = true;
    },
  );
  async.flushMicrotasks();
  if (!completed) {
    fail('Future did not complete after flushMicrotasks()');
  }
  if (error != null) {
    Error.throwWithStackTrace(error!, stackTrace!);
  }
  return result as T;
}

/// [service.scheduleSave] のデバウンスタイマーを仮想時間で確実に発火させ、
/// `_saveNow` 内の全非同期チェーン（readIndex → saveArtwork → サムネイル →
/// writeIndex）をマイクロタスクレベルまで完全に解決させる。
void elapseDebounce(FakeAsync async, [Duration extra = Duration.zero]) {
  async.elapse(_testDebounce + const Duration(milliseconds: 1) + extra);
  async.flushMicrotasks();
}

/// Production [ArtworkRepository] JSON I/O goes through `compute()` (an
/// Isolate). Isolate replies are delivered on the real event loop and never
/// complete inside a synchronous [fakeAsync] zone, which would make every
/// save appear to hang. This subclass keeps the same on-disk layout via
/// [MemoryFileSystem] but encodes/decodes on the calling zone so
/// [resolveSync] / [elapseDebounce] can drain the whole chain as microtasks.
class _SyncArtworkRepository extends ArtworkRepository {
  // Parent keeps FileSystem private, so this test double must retain its own
  // handle. Super-parameter conversion would drop that reference.
  // ignore: use_super_parameters
  _SyncArtworkRepository({required FileSystem fileSystem, required String documentsPath})
    : _fileSystem = fileSystem,
      super(fileSystem: fileSystem, documentsPath: documentsPath);

  final FileSystem _fileSystem;

  String get _indexPath => _fileSystem.path.join(documentsPath, 'index.json');

  Future<void> _writeAtomicBytes(String path, List<int> bytes) async {
    final target = _fileSystem.file(path);
    await target.parent.create(recursive: true);
    final tempFile = _fileSystem.file('$path.temp');
    await tempFile.writeAsBytes(bytes, flush: true);
    await tempFile.rename(path);
  }

  @override
  Future<ArtworkIndex> readIndex() async {
    final file = _fileSystem.file(_indexPath);
    if (!await file.exists()) return ArtworkIndex.empty();
    try {
      final raw = await file.readAsString();
      return ArtworkIndex.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return ArtworkIndex.empty();
    }
  }

  @override
  Future<void> writeIndex(ArtworkIndex index) async {
    await _writeAtomicBytes(_indexPath, utf8.encode(jsonEncode(index.toJson())));
  }

  @override
  Future<ArtworkDocument?> readArtwork(String id) async {
    final file = _fileSystem.file(documentPathFor(id));
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      return ArtworkDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveArtwork(ArtworkDocument document) async {
    await _writeAtomicBytes(
      documentPathFor(document.artwork.id),
      utf8.encode(jsonEncode(document.toJson())),
    );
  }

  @override
  Future<void> saveThumbnail(String id, Uint8List pngBytes) async {
    await _writeAtomicBytes(thumbnailPathFor(id), pngBytes);
  }
}

/// A fake that always fails, so tests can verify [AutoSaveService] never
/// lets a save failure escape as an uncaught exception (Phase Hγ #19) —
/// subclassing (not a hand-rolled interface) matches this codebase's
/// existing fake style (e.g. `_FakeUnderlayPicker` in
/// `test/underlay_provider_test.dart`).
class _ThrowingArtworkRepository extends _SyncArtworkRepository {
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

Future<void> _seedIndex(ArtworkRepository repository, List<String> ids) async {
  await repository.writeIndex(
    ArtworkIndex(
      artworks: [
        for (final id in ids)
          ArtworkSummary(
            id: id,
            title: id,
            updatedAt: DateTime.utc(2026, 8, 1),
            thumbnailPath: repository.thumbnailPathFor(id),
            documentPath: repository.documentPathFor(id),
          ),
      ],
    ),
  );
}

void main() {
  late MemoryFileSystem fs;
  late ArtworkRepository repository;

  setUp(() {
    fs = MemoryFileSystem();
    repository = _SyncArtworkRepository(fileSystem: fs, documentsPath: '/documents');
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
      () {
        fakeAsync((async) {
          final service = AutoSaveService(repository: repository, debounce: _testDebounce);
          addTearDown(service.dispose);

          service.scheduleSave(_blankDocument());
          elapseDebounce(async);

          expect(resolveSync(async, repository.readArtwork('artwork-1')), isNull);
          expect(resolveSync(async, repository.readIndex()).artworks, isEmpty);
        });
      },
    );

    test('flush of a blank, never-acknowledged artwork is a no-op', () {
      fakeAsync((async) {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        resolveSync(async, service.flush(_blankDocument()));

        expect(resolveSync(async, repository.readArtwork('artwork-1')), isNull);
        expect(resolveSync(async, repository.readIndex()).artworks, isEmpty);
      });
    });

    test('saves a renamed-but-otherwise-empty artwork (rename-ready)', () {
      fakeAsync((async) {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument(title: '夕焼け'));
        elapseDebounce(async);

        final restored = resolveSync(async, repository.readArtwork('artwork-1'));
        expect(restored, isNotNull);
        expect(restored!.artwork.title, '夕焼け');
      });
    });

    test('saves when the document has a polygon', () {
      fakeAsync((async) {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.scheduleSave(_documentWithTriangle());
        elapseDebounce(async);

        expect(resolveSync(async, repository.readArtwork('artwork-1')), isNotNull);
        expect(resolveSync(async, repository.readIndex()).artworks, hasLength(1));
      });
    });

    test('saves when the document has an underlay path only', () {
      fakeAsync((async) {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.scheduleSave(_documentWithUnderlay());
        elapseDebounce(async);

        expect(resolveSync(async, repository.readArtwork('artwork-1')), isNotNull);
      });
    });

    test(
      'after a successful save, a later blank snapshot of the same id is still saved',
      () {
        fakeAsync((async) {
          final service = AutoSaveService(repository: repository, debounce: _testDebounce);
          addTearDown(service.dispose);

          service.scheduleSave(_documentWithTriangle());
          elapseDebounce(async);
          expect(resolveSync(async, repository.readArtwork('artwork-1')), isNotNull);

          service.scheduleSave(_blankDocument());
          elapseDebounce(async);

          final restored = resolveSync(async, repository.readArtwork('artwork-1'));
          expect(restored, isNotNull);
          expect(restored!.artwork.polygons, isEmpty);
        });
      },
    );

    test(
      'acknowledgePersistedArtwork allows a blank snapshot of that id to save',
      () {
        fakeAsync((async) {
          final service = AutoSaveService(repository: repository, debounce: _testDebounce);
          addTearDown(service.dispose);

          service.acknowledgePersistedArtwork('artwork-1');
          service.scheduleSave(_blankDocument());
          elapseDebounce(async);

          expect(resolveSync(async, repository.readArtwork('artwork-1')), isNotNull);
          expect(resolveSync(async, repository.readIndex()).artworks.single.id, 'artwork-1');
        });
      },
    );
  });

  group('AutoSaveService.scheduleSave', () {
    test('does not save immediately — only after the debounce period elapses', () {
      fakeAsync((async) {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument());

        expect(resolveSync(async, repository.readArtwork('artwork-1')), isNull);
      });
    });

    test('saves the artwork document once the debounce period elapses', () {
      fakeAsync((async) {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument(title: '保存される作品'));
        elapseDebounce(async);

        final restored = resolveSync(async, repository.readArtwork('artwork-1'));
        expect(restored, isNotNull);
        expect(restored!.artwork.title, '保存される作品');
      });
    });

    test('adds a new 索引ファイル entry for a first-time save', () {
      fakeAsync((async) {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument(id: 'artwork-1', title: 'はじめての作品'));
        elapseDebounce(async);

        final index = resolveSync(async, repository.readIndex());
        expect(index.artworks, hasLength(1));
        expect(index.artworks.single.id, 'artwork-1');
        expect(index.artworks.single.title, 'はじめての作品');
        expect(index.artworks.single.documentPath, repository.documentPathFor('artwork-1'));
      });
    });

    test(
      'a burst of calls within the debounce window results in exactly one save, '
      'of the LATEST artwork',
      () {
        fakeAsync((async) {
          final service = AutoSaveService(repository: repository, debounce: _testDebounce);
          addTearDown(service.dispose);

          service.scheduleSave(_renamedEmptyDocument(title: '1回目'));
          service.scheduleSave(_renamedEmptyDocument(title: '2回目'));
          service.scheduleSave(_renamedEmptyDocument(title: '3回目 (最新)'));
          elapseDebounce(async);

          final restored = resolveSync(async, repository.readArtwork('artwork-1'));
          expect(restored!.artwork.title, '3回目 (最新)');

          final index = resolveSync(async, repository.readIndex());
          expect(index.artworks, hasLength(1));
        });
      },
    );

    test(
      'saving the same artwork id again updates its existing index entry '
      'in place, rather than appending a duplicate',
      () {
        fakeAsync((async) {
          final service = AutoSaveService(repository: repository, debounce: _testDebounce);
          addTearDown(service.dispose);

          service.scheduleSave(_renamedEmptyDocument(title: '編集前'));
          elapseDebounce(async);

          service.scheduleSave(_renamedEmptyDocument(title: '編集後'));
          elapseDebounce(async);

          final index = resolveSync(async, repository.readIndex());
          expect(index.artworks, hasLength(1));
          expect(index.artworks.single.title, '編集後');
        });
      },
    );

    test('a later scheduleSave for a DIFFERENT artwork keeps both index entries', () {
      fakeAsync((async) {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument(id: 'artwork-1', title: '1作目'));
        elapseDebounce(async);
        service.scheduleSave(_renamedEmptyDocument(id: 'artwork-2', title: '2作目'));
        elapseDebounce(async);

        final index = resolveSync(async, repository.readIndex());
        expect(index.artworks.map((a) => a.id), containsAll(['artwork-1', 'artwork-2']));
      });
    });
  });

  group('AutoSaveService.flush', () {
    test('saves immediately, without waiting for the debounce period', () {
      fakeAsync((async) {
        final service = AutoSaveService(
          repository: repository,
          debounce: const Duration(minutes: 5),
        );
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument(title: 'kill前の編集'));
        resolveSync(async, service.flush());

        final restored = resolveSync(async, repository.readArtwork('artwork-1'));
        expect(restored!.artwork.title, 'kill前の編集');
      });
    });

    test('an explicit document argument overrides whatever was last scheduled', () {
      fakeAsync((async) {
        final service = AutoSaveService(
          repository: repository,
          debounce: const Duration(minutes: 5),
        );
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument(title: 'スケジュール済み'));
        resolveSync(async, service.flush(_renamedEmptyDocument(title: '明示的な引数')));

        final restored = resolveSync(async, repository.readArtwork('artwork-1'));
        expect(restored!.artwork.title, '明示的な引数');
      });
    });

    test('with nothing ever scheduled and no argument, is a no-op', () {
      fakeAsync((async) {
        final service = AutoSaveService(repository: repository);
        addTearDown(service.dispose);

        resolveSync(async, service.flush());

        expect(resolveSync(async, repository.readIndex()), isA<Object>());
        final anyDocumentsDir = resolveSync(async, fs.directory('/documents/artworks').exists());
        expect(anyDocumentsDir, isFalse);
      });
    });

    test('cancels a still-pending debounced save so it does not also fire later', () {
      fakeAsync((async) {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument(title: '最初の編集'));
        resolveSync(async, service.flush(_renamedEmptyDocument(title: 'flush時点の内容')));

        elapseDebounce(async);

        final index = resolveSync(async, repository.readIndex());
        expect(index.artworks, hasLength(1));
      });
    });
  });

  group('AutoSaveService.cancel / dispose', () {
    test('cancel prevents a pending scheduled save from ever running', () {
      fakeAsync((async) {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);

        service.scheduleSave(_renamedEmptyDocument());
        service.cancel();
        elapseDebounce(async);

        expect(resolveSync(async, repository.readArtwork('artwork-1')), isNull);
      });
    });

    test('dispose prevents a pending scheduled save from ever running', () {
      fakeAsync((async) {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);

        service.scheduleSave(_renamedEmptyDocument());
        service.dispose();
        elapseDebounce(async);

        expect(resolveSync(async, repository.readArtwork('artwork-1')), isNull);
      });
    });
  });

  group('AutoSaveService error handling (Phase Hγ #19)', () {
    test(
      'a save failure is routed to onError instead of crashing (no uncaught exception)',
      () {
        fakeAsync((async) {
          Object? capturedError;
          final service = AutoSaveService(
            repository: _ThrowingArtworkRepository(),
            debounce: _testDebounce,
            onError: (error, stackTrace) => capturedError = error,
          );
          addTearDown(service.dispose);

          service.scheduleSave(_renamedEmptyDocument());
          elapseDebounce(async);

          expect(capturedError, isNotNull);
          expect(capturedError.toString(), contains('disk full'));
        });
      },
    );

    test('a save failure during flush does not make flush itself throw', () {
      fakeAsync((async) {
        final service = AutoSaveService(
          repository: _ThrowingArtworkRepository(),
          onError: (error, stackTrace) {},
        );
        addTearDown(service.dispose);

        resolveSync(async, service.flush(_renamedEmptyDocument()));
      });
    });
  });

  group('AutoSaveService thumbnail capture', () {
    test('saves the captured thumbnail bytes alongside the document', () {
      fakeAsync((async) {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final service = AutoSaveService(
          repository: repository,
          debounce: _testDebounce,
          captureThumbnail: () async => bytes,
        );
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument());
        elapseDebounce(async);

        expect(
          resolveSync(async, fs.file(repository.thumbnailPathFor('artwork-1')).readAsBytes()),
          bytes,
        );
      });
    });

    test(
      'a null capture result (e.g. canvas not mounted) skips the thumbnail without failing',
      () {
        fakeAsync((async) {
          final service = AutoSaveService(
            repository: repository,
            debounce: _testDebounce,
            captureThumbnail: () async => null,
          );
          addTearDown(service.dispose);

          service.scheduleSave(_renamedEmptyDocument());
          elapseDebounce(async);

          expect(
            resolveSync(async, fs.file(repository.thumbnailPathFor('artwork-1')).exists()),
            isFalse,
          );
          expect(resolveSync(async, repository.readArtwork('artwork-1')), isNotNull);
        });
      },
    );

    test('a thumbnail capture that throws does not stop the document from saving', () {
      fakeAsync((async) {
        Object? capturedError;
        final service = AutoSaveService(
          repository: repository,
          debounce: _testDebounce,
          captureThumbnail: () async => throw Exception('render tree not ready'),
          onError: (error, stackTrace) => capturedError = error,
        );
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument());
        elapseDebounce(async);

        expect(resolveSync(async, repository.readArtwork('artwork-1')), isNotNull);
        expect(
          resolveSync(async, fs.file(repository.thumbnailPathFor('artwork-1')).exists()),
          isFalse,
        );
        expect(capturedError, isNotNull);
      });
    });

    test('with no captureThumbnail callback at all, no thumbnail file is written', () {
      fakeAsync((async) {
        final service = AutoSaveService(repository: repository, debounce: _testDebounce);
        addTearDown(service.dispose);

        service.scheduleSave(_renamedEmptyDocument());
        elapseDebounce(async);

        expect(
          resolveSync(async, fs.file(repository.thumbnailPathFor('artwork-1')).exists()),
          isFalse,
        );
      });
    });

    test(
      'skips thumbnail capture when allowThumbnailCapture returns false '
      '(underlay referenced but decode pending/error — do not overwrite a good thumb)',
      () {
        fakeAsync((async) {
          final existingThumb = Uint8List.fromList([9, 9, 9]);
          resolveSync(async, repository.saveThumbnail('artwork-1', existingThumb));

          var captureCalls = 0;
          final service = AutoSaveService(
            repository: repository,
            debounce: _testDebounce,
            captureThumbnail: () async {
              captureCalls++;
              return Uint8List.fromList([1, 2, 3]);
            },
            allowThumbnailCapture: (_) => false,
          );
          addTearDown(service.dispose);

          service.scheduleSave(_documentWithUnderlay());
          elapseDebounce(async);

          expect(resolveSync(async, repository.readArtwork('artwork-1')), isNotNull);
          expect(captureCalls, 0);
          expect(
            resolveSync(async, fs.file(repository.thumbnailPathFor('artwork-1')).readAsBytes()),
            existingThumb,
          );
        });
      },
    );

    test(
      'still captures a thumbnail for an underlay document when allowThumbnailCapture is true',
      () {
        fakeAsync((async) {
          final bytes = Uint8List.fromList([4, 5, 6]);
          final service = AutoSaveService(
            repository: repository,
            debounce: _testDebounce,
            captureThumbnail: () async => bytes,
            allowThumbnailCapture: (_) => true,
          );
          addTearDown(service.dispose);

          service.scheduleSave(_documentWithUnderlay());
          elapseDebounce(async);

          expect(
            resolveSync(async, fs.file(repository.thumbnailPathFor('artwork-1')).readAsBytes()),
            bytes,
          );
        });
      },
    );
  });

  group('AutoSaveService gallery quota', () {
    const atLimit = GalleryQuota(baseSlotLimit: 1);

    test(
      'refuses the first persist of a new id when the index is at the limit',
      () {
        fakeAsync((async) {
          resolveSync(async, _seedIndex(repository, ['existing']));
          Object? capturedError;
          final service = AutoSaveService(
            repository: repository,
            debounce: _testDebounce,
            currentQuota: () => atLimit,
            onError: (error, stackTrace) => capturedError = error,
          );
          addTearDown(service.dispose);

          service.scheduleSave(_documentWithTriangle(id: 'new-id'));
          elapseDebounce(async);

          expect(capturedError, isA<GalleryQuotaExceededException>());
          expect(resolveSync(async, repository.readArtwork('new-id')), isNull);
          expect(
            resolveSync(async, repository.readIndex()).artworks.map((a) => a.id),
            ['existing'],
          );
        });
      },
    );

    test(
      'allows overwriting an id that is already in the on-disk index, even at the limit',
      () {
        fakeAsync((async) {
          resolveSync(async, _seedIndex(repository, ['artwork-1']));
          final service = AutoSaveService(
            repository: repository,
            debounce: _testDebounce,
            currentQuota: () => atLimit,
          );
          addTearDown(service.dispose);

          service.scheduleSave(_renamedEmptyDocument(title: '上書き'));
          elapseDebounce(async);

          final restored = resolveSync(async, repository.readArtwork('artwork-1'));
          expect(restored!.artwork.title, '上書き');
          expect(resolveSync(async, repository.readIndex()).artworks, hasLength(1));
        });
      },
    );

    test(
      'treats on-disk index membership as authoritative, not acknowledgePersistedArtwork',
      () {
        fakeAsync((async) {
          resolveSync(async, _seedIndex(repository, ['existing']));
          Object? capturedError;
          final service = AutoSaveService(
            repository: repository,
            debounce: _testDebounce,
            currentQuota: () => atLimit,
            onError: (error, stackTrace) => capturedError = error,
          );
          addTearDown(service.dispose);

          service.acknowledgePersistedArtwork('new-id');
          service.scheduleSave(_documentWithTriangle(id: 'new-id'));
          elapseDebounce(async);

          expect(capturedError, isA<GalleryQuotaExceededException>());
          expect(resolveSync(async, repository.readArtwork('new-id')), isNull);
        });
      },
    );

    test('flush rethrows GalleryQuotaExceededException so exit can be blocked', () {
      fakeAsync((async) {
        resolveSync(async, _seedIndex(repository, ['existing']));
        final service = AutoSaveService(
          repository: repository,
          currentQuota: () => atLimit,
          onError: (error, stackTrace) {},
        );
        addTearDown(service.dispose);

        expect(
          () => resolveSync(async, service.flush(_documentWithTriangle(id: 'new-id'))),
          throwsA(isA<GalleryQuotaExceededException>()),
        );
        expect(resolveSync(async, repository.readArtwork('new-id')), isNull);
      });
    });

    test('flush of a blank never-persisted artwork is still a no-op at the limit', () {
      fakeAsync((async) {
        resolveSync(async, _seedIndex(repository, ['existing']));
        final service = AutoSaveService(
          repository: repository,
          currentQuota: () => atLimit,
        );
        addTearDown(service.dispose);

        resolveSync(async, service.flush(_blankDocument(id: 'new-id')));

        expect(resolveSync(async, repository.readArtwork('new-id')), isNull);
        expect(
          resolveSync(async, repository.readIndex()).artworks.map((a) => a.id),
          ['existing'],
        );
      });
    });
  });
}
