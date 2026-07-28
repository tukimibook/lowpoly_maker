import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';
import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/providers/artwork_repository_provider.dart';
import 'package:polygon_art_app/providers/auto_save_provider.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/repositories/artwork_repository.dart';
import 'package:polygon_art_app/screens/editor_screen.dart';

class _TestArtworkRepository extends ArtworkRepository {
  _TestArtworkRepository(MemoryFileSystem fs)
    : super(fileSystem: fs, documentsPath: '/documents');
}

void main() {
  group('EditorScreen artwork rename', () {
    Future<ProviderContainer> pumpEditor(WidgetTester tester) async {
      final repository = _TestArtworkRepository(MemoryFileSystem());
      final container = ProviderContainer(
        overrides: [artworkRepositoryProvider.overrideWith((ref) async => repository)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PolygonArtApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Artwork'));
      await tester.pumpAndSettle();
      expect(find.byType(EditorScreen), findsOneWidget);
      return container;
    }

    testWidgets('tapping the AppBar title opens a rename dialog', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.byKey(const Key('artwork-title')));
      await tester.pumpAndSettle();

      expect(find.text('Rename artwork'), findsOneWidget);
      expect(find.byKey(const Key('artwork-rename-field')), findsOneWidget);
    });

    testWidgets('confirming the dialog updates the AppBar title via setTitle', (tester) async {
      final container = await pumpEditor(tester);
      expect(container.read(canvasProvider).title, kDefaultArtworkTitle);

      await tester.tap(find.byKey(const Key('artwork-title')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('artwork-rename-field')), '私の作品');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // Title change schedules a debounced auto-save — cancel so the test
      // binding does not see a pending Timer after the tree is disposed.
      container.read(autoSaveServiceProvider)?.cancel();

      expect(container.read(canvasProvider).title, '私の作品');
      expect(find.text('私の作品'), findsWidgets);
      expect(find.byKey(const Key('artwork-rename-field')), findsNothing);
    });

    testWidgets('cancel leaves the title unchanged', (tester) async {
      final container = await pumpEditor(tester);

      await tester.tap(find.byKey(const Key('artwork-title')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('artwork-rename-field')), '捨てる名前');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(container.read(canvasProvider).title, kDefaultArtworkTitle);
    });
  });
}
