import 'dart:async';
import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';
import 'package:polygon_art_app/models/artwork_document.dart';
import 'package:polygon_art_app/models/artwork_index.dart';
import 'package:polygon_art_app/models/artwork_summary.dart';
import 'package:polygon_art_app/providers/artwork_repository_provider.dart';
import 'package:polygon_art_app/providers/gallery_provider.dart';
import 'package:polygon_art_app/repositories/artwork_repository.dart';
import 'package:polygon_art_app/screens/editor_screen.dart';
import 'package:polygon_art_app/screens/gallery_screen.dart';
import 'package:polygon_art_app/screens/home_screen.dart';
import 'package:polygon_art_app/services/gallery_quota.dart';
import 'package:polygon_art_app/widgets/canvas/polygon_painter.dart';

/// A widget-test-only [ArtworkRepository] — see the identically-named class
/// in `test/screens/gallery_screen_test.dart` for why: JSON encode/decode
/// runs inline rather than through `compute()`'s real background `Isolate`
/// (which never progresses inside `testWidgets`' fake-clock zone).
class _TestArtworkRepository extends ArtworkRepository {
  _TestArtworkRepository(MemoryFileSystem fs)
    : _fs = fs,
      super(fileSystem: fs, documentsPath: '/documents');

  final MemoryFileSystem _fs;

  int saveArtworkCallCount = 0;

  /// Awaited inside [saveArtwork] before it returns — lets a test hold the
  /// forced save in flight (via a [Completer]) to observe the exit
  /// button's disabled/spinner state, and that a second tap while it's
  /// still pending never triggers a second, overlapping save.
  Future<void> Function()? onSave;

  @override
  Future<ArtworkIndex> readIndex() async {
    final file = _fs.file(_fs.path.join('/documents', 'index.json'));
    if (!await file.exists()) return ArtworkIndex.empty();
    final raw = await file.readAsString();
    return ArtworkIndex.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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
    final raw = await file.readAsString();
    return ArtworkDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> saveArtwork(ArtworkDocument document) async {
    saveArtworkCallCount++;
    if (onSave != null) await onSave!();
    final file = _fs.file(documentPathFor(document.artwork.id));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(utf8.encode(jsonEncode(document.toJson())), flush: true);
  }
}

/// Finds the canvas's own [CustomPaint] specifically — see
/// `test/widget_test.dart`'s identical helper for why `find.byType` alone
/// isn't specific enough once the tree grows past a bare editor screen.
Finder _canvasCustomPaintFinder() {
  return find.byWidgetPredicate((widget) {
    return widget is CustomPaint && widget.painter is PolygonPainter;
  });
}

Finder _iconButtonByTooltip(String tooltip) {
  return find.byWidgetPredicate((widget) {
    return widget is IconButton && widget.tooltip == tooltip;
  });
}

Future<void> _drawOneTriangle(WidgetTester tester) async {
  final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
  await tester.tapAt(canvasTopLeft + const Offset(50, 50));
  await tester.pump();
  await tester.tapAt(canvasTopLeft + const Offset(150, 50));
  await tester.pump();
  await tester.tapAt(canvasTopLeft + const Offset(100, 150));
  await tester.pump();
  await tester.tap(_iconButtonByTooltip('Close shape'));
  await tester.pumpAndSettle();
}

Finder _homeExitButtonFinder() => find.byKey(const Key('save-and-go-home-button'));
Finder _galleryExitButtonFinder() =>
    find.byKey(const Key('save-and-go-gallery-button'));

void main() {
  Future<_TestArtworkRepository> pumpEditorFromHome(
    WidgetTester tester, {
    required _TestArtworkRepository repository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [artworkRepositoryProvider.overrideWith((ref) async => repository)],
        child: const PolygonArtApp(),
      ),
    );
    // Reaches `EditorScreen` via `HomeScreen`'s direct shortcut (no
    // `GalleryScreen` beneath it in the stack yet) — the path most likely
    // to be broken by a naive `Navigator.pop()`-based "back" button.
    await tester.tap(find.text('New Artwork'));
    await tester.pumpAndSettle();
    return repository;
  }

