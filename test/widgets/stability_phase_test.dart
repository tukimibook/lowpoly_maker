import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';
import 'package:polygon_art_app/models/canvas_mode.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/providers/detach_cycle_provider.dart';
import 'package:polygon_art_app/providers/drag_preview_provider.dart';
import 'package:polygon_art_app/providers/polygon_drag_preview_provider.dart';
import 'package:polygon_art_app/providers/polygon_edit_target_provider.dart';
import 'package:polygon_art_app/providers/selected_vertex_provider.dart';
import 'package:polygon_art_app/providers/vertex_drag_preview_provider.dart';
import 'package:polygon_art_app/providers/viewport_provider.dart';
import 'package:polygon_art_app/widgets/canvas/polygon_painter.dart';

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

Future<ProviderContainer> _pumpEditor(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const PolygonArtApp(),
    ),
  );
  await tester.tap(find.text('New Artwork'));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _closeTriangleAt(
  WidgetTester tester,
  Offset canvasTopLeft,
  List<Offset> points,
) async {
  for (final point in points) {
    await tester.tapAt(canvasTopLeft + point);
    await tester.pump();
  }
  await tester.tap(_iconButtonByTooltip('Close shape'));
  await tester.pump();
}

void main() {
  group('clearEditSelectionUi / clearGesturePreviews', () {
    test('clearGesturePreviews nulls every transient preview controller', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(dragPreviewProvider).value = const DragPreview(
        position: Offset(1, 1),
      );
      container.read(vertexDragPreviewProvider).value = const VertexDragPreview(
        vertexId: 'v',
        position: Offset(2, 2),
      );
      container.read(polygonDragPreviewProvider).value = PolygonDragPreview(
        affectedVertexIds: const {'v'},
        delta: const Offset(3, 3),
      );

      clearGesturePreviews(container.read);

      expect(container.read(dragPreviewProvider).value, isNull);
      expect(container.read(vertexDragPreviewProvider).value, isNull);
      expect(container.read(polygonDragPreviewProvider).value, isNull);
    });

    test(
      'clearEditSelectionUi resets selection/arming; whole-shape cycles '
      'only when requested',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(selectedVertexProvider.notifier).state = 'v';
        container.read(weldArmedProvider.notifier).state = true;
        container.read(detachCycleIndexProvider.notifier).state = 2;
        container.read(polygonCycleIndexProvider.notifier).state = 1;
        container.read(edgeCycleIndexProvider.notifier).state = 0;

        clearEditSelectionUi(container.read, resetWholeShapeCycles: false);
        expect(container.read(selectedVertexProvider), isNull);
        expect(container.read(weldArmedProvider), isFalse);
        expect(container.read(detachCycleIndexProvider), 0);
        expect(container.read(polygonCycleIndexProvider), 1);
        expect(container.read(edgeCycleIndexProvider), 0);

        container.read(selectedVertexProvider.notifier).state = 'v2';
        container.read(polygonCycleIndexProvider.notifier).state = 3;
        clearEditSelectionUi(container.read);
        expect(container.read(selectedVertexProvider), isNull);
        expect(container.read(polygonCycleIndexProvider), -1);
        expect(container.read(edgeCycleIndexProvider), -1);
      },
    );

    testWidgets(
      'mode switch clears a dangling polygon-drag preview',
      (tester) async {
        final container = await _pumpEditor(tester);

        container.read(polygonDragPreviewProvider).value = PolygonDragPreview(
          affectedVertexIds: const {'a'},
          delta: const Offset(5, 5),
        );
        expect(container.read(polygonDragPreviewProvider).value, isNotNull);

        await tester.tap(find.byTooltip('Edit'));
        await tester.pump();

        expect(container.read(polygonDragPreviewProvider).value, isNull);
      },
    );
  });

  group('edit-mode gesture mutual exclusion', () {
    testWidgets(
      'long-press-dragging a vertex while a whole-shape target is active '
      'moves only that vertex (no whole-polygon translate)',
      (tester) async {
        final container = await _pumpEditor(tester);
        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());

        await _closeTriangleAt(tester, canvasTopLeft, const [
          Offset(50, 50),
          Offset(150, 50),
          Offset(100, 150),
        ]);

        await tester.tap(find.byTooltip('Edit'));
        await tester.pump();
        await tester.tap(_iconButtonByTooltip('Cycle Shape'));
        await tester.pump();
        expect(container.read(polygonCycleIndexProvider), 0);

        final polygon = container.read(canvasProvider).polygons.single;
        final draggedId = polygon.vertexIds[0];
        final otherId = polygon.vertexIds[1];
        final draggedBefore =
            container.read(canvasProvider).vertices[draggedId]!.position;
        final otherBefore =
            container.read(canvasProvider).vertices[otherId]!.position;

        final gesture = await tester.startGesture(canvasTopLeft + draggedBefore);
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        final draggedAfter =
            container.read(canvasProvider).vertices[draggedId]!.position;
        final otherAfter =
            container.read(canvasProvider).vertices[otherId]!.position;

        expect(draggedAfter.dx, closeTo(draggedBefore.dx + 30, 2));
        expect(otherAfter, otherBefore);
      },
    );
  });

  group('eraser deletes on tap only', () {
    testWidgets(
      'pinching with a finger over a vertex does not erase it',
      (tester) async {
        final container = await _pumpEditor(tester);
        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());

        await _closeTriangleAt(tester, canvasTopLeft, const [
          Offset(50, 50),
          Offset(150, 50),
          Offset(100, 150),
        ]);

        final vertexId = container.read(canvasProvider).polygons.single.vertexIds.first;
        final vertexPos =
            container.read(canvasProvider).vertices[vertexId]!.position;

        // Eraser is no longer in the mode toggle; enter it programmatically.
        container.read(canvasModeProvider.notifier).state = CanvasMode.eraser;
        await tester.pump();

        final finger1 = await tester.startGesture(canvasTopLeft + vertexPos);
        await tester.pump();
        final finger2 = await tester.startGesture(
          canvasTopLeft + vertexPos + const Offset(80, 0),
        );
        await tester.pump();

        const steps = 40;
        for (var i = 0; i < steps; i++) {
          await finger1.moveBy(const Offset(-1, 0));
          await finger2.moveBy(const Offset(1, 0));
        }
        await tester.pump();
        await finger1.up();
        await finger2.up();
        await tester.pump();

        expect(container.read(canvasProvider).vertices.containsKey(vertexId), isTrue);
        expect(container.read(viewportProvider).value.scale, greaterThan(1.0));
      },
    );

    testWidgets('a short tap on a vertex still erases it', (tester) async {
      final container = await _pumpEditor(tester);
      final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());

      await _closeTriangleAt(tester, canvasTopLeft, const [
        Offset(50, 50),
        Offset(150, 50),
        Offset(100, 150),
      ]);

      final vertexId = container.read(canvasProvider).polygons.single.vertexIds.first;
      final vertexPos =
          container.read(canvasProvider).vertices[vertexId]!.position;

      container.read(canvasModeProvider.notifier).state = CanvasMode.eraser;
      await tester.pump();
      await tester.tapAt(canvasTopLeft + vertexPos);
      await tester.pump();

      expect(container.read(canvasProvider).vertices.containsKey(vertexId), isFalse);
    });
  });
}
