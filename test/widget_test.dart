import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';
import 'package:polygon_art_app/providers/canvas_background_provider.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/providers/drag_preview_provider.dart';
import 'package:polygon_art_app/widgets/canvas/polygon_painter.dart';

/// Finds the canvas's own [CustomPaint] specifically (there is exactly one
/// [PolygonPainter] in the tree), rather than `find.byType(CustomPaint)`,
/// which can also match unrelated `CustomPaint`s Material widgets render
/// internally for ink/splash effects once the tree grows past a bare
/// editor screen.
Finder _canvasCustomPaintFinder() {
  return find.byWidgetPredicate((widget) {
    return widget is CustomPaint && widget.painter is PolygonPainter;
  });
}

void main() {
  testWidgets('Home screen shows new artwork button', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PolygonArtApp()),
    );

    expect(find.text('Polygon Art'), findsOneWidget);
    expect(find.text('新規作成'), findsOneWidget);
  });

  testWidgets('Tapping new artwork navigates to editor', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PolygonArtApp()),
    );

    await tester.tap(find.text('新規作成'));
    await tester.pumpAndSettle();

    expect(find.text('無題の作品'), findsOneWidget);
    expect(find.text('閉じる'), findsOneWidget);
  });

  testWidgets('Tapping the canvas three times enables closing a polygon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: PolygonArtApp()),
    );
    await tester.tap(find.text('新規作成'));
    await tester.pumpAndSettle();

    final closeButtonFinder = find.widgetWithText(FilledButton, '閉じる');
    expect(tester.widget<FilledButton>(closeButtonFinder).onPressed, isNull);

    final canvasCenter = tester.getCenter(find.byType(CustomPaint).first);
    await tester.tapAt(canvasCenter + const Offset(-40, -40));
    await tester.pump();
    await tester.tapAt(canvasCenter + const Offset(40, -40));
    await tester.pump();
    await tester.tapAt(canvasCenter + const Offset(0, 40));
    await tester.pump();

    expect(tester.widget<FilledButton>(closeButtonFinder).onPressed, isNotNull);
  });

  testWidgets(
    "the editor's canvas background toggle flips its own brightness "
    "independently of the app's theme, and defaults to light",
    (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PolygonArtApp(),
        ),
      );
      await tester.tap(find.text('新規作成'));
      await tester.pumpAndSettle();

      expect(container.read(canvasBackgroundProvider), Brightness.light);
      expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.dark_mode_outlined));
      await tester.pump();

      expect(container.read(canvasBackgroundProvider), Brightness.dark);
      expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'dragging in draw mode commits the point where the finger lifts, not '
    'where it first touched down (Phase C: commit-on-release)',
    (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PolygonArtApp(),
        ),
      );
      await tester.tap(find.text('新規作成'));
      await tester.pumpAndSettle();

      final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
      const downOffset = Offset(50, 50);
      const upOffset = Offset(250, 50);

      final gesture = await tester.startGesture(canvasTopLeft + downOffset);
      await tester.pump();
      await gesture.moveTo(canvasTopLeft + upOffset);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final artwork = container.read(canvasProvider);
      expect(artwork.draftVertexIds, hasLength(1));
      expect(
        artwork.vertices[artwork.draftVertexIds.single]!.position,
        upOffset,
      );
    },
  );

  testWidgets(
    'dragging near an existing vertex shows a live magnet-snap preview onto '
    'it (Phase C: rubber-band preview)',
    (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PolygonArtApp(),
        ),
      );
      await tester.tap(find.text('新規作成'));
      await tester.pumpAndSettle();

      final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
      await tester.tapAt(canvasTopLeft + const Offset(50, 50));
      await tester.pump();
      await tester.tapAt(canvasTopLeft + const Offset(150, 50));
      await tester.pump();
      await tester.tapAt(canvasTopLeft + const Offset(100, 150));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '閉じる'));
      await tester.pump();

      final polygon = container.read(canvasProvider).polygons.single;
      final vertexId = polygon.vertexIds.first;
      final vertexPosition =
          container.read(canvasProvider).vertices[vertexId]!.position;

      // Start well away from the shape (but still within the canvas's own
      // bounds — it sits above the bottom toolbar, so it's shorter than the
      // full test surface), then drag in to just beside (not exactly onto)
      // that vertex — close enough to be within the snap radius.
      final canvasSize = tester.getSize(_canvasCustomPaintFinder());
      final farPoint = Offset(canvasSize.width - 40, canvasSize.height - 40);
      final gesture = await tester.startGesture(canvasTopLeft + farPoint);
      await tester.pump();
      expect(container.read(dragPreviewProvider).value, isNotNull);
      expect(container.read(dragPreviewProvider).value?.snappedVertexId, isNull);

      await gesture.moveTo(canvasTopLeft + vertexPosition + const Offset(5, 5));
      await tester.pump();

      final preview = container.read(dragPreviewProvider).value;
      expect(preview, isNotNull);
      expect(preview!.snappedVertexId, vertexId);

      await gesture.up();
      await tester.pump();

      // The preview is cleared once the drag ends either way.
      expect(container.read(dragPreviewProvider).value, isNull);
    },
  );
}
