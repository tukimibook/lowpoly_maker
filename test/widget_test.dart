import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';
import 'package:polygon_art_app/providers/canvas_background_provider.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/providers/detach_cycle_provider.dart';
import 'package:polygon_art_app/providers/drag_preview_provider.dart';
import 'package:polygon_art_app/providers/polygon_edit_target_provider.dart';
import 'package:polygon_art_app/providers/selected_vertex_provider.dart';
import 'package:polygon_art_app/providers/viewport_provider.dart';
import 'package:polygon_art_app/services/coordinate_transform.dart';
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

  group(
    'Detach then long-press-drag grabs the right vertex (2026-07-16 bug fix)',
    () {
      testWidgets(
        'long-press-dragging the just-vacated spot right after detaching '
        'moves the DETACHED polygon\'s copy, not the original vertex still '
        'held by the neighboring polygon',
        (tester) async {
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
          const sharedSpot = Offset(150, 50);

          // Green: drawn (and so listed in `Artwork.polygons`) first.
          await tester.tapAt(canvasTopLeft + const Offset(50, 50));
          await tester.pump();
          await tester.tapAt(canvasTopLeft + sharedSpot);
          await tester.pump();
          await tester.tapAt(canvasTopLeft + const Offset(100, 150));
          await tester.pump();
          await tester.tap(_iconButtonByTooltip('多角形を閉じる'));
          await tester.pump();

          // Purple: its first tap snaps onto the same spot as green's
          // second vertex, welding the two — and purple is listed
          // *second* in `Artwork.polygons`, which is exactly the ordering
          // that used to make the bug reproduce (the vertex still held by
          // the "later" polygon — purple's original — used to win the
          // coincidence tie over the freshly detached copy).
          await tester.tap(find.byTooltip('描画モード'));
          await tester.pump();
          await tester.tapAt(canvasTopLeft + sharedSpot);
          await tester.pump();
          await tester.tapAt(canvasTopLeft + const Offset(250, 50));
          await tester.pump();
          await tester.tapAt(canvasTopLeft + const Offset(200, 150));
          await tester.pump();
          await tester.tap(_iconButtonByTooltip('多角形を閉じる'));
          await tester.pump();

          final greenId = container.read(canvasProvider).polygons[0].id;
          final purpleId = container.read(canvasProvider).polygons[1].id;
          final sharedId = container.read(canvasProvider).polygons[0].vertexIds[1];
          expect(
            container.read(canvasProvider).polygons[1].vertexIds,
            contains(sharedId),
          );

          await tester.tap(find.byTooltip('編集モード'));
          await tester.pump();
          await tester.tapAt(canvasTopLeft + sharedSpot);
          await tester.pump();
          expect(container.read(selectedVertexProvider), sharedId);

          // No cycling needed: the detach target defaults to the first
          // referencing polygon, which is green (drawn first).
          await tester.tap(_iconButtonByTooltip('選択中の多角形から切り離す'));
          await tester.pump();

          final copyId = container.read(selectedVertexProvider);
          expect(copyId, isNotNull);
          expect(copyId, isNot(sharedId));
          expect(
            container.read(canvasProvider).polygons.singleWhere((p) => p.id == greenId).vertexIds,
            contains(copyId),
          );
          expect(
            container.read(canvasProvider).polygons.singleWhere((p) => p.id == purpleId).vertexIds,
            contains(sharedId),
          );

          // Long-press (holding still long enough for the timer to fire,
          // without moving — a plain pan would instead target whichever
          // whole polygon is currently cycled, an unrelated feature) right
          // on the now-coincident spot, then drag away.
          final gesture = await tester.startGesture(canvasTopLeft + sharedSpot);
          await tester.pump(const Duration(milliseconds: 600));
          await gesture.moveTo(canvasTopLeft + const Offset(150, 120));
          await tester.pump();
          await gesture.up();
          await tester.pump();

          final vertices = container.read(canvasProvider).vertices;
          // The detached copy (green's) followed the drag...
          expect(vertices[copyId]!.position, const Offset(150, 120));
          // ...while purple's original vertex, still at the old spot, did
          // not move at all.
          expect(vertices[sharedId]!.position, sharedSpot);
        },
      );
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

        // A single move, well past Flutter's own scale-vs-tap/long-press
        // arena slop (`kPanSlop`, 36 logical px — needed for `onScaleStart`
        // to win the arena over `onLongPressStart` at all), is enough: unlike
        // `PanGestureRecognizer` (whose very first accepted move used to be
        // entirely consumed by establishing the drag's starting position
        // and reported as a zero delta, requiring an extra throwaway move
        // before this test's real one), `ScaleGestureRecognizer` reports
        // `ScaleUpdateDetails.focalPointDelta` as the *actual* incremental
        // movement for every update, including the one that just won the
        // arena — see `.cursor/plans/plan_phase_H_beta.md`, 2026-07-17
        // 検討メモ.
        const dragBy = Offset(60, 40);
        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
        final gesture = await tester.startGesture(canvasTopLeft + const Offset(20, 20));
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

    testWidgets(
      'a second finger joining mid-drag while a polygon is targeted '
      'discards the in-progress whole-shape drag instead of committing it '
      'where the first finger currently sits, and switches to viewport '
      'pinch/pan instead',
      (tester) async {
        final container = await pumpEditorWithTriangle(tester);
        final originalPositions = {
          for (final id in container.read(canvasProvider).polygons.single.vertexIds)
            id: container.read(canvasProvider).vertices[id]!.position,
        };

        await tester.tap(_iconButtonByTooltip('図形を切り替え'));
        await tester.pump();

        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
        final finger1 = await tester.startGesture(
          canvasTopLeft + const Offset(20, 20),
        );
        await tester.pump();
        await finger1.moveBy(const Offset(60, 40));
        await tester.pump();

        // A second finger joins mid-drag — must discard the in-progress
        // whole-shape translation (not commit it at wherever finger 1
        // currently sits), same as the draw-mode equivalent above.
        final finger2 = await tester.startGesture(
          canvasTopLeft + const Offset(220, 20),
        );
        await tester.pump();
        await finger1.up();
        await finger2.up();
        await tester.pump();

        // Positions are exactly what they were before the gesture — proof
        // `commitPolygonDrag`/`translatePolygon` never ran; only the
        // (separately tested) viewport pan/zoom math handled this gesture.
        final polygon = container.read(canvasProvider).polygons.single;
        for (final id in polygon.vertexIds) {
          expect(
            container.read(canvasProvider).vertices[id]!.position,
            originalPositions[id],
          );
        }
      },
    );
  });

  group(
    'Edit mode selected-vertex UX enhancements (2026-07-17: seamless '
    'switch-and-drag + 選択解除)',
    () {
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

      testWidgets(
        'long-press-dragging directly onto a different, already-visible '
        'vertex switches the selection to it and resets the detach/'
        'whole-shape cycle counters',
        (tester) async {
          final container = await pumpEditorWithTriangle(tester);
          final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
          final polygon = container.read(canvasProvider).polygons.single;
          final vertexAId = polygon.vertexIds[0];
          final vertexBId = polygon.vertexIds[1];
          final vertexAPos = container.read(canvasProvider).vertices[vertexAId]!.position;
          final vertexBPos = container.read(canvasProvider).vertices[vertexBId]!.position;

          await tester.tapAt(canvasTopLeft + vertexAPos);
          await tester.pump();
          expect(container.read(selectedVertexProvider), vertexAId);

          // Leave behind cycle state as if the artist had been mid-cycle —
          // switching to a genuinely different vertex must clear all of
          // it, exactly like tapping a different vertex already does via
          // `handleEditTap`.
          container.read(detachCycleIndexProvider.notifier).state = 3;
          container.read(polygonCycleIndexProvider.notifier).state = 2;
          container.read(edgeCycleIndexProvider.notifier).state = 1;

          final gesture = await tester.startGesture(canvasTopLeft + vertexBPos);
          await tester.pump(const Duration(milliseconds: 600));
          await gesture.moveBy(const Offset(5, 5));
          await tester.pump();
          await gesture.up();
          await tester.pump();

          expect(container.read(selectedVertexProvider), vertexBId);
          expect(container.read(detachCycleIndexProvider), 0);
          expect(container.read(polygonCycleIndexProvider), -1);
          expect(container.read(edgeCycleIndexProvider), -1);
        },
      );

      testWidgets(
        're-long-pressing the SAME already-selected vertex (e.g. to '
        'reposition it) leaves the detach cycle counter untouched — the '
        'guard condition must only fire on an actual switch',
        (tester) async {
          final container = await pumpEditorWithTriangle(tester);
          final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
          final polygon = container.read(canvasProvider).polygons.single;
          final vertexAId = polygon.vertexIds[0];
          final vertexAPos = container.read(canvasProvider).vertices[vertexAId]!.position;

          await tester.tapAt(canvasTopLeft + vertexAPos);
          await tester.pump();
          expect(container.read(selectedVertexProvider), vertexAId);

          container.read(detachCycleIndexProvider.notifier).state = 3;

          final gesture = await tester.startGesture(canvasTopLeft + vertexAPos);
          await tester.pump(const Duration(milliseconds: 600));
          await gesture.moveBy(const Offset(5, 5));
          await tester.pump();
          await gesture.up();
          await tester.pump();

          expect(container.read(selectedVertexProvider), vertexAId);
          expect(container.read(detachCycleIndexProvider), 3);
        },
      );

      testWidgets(
        '選択を解除 clears the selection, resets the detach cycle, and '
        'brings back the whole-shape target row',
        (tester) async {
          final container = await pumpEditorWithTriangle(tester);
          final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
          final polygon = container.read(canvasProvider).polygons.single;
          final vertexAId = polygon.vertexIds[0];
          final vertexAPos = container.read(canvasProvider).vertices[vertexAId]!.position;

          await tester.tapAt(canvasTopLeft + vertexAPos);
          await tester.pump();
          expect(container.read(selectedVertexProvider), vertexAId);
          expect(_iconButtonByTooltip('図形を切り替え'), findsNothing);
          expect(_iconButtonByTooltip('選択を解除'), findsOneWidget);

          container.read(detachCycleIndexProvider.notifier).state = 3;

          await tester.tap(_iconButtonByTooltip('選択を解除'));
          await tester.pump();

          expect(container.read(selectedVertexProvider), isNull);
          expect(container.read(detachCycleIndexProvider), 0);
          expect(_iconButtonByTooltip('図形を切り替え'), findsOneWidget);
        },
      );

      testWidgets(
        '選択を解除 is also present alongside the ♻️/✂️ pair when the '
        'selected vertex is shared between two polygons',
        (tester) async {
          final container = await pumpEditorWithTriangle(tester);
          final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());

          // Draw a second triangle sharing a vertex with the first, then
          // select that shared vertex.
          final sharedSpot = container
              .read(canvasProvider)
              .vertices[container.read(canvasProvider).polygons.single.vertexIds[1]]!
              .position;

          await tester.tap(find.byTooltip('描画モード'));
          await tester.pump();
          await tester.tapAt(canvasTopLeft + sharedSpot);
          await tester.pump();
          await tester.tapAt(canvasTopLeft + const Offset(250, 50));
          await tester.pump();
          await tester.tapAt(canvasTopLeft + const Offset(200, 150));
          await tester.pump();
          await tester.tap(_iconButtonByTooltip('多角形を閉じる'));
          await tester.pump();

          await tester.tap(find.byTooltip('編集モード'));
          await tester.pump();
          await tester.tapAt(canvasTopLeft + sharedSpot);
          await tester.pump();

          expect(_iconButtonByTooltip('切り離す多角形を切り替え'), findsOneWidget);
          expect(_iconButtonByTooltip('選択中の多角形から切り離す'), findsOneWidget);
          expect(_iconButtonByTooltip('選択を解除'), findsOneWidget);
        },
      );
    },
  );

  group('Phase Hβ: viewport pinch/pan gesture (2026-07-17)', () {
    Future<ProviderContainer> pumpEditor(WidgetTester tester) async {
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

    testWidgets(
      'pinching outward with two fingers zooms in (scale increases) around '
      'their fixed midpoint, without placing any draft point',
      (tester) async {
        final container = await pumpEditor(tester);
        // Eraser mode, on an empty canvas: its 1-finger action
        // (`handleEraseTap`, fired once from `onScaleStart`) is a no-op
        // with nothing under the touch to erase, so a pinch/pan started
        // here is guaranteed to have no side effect on `Artwork` — while
        // still sharing draw mode's `GestureDetector` (a lone
        // `ScaleGestureRecognizer`, no competing tap/long-press
        // recognizers), so the arena resolves immediately with no slop,
        // just like a real single-`ScaleGestureRecognizer` widget. Edit
        // mode's extra tap/long-press recognizers would otherwise eat a
        // chunk of these small steps as slop before the arena resolves.
        await tester.tap(find.byTooltip('消しゴムモード'));
        await tester.pump();
        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
        // Symmetric about a fixed midpoint (200, 150), so the focal point
        // never moves — isolates the scale change from any panning.
        final finger1 = await tester.startGesture(
          canvasTopLeft + const Offset(150, 150),
        );
        await tester.pump();
        final finger2 = await tester.startGesture(
          canvasTopLeft + const Offset(250, 150),
        );
        await tester.pump();

        // Small, interleaved steps for *both* fingers — real touch hardware
        // reports incremental movement for every pointer roughly in sync;
        // moving one finger's full distance in a single jump before the
        // other has moved at all (which a real pinch never does) would
        // itself distort the focal point Flutter reports, since
        // `onScaleStart` for the newly-added second finger only fires on
        // the *next* pointer event after it touches down — by which point
        // this step's own movement has already happened.
        const steps = 50;
        for (var i = 0; i < steps; i++) {
          await finger1.moveBy(const Offset(-1, 0));
          await finger2.moveBy(const Offset(1, 0));
        }
        await tester.pump();
        await finger1.up();
        await finger2.up();
        await tester.pump();

        final transform = container.read(viewportProvider).value;
        expect(transform.scale, closeTo(2.0, 0.1));
        // The world point under the fixed midpoint (200, 150) — which,
        // since the viewport started at identity, is itself — must still
        // render right there after zooming around it.
        final rendered = transform.worldToScreen(const Offset(200, 150));
        expect(rendered.dx, closeTo(200, 3));
        expect(rendered.dy, closeTo(150, 3));
        expect(container.read(canvasProvider).polygons, isEmpty);
        expect(container.read(canvasProvider).draftVertexIds, isEmpty);
      },
    );

    testWidgets(
      'panning with two fingers moving in lockstep (no span change) shifts '
      "the viewport's offset by exactly that movement, leaving scale at 1",
      (tester) async {
        final container = await pumpEditor(tester);
        // Same reasoning as the pinch test above: eraser mode on an empty
        // canvas has no 1-finger side effect, and shares draw mode's
        // slop-free single-recognizer `GestureDetector`.
        await tester.tap(find.byTooltip('消しゴムモード'));
        await tester.pump();
        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
        const delta = Offset(40, -25);

        final finger1 = await tester.startGesture(
          canvasTopLeft + const Offset(150, 150),
        );
        await tester.pump();
        final finger2 = await tester.startGesture(
          canvasTopLeft + const Offset(250, 150),
        );
        await tester.pump();

        // Small, interleaved steps for both fingers — see the pinch test
        // above for why a single full-distance jump on just one finger
        // would itself distort the reported focal point.
        const steps = 50;
        final stepDelta = delta / steps.toDouble();
        for (var i = 0; i < steps; i++) {
          await finger1.moveBy(stepDelta);
          await finger2.moveBy(stepDelta);
        }
        await tester.pump();
        await finger1.up();
        await finger2.up();
        await tester.pump();

        final transform = container.read(viewportProvider).value;
        expect(transform.scale, closeTo(1.0, 0.05));
        expect(transform.offset.dx, closeTo(delta.dx, 2));
        expect(transform.offset.dy, closeTo(delta.dy, 2));
        expect(container.read(canvasProvider).draftVertexIds, isEmpty);
      },
    );

    testWidgets(
      'touching a second finger down mid-draw discards the in-progress '
      'point instead of committing it at the first finger\u2019s position '
      '(a real pinch never has both fingers touch down in exactly the same '
      'frame), and any further movement pans/zooms the viewport instead of '
      'drawing more points',
      (tester) async {
        final container = await pumpEditor(tester);
        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
        const singleFingerStart = Offset(80, 80);

        final finger1 = await tester.startGesture(
          canvasTopLeft + singleFingerStart,
        );
        await tester.pump();
        expect(container.read(dragPreviewProvider).value, isNotNull);

        // A second finger joins while the first is still down and hasn't
        // moved — per Flutter's own `ScaleGestureRecognizer`, this ends the
        // 1-finger sub-cycle right where finger 1 currently sits, which
        // `PolygonCanvas` must read as "discard whatever finger 1 alone was
        // doing", not "commit it as if finger 1 had just been released
        // normally" — otherwise starting an ordinary pinch would reliably
        // leave behind an unwanted point at the first finger's landing
        // spot.
        final finger2 = await tester.startGesture(
          canvasTopLeft + const Offset(280, 80),
        );
        await tester.pump();

        expect(container.read(canvasProvider).draftVertexIds, isEmpty);
        expect(container.read(dragPreviewProvider).value, isNull);

        // Both fingers now move together (a plain pan) — must NOT be
        // reinterpreted as a draw action once a pinch/pan has started,
        // even though only one of them keeps moving here.
        await finger1.moveTo(canvasTopLeft + const Offset(120, 80));
        await finger2.moveTo(canvasTopLeft + const Offset(320, 80));
        await tester.pump();
        await finger1.up();
        await finger2.up();
        await tester.pump();

        // Nothing was ever committed to the artwork, so there's nothing an
        // artist could even want to undo from this gesture.
        expect(container.read(canvasProvider).draftVertexIds, isEmpty);
        expect(container.read(canvasProvider.notifier).canUndo, isFalse);
      },
    );

    testWidgets(
      '全体表示に戻す resets an arbitrary pan/zoom back to identity',
      (tester) async {
        final container = await pumpEditor(tester);
        container.read(viewportProvider).value = const ViewportTransform(
          scale: 2.5,
          offset: Offset(120, -40),
        );
        await tester.pump();

        await tester.tap(_iconButtonByTooltip('全体表示に戻す'));
        await tester.pump();

        expect(
          container.read(viewportProvider).value,
          ViewportTransform.identity,
        );
      },
    );

    testWidgets(
      'at a zoomed-in scale, the self-close double-tap gesture keeps a '
      'constant on-screen tolerance instead of silently shrinking in world '
      'space (regression guard for the un-scaled-tolerance bug)',
      (tester) async {
        final container = await pumpEditor(tester);
        container.read(viewportProvider).value = const ViewportTransform(
          scale: 2.0,
          offset: Offset.zero,
        );
        await tester.pump();

        final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
        // Screen positions; PolygonCanvas converts these to world
        // coordinates via the scale-2 viewport before ever calling
        // CanvasNotifier.
        await tester.tapAt(canvasTopLeft + const Offset(50, 50));
        await tester.pump();
        await tester.tapAt(canvasTopLeft + const Offset(350, 50));
        await tester.pump();
        await tester.tapAt(canvasTopLeft + const Offset(200, 350));
        await tester.pump();
        // First tap of the pair: near the draft's own start on screen.
        await tester.tapAt(canvasTopLeft + const Offset(60, 50));
        await tester.pump();
        // Second tap of the pair, 30 *screen* px from the first — at scale
        // 2 that's 15 *world* px, which exceeds the correctly-scaled
        // tolerance (kDoubleTapMaxDistance / 2 = 10) and so must NOT
        // self-close; a caller that forgot to scale this down (still
        // comparing against the raw, un-scaled kDoubleTapMaxDistance = 20)
        // would incorrectly treat this as a double-tap and close here.
        await tester.tapAt(canvasTopLeft + const Offset(60, 80));
        await tester.pump();

        expect(container.read(canvasProvider).polygons, isEmpty);
        expect(container.read(canvasProvider).draftVertexIds, hasLength(5));
      },
    );
  });
}
