import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/artwork_document.dart';
import 'package:polygon_art_app/models/artwork_index.dart';
import 'package:polygon_art_app/models/artwork_summary.dart';
import 'package:polygon_art_app/providers/artwork_repository_provider.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/repositories/artwork_repository.dart';
import 'package:polygon_art_app/screens/gallery_screen.dart';

// Every Japanese UI string this file needs to match against is spelled out
// as an explicit `\u{...}` escape (rather than a literal character) so this
// source file stays plain ASCII end to end -- sidesteps any editor/tool
// transport step in this environment mangling multi-byte UTF-8 into "?"
// bytes, which is exactly what happened here earlier. Each constant's
// comment gives its meaning/romanization for readability.
const String _testArtworkTitle =
    '\u{30c6}\u{30b9}\u{30c8}\u{4f5c}\u{54c1}'; // "test sakuhin" - test artwork
const String _defaultArtworkTitle =
    '\u{7121}\u{984c}\u{306e}\u{4f5c}\u{54c1}'; // "mudai no sakuhin" - untitled artwork
const String _emptyGalleryMessage =
    '\u{4f5c}\u{54c1}\u{304c}\u{307e}\u{3060}\u{3042}\u{308a}\u{307e}\u{305b}\u{3093}'; // no artworks yet
const String _deleteConfirmQuestion =
    '\u{4f5c}\u{54c1}\u{3092}\u{524a}\u{9664}\u{3057}\u{307e}\u{3059}\u{304b}\u{ff1f}'; // delete this artwork?
const String _deleteButtonLabel = '\u{524a}\u{9664}'; // delete
const String _cancelButtonLabel = '\u{30ad}\u{30e3}\u{30f3}\u{30bb}\u{30eb}'; // cancel

/// A widget-test-only [ArtworkRepository]: identical file layout/behavior,
/// but its JSON encode/decode runs inline rather than through
/// `compute()`'s real background `Isolate` (see the base class's own class
/// doc for why production uses one). A real `Isolate` never progresses
/// inside `testWidgets`' fake-clock zone, and wrapping every interaction in
/// `WidgetTester.runAsync` to compensate makes `pumpAndSettle` unable to
/// tell a still-loading frame apart from GalleryScreen's tiles endlessly
/// rescheduling paint ? this sidesteps that class of flakiness entirely,
/// exactly like `_ThrowingArtworkRepository`
/// (`test/services/auto_save_service_test.dart`) overrides methods for its
/// own test-only behavior.
class _TestArtworkRepository extends ArtworkRepository {
  _TestArtworkRepository(MemoryFileSystem fs) : _fs = fs, super(fileSystem: fs, documentsPath: '/documents');

  final MemoryFileSystem _fs;

  @override
  Future<ArtworkIndex> readIndex() async {
    final file = _fs.file(_fs.path.join('/documents', 'index.json'));
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
    final file = _fs.file(_fs.path.join('/documents', 'index.json'));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(utf8.encode(jsonEncode(index.toJson())), flush: true);
  }

  @override
  Future<ArtworkDocument?> readArtwork(String id) async {
    final file = _fs.file(documentPathFor(id));
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
    final file = _fs.file(documentPathFor(document.artwork.id));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(utf8.encode(jsonEncode(document.toJson())), flush: true);
  }
}

Future<_TestArtworkRepository> _repositoryWithOneArtwork(MemoryFileSystem fs) async {
  final repository = _TestArtworkRepository(fs);
  await repository.saveArtwork(
    ArtworkDocument(artwork: Artwork.empty(id: 'a1', title: _testArtworkTitle)),
  );
  await repository.writeIndex(
    ArtworkIndex(
      artworks: [
        ArtworkSummary(
          id: 'a1',
          title: _testArtworkTitle,
          updatedAt: DateTime.utc(2026, 7, 20),
          thumbnailPath: repository.thumbnailPathFor('a1'),
          documentPath: repository.documentPathFor('a1'),
        ),
      ],
    ),
  );
  return repository;
}

