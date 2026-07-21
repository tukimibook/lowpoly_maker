import 'dart:async';
import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';
import 'package:polygon_art_app/models/artwork_document.dart';
import 'package:polygon_art_app/models/artwork_index.dart';
import 'package:polygon_art_app/providers/artwork_repository_provider.dart';
import 'package:polygon_art_app/repositories/artwork_repository.dart';
import 'package:polygon_art_app/screens/editor_screen.dart';
import 'package:polygon_art_app/screens/gallery_screen.dart';
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
  /// forced save in flight (via a [Completer]) to observe the save-and-exit
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
  await tester.tap(_iconButtonByTooltip('多角形を閉じる'));
  await tester.pumpAndSettle();
}

Finder _saveAndExitButtonFinder() => find.byKey(const Key('save-and-exit-button'));

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
    // to be broken by a naive `Navigator.pop()`-based "戻る" button.
    await tester.tap(find.text('新規作成'));
    await tester.pumpAndSettle();
    return repository;
  }

  group('EditorScreen save-and-exit button', () {
    testWidgets(
      'forces an immediate save (no debounce wait) and returns to a fresh '
      'GalleryScreen, discarding the entire navigation stack',
      (tester) async {
        final repository = _TestArtworkRepository(MemoryFileSystem());
        await pumpEditorFromHome(tester, repository: repository);
        await _drawOneTriangle(tester);

        expect(find.byType(EditorScreen), findsOneWidget);
        // The forced save's thumbnail capture goes through a real
        // `RenderRepaintBoundary.toImage()`/`toByteData()` round trip, which
        // (like `compute()` elsewhere in this app — see `widget_test.dart`'s
        // tessellation tests) never progresses inside `testWidgets`' fake-async
        // zone without `runAsync`.
        await tester.runAsync(() async {
          await tester.tap(_saveAndExitButtonFinder());
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
        await tester.pumpAndSettle();

        expect(find.byType(GalleryScreen), findsOneWidget);
        expect(find.byType(EditorScreen), findsNothing);
        expect(repository.saveArtworkCallCount, 1);

        final index = await repository.readIndex();
        expect(index.artworks, hasLength(1));
        final saved = await repository.readArtwork(index.artworks.single.id);
        expect(saved!.artwork.polygons, hasLength(1));
      },
    );

    testWidgets(
      'disables itself and shows a spinner while the forced save is still in flight, '
      'and ignores further taps until it completes',
      (tester) async {
        final saveGate = Completer<void>();
        final repository = _TestArtworkRepository(MemoryFileSystem())
          ..onSave = () => saveGate.future;
        await pumpEditorFromHome(tester, repository: repository);

        await tester.tap(_saveAndExitButtonFinder());
        await tester.pump(); // Don't settle: the save never completes yet.

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final button = tester.widget<IconButton>(_saveAndExitButtonFinder());
        expect(button.onPressed, isNull);

        // A second tap while disabled is a no-op at the framework level
        // (a disabled `IconButton` doesn't fire `onPressed`) — this is the
        // actual multi-tap-prevention guarantee under test.
        await tester.tap(_saveAndExitButtonFinder(), warnIfMissed: false);
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

        expect(find.byType(GalleryScreen), findsOneWidget);
        expect(repository.saveArtworkCallCount, 1);
      },
    );
  });
}