  Future<_TestArtworkRepository> pumpEditorViaGallery(
    WidgetTester tester, {
    required _TestArtworkRepository repository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [artworkRepositoryProvider.overrideWith((ref) async => repository)],
        child: const PolygonArtApp(),
      ),
    );
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gallery-new-fab')));
    await tester.pumpAndSettle();
    return repository;
  }

  group('EditorScreen exit buttons', () {
    testWidgets(
      'Home button forces an immediate save and returns to HomeScreen, '
      'popping back to the first route',
      (tester) async {
        final repository = _TestArtworkRepository(MemoryFileSystem());
        await pumpEditorFromHome(tester, repository: repository);
        await _drawOneTriangle(tester);

        expect(find.byType(EditorScreen), findsOneWidget);
        expect(_iconButtonByTooltip('Return to Home'), findsOneWidget);
        expect(_iconButtonByTooltip('Go to Gallery'), findsOneWidget);
        // The forced save's thumbnail capture goes through a real
        // `RenderRepaintBoundary.toImage()`/`toByteData()` round trip, which
        // (like `compute()` elsewhere in this app — see `widget_test.dart`'s
        // tessellation tests) never progresses inside `testWidgets`' fake-async
        // zone without `runAsync`.
        await tester.runAsync(() async {
          await tester.tap(_homeExitButtonFinder());
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(EditorScreen), findsNothing);
        expect(repository.saveArtworkCallCount, 1);

        final index = await repository.readIndex();
        expect(index.artworks, hasLength(1));
        final saved = await repository.readArtwork(index.artworks.single.id);
        expect(saved!.artwork.polygons, hasLength(1));
      },
    );

    testWidgets(
      'Gallery button from Home→Editor (no Gallery in stack) saves and '
      'opens GalleryScreen',
      (tester) async {
        final repository = _TestArtworkRepository(MemoryFileSystem());
        await pumpEditorFromHome(tester, repository: repository);
        await _drawOneTriangle(tester);

        await tester.runAsync(() async {
          await tester.tap(_galleryExitButtonFinder());
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
        await tester.pumpAndSettle();

        expect(find.byType(GalleryScreen), findsOneWidget);
        expect(find.byType(EditorScreen), findsNothing);
        expect(repository.saveArtworkCallCount, 1);
      },
    );

    testWidgets(
      'Gallery button from Home→Gallery→Editor pops back to the existing '
      'GalleryScreen without stacking a second one',
      (tester) async {
        final repository = _TestArtworkRepository(MemoryFileSystem());
        await pumpEditorViaGallery(tester, repository: repository);
        await _drawOneTriangle(tester);

        expect(find.byType(EditorScreen), findsOneWidget);

        await tester.runAsync(() async {
          await tester.tap(_galleryExitButtonFinder());
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
        await tester.pumpAndSettle();

        expect(find.byType(GalleryScreen), findsOneWidget);
        expect(find.byType(EditorScreen), findsNothing);
        expect(repository.saveArtworkCallCount, 1);

        // One more pop should reveal Home — proving Gallery was the route
        // we stopped on, not a freshly-pushed replacement of the root.
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.pop();
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets(
      'disables both exit buttons and shows a spinner on the pressed one '
      'while the forced save is still in flight, and ignores further taps '
      'until it completes',
      (tester) async {
        final saveGate = Completer<void>();
        final repository = _TestArtworkRepository(MemoryFileSystem())
          ..onSave = () => saveGate.future;
        await pumpEditorFromHome(tester, repository: repository);
        // Must have content — a blank new canvas is skipped by auto-save and
        // would complete flush synchronously (no spinner / no saveArtwork).
        await _drawOneTriangle(tester);

        await tester.tap(_homeExitButtonFinder());
        await tester.pump(); // Don't settle: the save never completes yet.

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final homeButton = tester.widget<IconButton>(_homeExitButtonFinder());
        final galleryButton =
            tester.widget<IconButton>(_galleryExitButtonFinder());
        expect(homeButton.onPressed, isNull);
        expect(galleryButton.onPressed, isNull);

        // A second tap while disabled is a no-op at the framework level
        // (a disabled `IconButton` doesn't fire `onPressed`) — this is the
        // actual multi-tap-prevention guarantee under test.
        await tester.tap(_homeExitButtonFinder(), warnIfMissed: false);
        await tester.tap(_galleryExitButtonFinder(), warnIfMissed: false);
        await tester.pump();
        expect(repository.saveArtworkCallCount, 1);

        // Unblocks `saveArtwork`, letting the rest of the chain (thumbnail
        // capture's real `toImage()`/`toByteData()`, then navigation) run —
        // see the other test's comment for why that needs `runAsync`.
        saveGate.complete();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(repository.saveArtworkCallCount, 1);
      },
    );

    testWidgets(
      'leaving a brand-new blank canvas via Home exit does not create a '
      'gallery entry (empty-canvas auto-save suppression)',
      (tester) async {
        final repository = _TestArtworkRepository(MemoryFileSystem());
        await pumpEditorFromHome(tester, repository: repository);

        await tester.runAsync(() async {
          await tester.tap(_homeExitButtonFinder());
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(repository.saveArtworkCallCount, 0);
        expect((await repository.readIndex()).artworks, isEmpty);
      },
    );
  });

  group('EditorScreen quota safety net', () {
    testWidgets(
      'flush at the save limit stays on the editor and shows a SnackBar',
      (tester) async {
        final repository = _TestArtworkRepository(MemoryFileSystem());
        await repository.writeIndex(
          ArtworkIndex(
            artworks: [
              ArtworkSummary(
                id: 'existing',
                title: '既存作品',
                updatedAt: DateTime.utc(2026, 8, 1),
                thumbnailPath: repository.thumbnailPathFor('existing'),
                documentPath: repository.documentPathFor('existing'),
              ),
            ],
          ),
        );

        final container = ProviderContainer(
          overrides: [
            artworkRepositoryProvider.overrideWith((ref) async => repository),
            galleryQuotaProvider.overrideWith((ref) => const GalleryQuota(baseSlotLimit: 1)),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const PolygonArtApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Bypass the UI primary gate: open a *new* id while the gallery is full.
        // Do not await pushNamed — that Future only completes when the editor
        // is popped, which this test must itself perform after drawing.
        container.read(galleryControllerProvider).createNewArtwork();
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.pushNamed(PolygonArtApp.editorRoute);
        await tester.pumpAndSettle();

        await _drawOneTriangle(tester);

        await tester.tap(_homeExitButtonFinder());
        await tester.pumpAndSettle();

        expect(find.byType(EditorScreen), findsOneWidget);
        expect(find.byType(HomeScreen), findsNothing);
        expect(find.text(GalleryQuotaMessages.snackBar), findsAtLeastNWidgets(1));
        expect(repository.saveArtworkCallCount, 0);
      },
    );
  });
}
