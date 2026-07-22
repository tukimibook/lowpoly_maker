import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/providers/selected_vertex_provider.dart';
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

Finder _weldButton() => find.byKey(const Key('weld-vertices-button'));

Future<ProviderContainer> _pumpEditor(WidgetTester tester) async {
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
  await tester.tap(_iconButtonByTooltip('多角形を閉じる'));
  await tester.pump();
}

void main() {
  group('Edit-mode weld arming UI', () {
    testWidgets(
      'without arming, tapping another vertex only changes selection '
      '(no implicit weld)',
      (tester) async {
        final container = await _pumpEditor(tester);
        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());

        await _closeTriangleAt(tester, canvasTopLeft, const [
          Offset(50, 50),
          Offset(150, 50),
          Offset(100, 150),
        ]);
        await _closeTriangleAt(tester, canvasTopLeft, const [
          Offset(200, 50),
          Offset(300, 50),
          Offset(250, 150),
        ]);

        await tester.tap(find.byTooltip('編集モード'));
        await tester.pump();

        final artwork = container.read(canvasProvider);
        final keepId = artwork.polygons[0].vertexIds[1]; // (150, 50)
        final mergeId = artwork.polygons[1].vertexIds[0]; // (200, 50)
        final keepPos = artwork.vertices[keepId]!.position;
        final mergePos = artwork.vertices[mergeId]!.position;

        await tester.tapAt(canvasTopLeft + keepPos);
        await tester.pump();
        expect(container.read(selectedVertexProvider), keepId);
        expect(container.read(weldArmedProvider), isFalse);

        await tester.tapAt(canvasTopLeft + mergePos);
        await tester.pump();

        expect(container.read(selectedVertexProvider), mergeId);
        expect(container.read(canvasProvider).vertices.containsKey(mergeId), isTrue);
        expect(container.read(weldArmedProvider), isFalse);
      },
    );

    testWidgets(
      'weld button arms, shows English SnackBar, and a follow-up tap welds',
      (tester) async {
        final container = await _pumpEditor(tester);
        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());

        await _closeTriangleAt(tester, canvasTopLeft, const [
          Offset(50, 50),
          Offset(150, 50),
          Offset(100, 150),
        ]);
        await _closeTriangleAt(tester, canvasTopLeft, const [
          Offset(200, 50),
          Offset(300, 50),
          Offset(250, 150),
        ]);

        await tester.tap(find.byTooltip('編集モード'));
        await tester.pump();

        final artwork = container.read(canvasProvider);
        final keepId = artwork.polygons[0].vertexIds[1];
        final mergeId = artwork.polygons[1].vertexIds[0];
        final keepPos = artwork.vertices[keepId]!.position;
        final mergePos = artwork.vertices[mergeId]!.position;

        await tester.tapAt(canvasTopLeft + keepPos);
        await tester.pump();

        expect(_weldButton(), findsOneWidget);
        final beforeArm = tester.widget<IconButton>(_weldButton());
        expect(beforeArm.tooltip, 'Weld vertices');
        expect(beforeArm.style, isNull);

        await tester.tap(_weldButton());
        await tester.pump();

        expect(container.read(weldArmedProvider), isTrue);
        expect(find.text('Tap a vertex to weld'), findsOneWidget);
        expect(tester.widget<IconButton>(_weldButton()).style, isNotNull);

        await tester.tapAt(canvasTopLeft + mergePos);
        await tester.pump();

        expect(container.read(weldArmedProvider), isFalse);
        expect(container.read(canvasProvider).vertices.containsKey(mergeId), isFalse);
        expect(container.read(selectedVertexProvider), keepId);
      },
    );

    testWidgets('deselect clears weld arming', (tester) async {
      final container = await _pumpEditor(tester);
      final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());

      await _closeTriangleAt(tester, canvasTopLeft, const [
        Offset(50, 50),
        Offset(150, 50),
        Offset(100, 150),
      ]);

      await tester.tap(find.byTooltip('編集モード'));
      await tester.pump();

      final vertexId = container.read(canvasProvider).polygons.single.vertexIds.first;
      final pos = container.read(canvasProvider).vertices[vertexId]!.position;
      await tester.tapAt(canvasTopLeft + pos);
      await tester.pump();

      await tester.tap(_weldButton());
      await tester.pump();
      expect(container.read(weldArmedProvider), isTrue);

      await tester.tap(_iconButtonByTooltip('選択を解除'));
      await tester.pump();

      expect(container.read(selectedVertexProvider), isNull);
      expect(container.read(weldArmedProvider), isFalse);
      expect(_weldButton(), findsNothing);
    });

    testWidgets('mode switch clears weld arming', (tester) async {
      final container = await _pumpEditor(tester);
      final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());

      await _closeTriangleAt(tester, canvasTopLeft, const [
        Offset(50, 50),
        Offset(150, 50),
        Offset(100, 150),
      ]);

      await tester.tap(find.byTooltip('編集モード'));
      await tester.pump();

      final vertexId = container.read(canvasProvider).polygons.single.vertexIds.first;
      final pos = container.read(canvasProvider).vertices[vertexId]!.position;
      await tester.tapAt(canvasTopLeft + pos);
      await tester.pump();

      await tester.tap(_weldButton());
      await tester.pump();
      expect(container.read(weldArmedProvider), isTrue);

      await tester.tap(find.byTooltip('描画モード'));
      await tester.pump();

      expect(container.read(weldArmedProvider), isFalse);
      expect(container.read(selectedVertexProvider), isNull);
    });

    testWidgets('weld button is absent when no vertex is selected', (tester) async {
      await _pumpEditor(tester);

      await tester.tap(find.byTooltip('編集モード'));
      await tester.pump();

      expect(_weldButton(), findsNothing);
    });

    testWidgets(
      'a failed weld attempt (e.g. same-polygon dissolve) still disarms',
      (tester) async {
        final container = await _pumpEditor(tester);
        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());

        await _closeTriangleAt(tester, canvasTopLeft, const [
          Offset(50, 50),
          Offset(150, 50),
          Offset(100, 150),
        ]);

        await tester.tap(find.byTooltip('編集モード'));
        await tester.pump();

        final polygon = container.read(canvasProvider).polygons.single;
        final keepId = polygon.vertexIds[0];
        final mergeId = polygon.vertexIds[1];
        final keepPos = container.read(canvasProvider).vertices[keepId]!.position;
        final mergePos = container.read(canvasProvider).vertices[mergeId]!.position;

        await tester.tapAt(canvasTopLeft + keepPos);
        await tester.pump();
        await tester.tap(_weldButton());
        await tester.pump();
        expect(container.read(weldArmedProvider), isTrue);

        await tester.tapAt(canvasTopLeft + mergePos);
        await tester.pump();

        expect(container.read(weldArmedProvider), isFalse);
        expect(container.read(canvasProvider).vertices.containsKey(mergeId), isTrue);
      },
    );
  });
}