Widget _appWith(ArtworkRepository repository) {
  return ProviderScope(
    overrides: [artworkRepositoryProvider.overrideWith((ref) async => repository)],
    child: const MaterialApp(home: GalleryScreen()),
  );
}

void main() {
  group('GalleryScreen -- rendering', () {
    testWidgets('shows the empty state when the index has no artworks', (tester) async {
      final repository = _TestArtworkRepository(MemoryFileSystem());

      await tester.pumpWidget(_appWith(repository));
      await tester.pumpAndSettle();

      expect(find.text(_emptyGalleryMessage), findsOneWidget);
    });

    testWidgets('renders one tile per artwork in the index, showing its title', (tester) async {
      final repository = await _repositoryWithOneArtwork(MemoryFileSystem());

      await tester.pumpWidget(_appWith(repository));
      await tester.pumpAndSettle();

      expect(find.text(_testArtworkTitle), findsOneWidget);
      expect(find.byKey(const Key('gallery-tile-a1')), findsOneWidget);
    });

    testWidgets('shows a loading indicator before the index resolves', (tester) async {
      final repository = await _repositoryWithOneArtwork(MemoryFileSystem());

      await tester.pumpWidget(_appWith(repository));
      // Before settling: the FutureProvider hasn't resolved yet.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
    });
  });

  group('GalleryScreen -- new artwork', () {
    testWidgets('tapping the FAB resets canvasProvider and opens the editor', (tester) async {
      final repository = _TestArtworkRepository(MemoryFileSystem());
      final container = ProviderContainer(
        overrides: [artworkRepositoryProvider.overrideWith((ref) async => repository)],
      );
      addTearDown(container.dispose);
      final originalId = container.read(canvasProvider).id;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GalleryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('gallery-new-fab')));
      await tester.pumpAndSettle();

      expect(container.read(canvasProvider).id, isNot(originalId));
      expect(find.text(_defaultArtworkTitle), findsOneWidget); // EditorScreen's AppBar title
    });
  });

  group('GalleryScreen -- open (resume)', () {
    testWidgets('tapping a tile restores the artwork and opens the editor', (tester) async {
      final repository = await _repositoryWithOneArtwork(MemoryFileSystem());
      final container = ProviderContainer(
        overrides: [artworkRepositoryProvider.overrideWith((ref) async => repository)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GalleryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('gallery-tile-a1')));
      await tester.pumpAndSettle();
      // Opening an artwork schedules AutoSave's debounce timer; drain it so
      // the binding does not see a pending Timer after the widget tree is
      // disposed.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(container.read(canvasProvider).id, 'a1');
      expect(find.text(_testArtworkTitle), findsOneWidget); // EditorScreen's AppBar title
    });
  });

  group('GalleryScreen -- delete', () {
    testWidgets('deleting a tile removes it from the grid after confirmation', (tester) async {
      final repository = await _repositoryWithOneArtwork(MemoryFileSystem());

      await tester.pumpWidget(_appWith(repository));
      await tester.pumpAndSettle();
      expect(find.text(_testArtworkTitle), findsOneWidget);

      await tester.tap(find.byKey(const Key('gallery-delete-a1')));
      await tester.pumpAndSettle();
      // Confirmation dialog is now showing.
      expect(find.text(_deleteConfirmQuestion), findsOneWidget);

      await tester.tap(find.text(_deleteButtonLabel));
      await tester.pumpAndSettle();

      expect(find.text(_testArtworkTitle), findsNothing);
      expect(find.text(_emptyGalleryMessage), findsOneWidget);
      expect(await repository.readArtwork('a1'), isNull);
    });

    testWidgets('cancelling the confirmation dialog keeps the artwork', (tester) async {
      final repository = await _repositoryWithOneArtwork(MemoryFileSystem());

      await tester.pumpWidget(_appWith(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('gallery-delete-a1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_cancelButtonLabel));
      await tester.pumpAndSettle();

      expect(find.text(_testArtworkTitle), findsOneWidget);
      expect(await repository.readArtwork('a1'), isNotNull);
    });
  });
}
