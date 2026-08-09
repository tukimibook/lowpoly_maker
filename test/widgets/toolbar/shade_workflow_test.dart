import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';
import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/polygon_shape.dart';
import 'package:polygon_art_app/models/shade_tool.dart';
import 'package:polygon_art_app/models/vertex.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/providers/selection_drag_provider.dart';
import 'package:polygon_art_app/providers/shade_session_provider.dart';
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

double _lightness(Color color) => HSLColor.fromColor(color).lightness;

/// Two triangles sharing [v1] so Light BFS reaches both from [p0].
Artwork _weldedPairArtwork({required Color initialFill}) {
  return Artwork(
    id: 'shade-workflow',
    title: kDefaultArtworkTitle,
    vertices: {
      'v0': const Vertex(id: 'v0', position: Offset(40, 40)),
      'v1': const Vertex(id: 'v1', position: Offset(200, 40)),
      'v2': const Vertex(id: 'v2', position: Offset(120, 160)),
      'v3': const Vertex(id: 'v3', position: Offset(360, 40)),
      'v4': const Vertex(id: 'v4', position: Offset(280, 160)),
    },
    polygons: [
      PolygonShape(
        id: 'p0',
        vertexIds: const ['v0', 'v1', 'v2'],
        fillColor: initialFill,
        strokeColor: const Color(0xFF000000),
        strokeWidth: 1,
      ),
      PolygonShape(
        id: 'p1',
        vertexIds: const ['v1', 'v3', 'v4'],
        fillColor: initialFill,
        strokeColor: const Color(0xFF000000),
        strokeWidth: 1,
      ),
    ],
  );
}

void main() {
  group('Shade workflow (Step 3.7)', () {
    Future<ProviderContainer> pumpEditor(WidgetTester tester) async {
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

    testWidgets(
      'select → light → clear → solid hand-tune → undo last solid only',
      (tester) async {
        final container = await pumpEditor(tester);
        const initialFill = Color(0xFF9E9E9E);
        container.read(canvasProvider.notifier).loadArtwork(
              _weldedPairArtwork(initialFill: initialFill),
            );
        await tester.pump();

        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
        // Interiors well inside each ring (away from shared vertex).
        final p0Interior = canvasTopLeft + const Offset(120, 90);
        final p1Interior = canvasTopLeft + const Offset(280, 90);

        await tester.tap(find.byTooltip('Shade'));
        await tester.pump();

        // --- 1. Select brush: drag across both (Add polarity) ---
        container.read(shadeToolProvider.notifier).state = ShadeTool.select;
        await tester.pump();

        final selectGesture = await tester.startGesture(p0Interior);
        await tester.pump();
        await selectGesture.moveTo(p1Interior);
        await tester.pump();
        await selectGesture.up();
        await tester.pump();

        expect(
          container.read(selectionDragProvider).value,
          unorderedEquals({'p0', 'p1'}),
        );

        // --- 2. Light origin on p0 → distance batch ---
        final lightBase = kDefaultPolygonPalette.first;
        container.read(selectedFillColorProvider.notifier).state = lightBase;
        container.read(shadeToolProvider.notifier).state = ShadeTool.light;
        await tester.pump();

        await tester.tapAt(p0Interior);
        await tester.pump();

        final afterLight = container.read(canvasProvider).polygons;
        final p0AfterLight =
            afterLight.firstWhere((p) => p.id == 'p0').fillColor;
        final p1AfterLight =
            afterLight.firstWhere((p) => p.id == 'p1').fillColor;
        expect(p0AfterLight, isNot(equals(initialFill)));
        expect(p1AfterLight, isNot(equals(initialFill)));
        expect(_lightness(p1AfterLight), lessThan(_lightness(p0AfterLight)));
        // Light commit clears the selection set.
        expect(container.read(selectionDragProvider).value, isEmpty);

        // --- 3. Clear selection (explicit UI; already empty after light) ---
        await tester.tap(_iconButtonByTooltip('Clear selection'));
        await tester.pump();
        expect(container.read(selectionDragProvider).value, isEmpty);

        // --- 4. Re-select only p1 for hand-tune ---
        container.read(shadeToolProvider.notifier).state = ShadeTool.select;
        await tester.pump();
        await tester.tapAt(p1Interior);
        await tester.pump();
        expect(container.read(selectionDragProvider).value, {'p1'});

        // --- 5. Accordion color + solid batch on selection ---
        final accordionBase = kDefaultPolygonPalette[2];
        await tester.tap(find.byKey(ValueKey(('base', accordionBase))));
        await tester.pumpAndSettle();
        expect(container.read(activeBaseColorProvider), accordionBase);

        await tester.tap(find.byKey(ValueKey(('ramp', accordionBase, 0))));
        await tester.pump();
        final solidColor = container.read(selectedFillColorProvider);
        expect(solidColor, isNot(equals(accordionBase)));

        container.read(shadeToolProvider.notifier).state = ShadeTool.solid;
        await tester.pump();
        // solid commits on gesture end using the selection set (position unused).
        await tester.tapAt(p1Interior);
        await tester.pump();

        final afterSolid = container.read(canvasProvider).polygons;
        expect(
          afterSolid.firstWhere((p) => p.id == 'p1').fillColor,
          solidColor,
        );
        // Untouched by solid — still the Light result.
        expect(
          afterSolid.firstWhere((p) => p.id == 'p0').fillColor,
          p0AfterLight,
        );
        expect(container.read(selectionDragProvider).value, isEmpty);
        expect(container.read(canvasProvider.notifier).canUndo, isTrue);

        // --- 6. Undo reverts only the solid apply ---
        await tester.tap(_iconButtonByTooltip('Undo'));
        await tester.pump();

        final afterUndo = container.read(canvasProvider).polygons;
        expect(
          afterUndo.firstWhere((p) => p.id == 'p1').fillColor,
          p1AfterLight,
        );
        expect(
          afterUndo.firstWhere((p) => p.id == 'p0').fillColor,
          p0AfterLight,
        );
      },
    );
  });
}
