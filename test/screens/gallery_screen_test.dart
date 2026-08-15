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
import 'package:polygon_art_app/screens/editor_screen.dart';
import 'package:polygon_art_app/services/gallery_quota.dart';

// UI strings matched by this file (English after the global UI pass).
const String _testArtworkTitle = 'Test Artwork';
const String _defaultArtworkTitle = 'Untitled';
const String _emptyGalleryMessage = 'No artworks yet';
const String _deleteConfirmQuestion = 'Delete artwork?';
const String _deleteButtonLabel = 'Delete';
const String _cancelButtonLabel = 'Cancel';


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

  group('GalleryScreen -- quota', () {
    testWidgets(
      'tapping the FAB at the save limit shows a dialog and does not open the editor',
      (tester) async {
        final repository = await _repositoryWithOneArtwork(MemoryFileSystem());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              artworkRepositoryProvider.overrideWith((ref) async => repository),
              galleryQuotaProvider.overrideWith((ref) => const GalleryQuota(baseSlotLimit: 1)),
            ],
            child: const MaterialApp(home: GalleryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('gallery-new-fab')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('gallery-quota-reached-dialog')), findsOneWidget);
        expect(find.text(GalleryQuotaMessages.dialogBody(1)), findsOneWidget);
        expect(find.byType(EditorScreen), findsNothing);
      },
    );
  });
}
