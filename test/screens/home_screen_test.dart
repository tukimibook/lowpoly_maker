import 'dart:ui';

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';
import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/canvas_mode.dart';
import 'package:polygon_art_app/models/draw_mode.dart';
import 'package:polygon_art_app/models/polygon_shape.dart';
import 'package:polygon_art_app/models/vertex.dart';
import 'package:polygon_art_app/providers/artwork_repository_provider.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/providers/selected_vertex_provider.dart';
import 'package:polygon_art_app/repositories/artwork_repository.dart';
import 'package:polygon_art_app/screens/editor_screen.dart';

/// Inline JSON (no `compute()`) — same rationale as
/// `test/screens/gallery_screen_test.dart`'s `_TestArtworkRepository`.
class _TestArtworkRepository extends ArtworkRepository {
  _TestArtworkRepository(MemoryFileSystem fs)
    : super(fileSystem: fs, documentsPath: '/documents');
}

Artwork _dirtyArtwork() {
  return Artwork(
    id: 'leftover-session',
    title: '前回の作品',
    vertices: {
      'v1': const Vertex(id: 'v1', position: Offset(0, 0)),
      'v2': const Vertex(id: 'v2', position: Offset(100, 0)),
      'v3': const Vertex(id: 'v3', position: Offset(50, 100)),
    },
    polygons: [
      PolygonShape(
        id: 'p1',
        vertexIds: const ['v1', 'v2', 'v3'],
        fillColor: const Color(0xFFEF5350),
        strokeColor: const Color(0xFF212121),
        strokeWidth: 2.5,
      ),
    ],
  );
}

void main() {
  group('HomeScreen 新規作成 (defect-fix #5)', () {
    testWidgets(
      'resets leftover canvas geometry and tool mode before opening the editor',
      (tester) async {
        final repository = _TestArtworkRepository(MemoryFileSystem());
        final container = ProviderContainer(
          overrides: [artworkRepositoryProvider.overrideWith((ref) async => repository)],
        );
        addTearDown(container.dispose);

        // Simulate a previous editing session that left geometry + eraser mode.
        container.read(canvasProvider.notifier).loadArtwork(_dirtyArtwork());
        container.read(canvasModeProvider.notifier).state = CanvasMode.eraser;
        container.read(drawModeProvider.notifier).state = DrawMode.trace;
        container.read(selectedVertexProvider.notifier).state = 'v1';
        final leftoverId = container.read(canvasProvider).id;

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
        expect(container.read(canvasProvider).id, isNot(leftoverId));
        expect(container.read(canvasProvider).polygons, isEmpty);
        expect(container.read(canvasProvider).vertices, isEmpty);
        expect(container.read(canvasModeProvider), CanvasMode.draw);
        expect(container.read(drawModeProvider), DrawMode.tap);
        expect(container.read(selectedVertexProvider), isNull);
      },
    );
  });
}
