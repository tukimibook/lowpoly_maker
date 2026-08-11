import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/providers/polygon_edit_target_provider.dart';
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

Finder _paletteSwatchByColor(Color color) {
  return find.byKey(ValueKey(('base', color)));
}

void main() {
  group('FillColorPalette mode branching', () {
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
      'draw mode: tapping a swatch updates selectedFillColorProvider only',
      (tester) async {
        final container = await pumpEditor(tester);

        expect(find.byKey(const Key('fill-color-palette')), findsOneWidget);
        expect(
          container.read(selectedFillColorProvider),
          kDefaultPolygonPalette.first,
        );

        final nextColor = kDefaultPolygonPalette[1];
        await tester.tap(_paletteSwatchByColor(nextColor));
        await tester.pump();

        expect(container.read(selectedFillColorProvider), nextColor);
        expect(container.read(canvasProvider).polygons, isEmpty);
        expect(container.read(canvasProvider.notifier).canUndo, isFalse);
      },
    );

    testWidgets(
      'edit mode with a targeted polygon: palette stays hidden '
      '(no accidental recolor)',
      (tester) async {
        final container = await pumpEditor(tester);
        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());

        await tester.tapAt(canvasTopLeft + const Offset(40, 40));
        await tester.pump();
        await tester.tapAt(canvasTopLeft + const Offset(160, 40));
        await tester.pump();
        await tester.tapAt(canvasTopLeft + const Offset(100, 160));
        await tester.pump();
        await tester.tap(_iconButtonByTooltip('Close shape'));
        await tester.pump();

        await tester.tap(find.byTooltip('Edit'));
        await tester.pump();

        // Unselected: palette hidden.
        expect(find.byKey(const Key('fill-color-palette')), findsNothing);

        await tester.tap(_iconButtonByTooltip('Cycle Shape'));
        await tester.pump();
        expect(container.read(editSelectionProvider).polygonIndex, 0);
        // Targeted polygon still must not expose a recolor palette.
        expect(find.byKey(const Key('fill-color-palette')), findsNothing);
      },
    );
  });
}
