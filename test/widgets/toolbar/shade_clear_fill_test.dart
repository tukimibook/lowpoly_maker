import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';
import 'package:polygon_art_app/models/shade_tool.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/providers/selection_drag_provider.dart';
import 'package:polygon_art_app/providers/shade_session_provider.dart';
import 'package:polygon_art_app/widgets/canvas/polygon_painter.dart';

Finder _canvasCustomPaintFinder() {
  return find.byWidgetPredicate((widget) {
    return widget is CustomPaint && widget.painter is PolygonPainter;
  });
}

void main() {
  group('Shade clear fill / light guard', () {
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
      'Light tool is a no-op when the pen is kClearFillColor',
      (tester) async {
        final container = await pumpEditor(tester);
        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());

        // Close a triangle in the default opaque pen color.
        await tester.tapAt(canvasTopLeft + const Offset(50, 50));
        await tester.pump();
        await tester.tapAt(canvasTopLeft + const Offset(150, 50));
        await tester.pump();
        await tester.tapAt(canvasTopLeft + const Offset(100, 150));
        await tester.pump();
        await tester.tap(find.byTooltip('Close shape'));
        await tester.pump();

        final before = container.read(canvasProvider).polygons.single.fillColor;
        expect(before.a, 1.0);

        await tester.tap(find.byTooltip('Shade'));
        await tester.pump();

        // Select the triangle, then arm clear as the base color.
        container.read(shadeToolProvider.notifier).state = ShadeTool.select;
        await tester.pump();
        await tester.tapAt(canvasTopLeft + const Offset(100, 80));
        await tester.pump();
        expect(container.read(selectionDragProvider).value, isNotEmpty);

        container.read(selectedFillColorProvider.notifier).state =
            kClearFillColor;
        container.read(shadeToolProvider.notifier).state = ShadeTool.light;
        await tester.pump();

        // Light-origin tap on the selected polygon must not recolor.
        await tester.tapAt(canvasTopLeft + const Offset(100, 80));
        await tester.pump();

        expect(
          container.read(canvasProvider).polygons.single.fillColor,
          before,
        );
        // Selection must remain (no successful commit cleared it).
        expect(container.read(selectionDragProvider).value, isNotEmpty);
      },
    );

    testWidgets(
      'Shade palette leads with the clear swatch; tapping it arms no-fill',
      (tester) async {
        final container = await pumpEditor(tester);

        await tester.tap(find.byTooltip('Shade'));
        await tester.pump();

        expect(find.byKey(const Key('fill-color-palette')), findsOneWidget);
        expect(find.byTooltip('No fill'), findsOneWidget);
        expect(container.read(activeBaseColorProvider), isNull);

        await tester.tap(find.byTooltip('No fill'));
        await tester.pump();

        expect(container.read(selectedFillColorProvider), kClearFillColor);
        // Clear is not a base — accordion stays collapsed.
        expect(container.read(activeBaseColorProvider), isNull);
      },
    );

    testWidgets(
      'tapping a preset expands accordion; ramp tap keeps the base anchor',
      (tester) async {
        final container = await pumpEditor(tester);

        await tester.tap(find.byTooltip('Shade'));
        await tester.pump();

        final base = kDefaultPolygonPalette[2];
        await tester.tap(find.byKey(ValueKey(('base', base))));
        await tester.pumpAndSettle();

        expect(container.read(activeBaseColorProvider), base);
        expect(container.read(selectedFillColorProvider), base);
        expect(find.byKey(ValueKey(('ramp', base, 'L'))), findsOneWidget);
        expect(find.byKey(ValueKey(('ramp', base, 0))), findsOneWidget);

        await tester.tap(find.byKey(ValueKey(('ramp', base, 'L'))));
        await tester.pump();

        expect(container.read(activeBaseColorProvider), base);
        expect(
          container.read(selectedFillColorProvider),
          isNot(equals(base)),
        );
        // Family stays expanded.
        expect(find.byKey(ValueKey(('ramp', base, 'L'))), findsOneWidget);
      },
    );
  });
}
