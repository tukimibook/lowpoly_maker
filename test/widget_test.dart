import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';
import 'package:polygon_art_app/providers/canvas_background_provider.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/providers/drag_preview_provider.dart';
import 'package:polygon_art_app/providers/selected_vertex_provider.dart';
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

/// Finds an [IconButton] by its accessible name — the icon-only 2026-07-16
/// toolbar redesign (`.cursor/plans/plan_phase_H_alpha.md`) carries no
/// visible text, so tests must match on `tooltip` instead of `find.text`.
Finder _iconButtonByTooltip(String tooltip) {
  return find.byWidgetPredicate((widget) {
    return widget is IconButton && widget.tooltip == tooltip;
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
    // The "閉じる" button lost its visible text label in the 2026-07-16
    // icon-only toolbar redesign (see `.cursor/plans/plan_phase_H_alpha.md`)
    // — its accessible name now lives solely in its Tooltip.
    expect(_iconButtonByTooltip('多角形を閉じる'), findsOneWidget);
  });

  testWidgets('Tapping the canvas three times enables closing a polygon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: PolygonArtApp()),
    );
    await tester.tap(find.text('新規作成'));
    await tester.pumpAndSettle();

    final closeButtonFinder = _iconButtonByTooltip('多角形を閉じる');
    expect(tester.widget<IconButton>(closeButtonFinder).onPressed, isNull);

    final canvasCenter = tester.getCenter(_canvasCustomPaintFinder());
    await tester.tapAt(canvasCenter + const Offset(-40, -40));
    await tester.pump();
    await tester.tapAt(canvasCenter + const Offset(40, -40));
    await tester.pump();
    await tester.tapAt(canvasCenter + const Offset(0, 40));
    await tester.pump();

    expect(tester.widget<IconButton>(closeButtonFinder).onPressed, isNotNull);
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
      await tester.tap(_iconButtonByTooltip('多角形を閉じる'));
      await tester.pump();

      final polygon = container.read(canvasProvider).polygons.single;
      final vertexId = polygon.vertexIds.first;
      final vertexPosition =
          container.read(canvasProvider).vertices[vertexId]!.position;

      // Start well away from the shape, near the canvas's top-right corner
      // — since the 2026-07-16 redesign (`.cursor/plans/
      // plan_phase_H_alpha.md`), the canvas itself spans the *entire* body
      // (the bottom toolbar floats on top as a `Stack` overlay instead of
      // shrinking it), so a point near the very bottom would now land
      // under that floating toolbar instead of on an empty patch of
      // canvas. Then drag in to just beside (not exactly onto) that
      // vertex — close enough to be within the snap radius.
      final canvasSize = tester.getSize(_canvasCustomPaintFinder());
      final farPoint = Offset(canvasSize.width - 40, 40);
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

  group('Edit mode whole-shape target UI (no vertex selected, 2026-07-16)', () {
    Future<ProviderContainer> pumpEditorWithTriangle(WidgetTester tester) async {
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
      await tester.tap(_iconButtonByTooltip('多角形を閉じる'));
      await tester.pump();

      await tester.tap(find.byTooltip('編集モード'));
      await tester.pump();

      return container;
    }

    PolygonPainter currentPainter(WidgetTester tester) {
      return tester.widget<CustomPaint>(_canvasCustomPaintFinder()).painter as PolygonPainter;
    }

    testWidgets(
      'shows the four whole-shape buttons, with nothing highlighted until '
      '図形を切り替え is pressed',
      (tester) async {
        await pumpEditorWithTriangle(tester);

        expect(_iconButtonByTooltip('図形を切り替え'), findsOneWidget);
        expect(_iconButtonByTooltip('辺を切り替え'), findsOneWidget);
        expect(_iconButtonByTooltip('ここに頂点を追加'), findsOneWidget);
        expect(_iconButtonByTooltip('図形を削除'), findsOneWidget);
        expect(currentPainter(tester).highlightedPolygonId, isNull);

        // 辺を切り替え/ここに頂点を追加/図形を削除 all require a target
        // polygon first, so they start out disabled.
        expect(tester.widget<IconButton>(_iconButtonByTooltip('辺を切り替え')).onPressed, isNull);
        expect(
          tester.widget<IconButton>(_iconButtonByTooltip('ここに頂点を追加')).onPressed,
          isNull,
        );
        expect(tester.widget<IconButton>(_iconButtonByTooltip('図形を削除')).onPressed, isNull);
      },
    );

    testWidgets('図形を切り替え highlights that polygon on the canvas', (tester) async {
      final container = await pumpEditorWithTriangle(tester);
      final polygonId = container.read(canvasProvider).polygons.single.id;

      await tester.tap(_iconButtonByTooltip('図形を切り替え'));
      await tester.pump();

      expect(currentPainter(tester).highlightedPolygonId, polygonId);
    });

    testWidgets(
      '辺を切り替え then ここに頂点を追加 inserts a vertex at that edge\'s midpoint and '
      'selects it immediately',
      (tester) async {
        final container = await pumpEditorWithTriangle(tester);
        final before = container.read(canvasProvider).polygons.single.vertexIds;

        await tester.tap(_iconButtonByTooltip('図形を切り替え'));
        await tester.pump();
        await tester.tap(_iconButtonByTooltip('辺を切り替え'));
        await tester.pump();
        await tester.tap(_iconButtonByTooltip('ここに頂点を追加'));
        await tester.pump();

        final after = container.read(canvasProvider).polygons.single.vertexIds;
        expect(after, hasLength(before.length + 1));

        final selectedId = container.read(selectedVertexProvider);
        expect(selectedId, isNotNull);
        expect(after, contains(selectedId));
        expect(before, isNot(contains(selectedId)));

        // The whole-shape row is gone now that a vertex is selected, and
        // its cycle counters were reset for next time.
        expect(_iconButtonByTooltip('図形を切り替え'), findsNothing);
      },
    );

    testWidgets('図形を削除 removes the targeted polygon', (tester) async {
      final container = await pumpEditorWithTriangle(tester);

      await tester.tap(_iconButtonByTooltip('図形を切り替え'));
      await tester.pump();
      await tester.tap(_iconButtonByTooltip('図形を削除'));
      await tester.pump();

      expect(container.read(canvasProvider).polygons, isEmpty);
    });

    testWidgets(
      'dragging the canvas while a polygon is targeted translates the whole shape',
      (tester) async {
        final container = await pumpEditorWithTriangle(tester);
        final polygonId = container.read(canvasProvider).polygons.single.id;
        final originalPositions = {
          for (final id in container.read(canvasProvider).polygons.single.vertexIds)
            id: container.read(canvasProvider).vertices[id]!.position,
        };

        await tester.tap(_iconButtonByTooltip('図形を切り替え'));
        await tester.pump();

        // Two separate moves are required: the first must clear Flutter's
        // own pan-vs-tap/long-press arena slop (`kPanSlop`, 36 logical px)
        // for `onPanStart` to win the arena over `onLongPressStart` at
        // all — but with the default `DragStartBehavior.start`, that very
        // move is entirely consumed by establishing the drag's starting
        // position and reports as a zero delta. Only the *second* move,
        // once the gesture is already accepted, produces a real
        // `onPanUpdate` delta — that is what should end up translating
        // the polygon.
        const dragBy = Offset(60, 40);
        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
        final gesture = await tester.startGesture(canvasTopLeft + const Offset(20, 20));
        await tester.pump();
        await gesture.moveBy(const Offset(50, 30)); // clears kPanSlop; contributes no delta
        await tester.pump();
        await gesture.moveBy(dragBy);
        await tester.pump();
        await gesture.up();
        await tester.pump();

        final polygon = container.read(canvasProvider).polygons.single;
        expect(polygon.id, polygonId);
        for (final id in polygon.vertexIds) {
          expect(
            container.read(canvasProvider).vertices[id]!.position,
            originalPositions[id]! + dragBy,
          );
        }
      },
    );
  });
}
