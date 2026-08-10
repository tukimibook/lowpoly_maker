import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';
import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/providers/export_provider.dart';
import 'package:polygon_art_app/services/artwork_png_renderer.dart';
import 'package:polygon_art_app/services/gallery_export_target.dart';
import 'package:polygon_art_app/services/share_sheet_target.dart';
import 'package:polygon_art_app/widgets/canvas/polygon_painter.dart';

/// Finds the canvas's own [CustomPaint] specifically — see
/// `test/widget_test.dart`'s identical helper for why `find.byType` alone
/// isn't specific enough once the tree grows past a bare editor screen.
Finder _canvasCustomPaintFinder() {
  return find.byWidgetPredicate((widget) {
    return widget is CustomPaint && widget.painter is PolygonPainter;
  });
}

/// Finds an [IconButton] by its accessible name — see
/// `test/widget_test.dart`'s identical helper.
Finder _iconButtonByTooltip(String tooltip) {
  return find.byWidgetPredicate((widget) {
    return widget is IconButton && widget.tooltip == tooltip;
  });
}

/// Draws and closes one triangular polygon on the already-pumped editor —
/// just enough confirmed geometry for the export menu button to enable
/// itself (`EditorScreen`'s `isEmpty` check).
Future<void> _drawOneTriangle(WidgetTester tester) async {
  final canvasTopLeft = tester.getTopLeft(_canvasCustomPaintFinder());
  await tester.tapAt(canvasTopLeft + const Offset(50, 50));
  await tester.pump();
  await tester.tapAt(canvasTopLeft + const Offset(150, 50));
  await tester.pump();
  await tester.tapAt(canvasTopLeft + const Offset(100, 150));
  await tester.pump();
  await tester.tap(_iconButtonByTooltip('Close shape'));
  await tester.pumpAndSettle();
}

/// Always succeeds with a tiny, fixed PNG payload — this test only cares
/// about *which* target gets called with what, never about pixel content
/// (that's `test/services/artwork_png_renderer_test.dart`'s job).
class _FakeRenderer implements ArtworkPngRenderer {
  Color? lastBackgroundColor;

  @override
  Future<Uint8List?> render(
    Artwork artwork,
    Size canvasSize, {
    Color backgroundColor = kExportBackgroundColor,
  }) async {
    lastBackgroundColor = backgroundColor;
    return Uint8List.fromList([1, 2, 3]);
  }
}

class _RecordingGalleryTarget implements GalleryExportTarget {
  int callCount = 0;
  bool hasAccessResult = true;
  bool requestAccessResult = true;

  @override
  Future<bool> hasAccess() async => hasAccessResult;

  @override
  Future<bool> requestAccess() async => requestAccessResult;

  @override
  Future<void> saveImageBytes(Uint8List bytes, {required String name}) async {
    callCount++;
  }
}

class _RecordingShareTarget implements ShareSheetTarget {
  int callCount = 0;

  @override
  Future<void> shareImageBytes(Uint8List bytes, {required String fileName}) async {
    callCount++;
  }
}

/// A [ShareSheetTarget] that never completes — used to assert the export
/// menu button disables itself (`ExportState.isExporting`) while a share is
/// still in flight.
class _HangingShareTarget implements ShareSheetTarget {
  @override
  Future<void> shareImageBytes(Uint8List bytes, {required String fileName}) {
    return Completer<void>().future;
  }
}

void main() {
  Future<({ProviderContainer container, _FakeRenderer renderer})> pumpEditor(
    WidgetTester tester, {
    GalleryExportTarget? galleryTarget,
    ShareSheetTarget? shareTarget,
  }) async {
    final renderer = _FakeRenderer();
    final container = ProviderContainer(
      overrides: [
        artworkPngRendererProvider.overrideWithValue(renderer),
        galleryExportTargetProvider.overrideWithValue(
          galleryTarget ?? _RecordingGalleryTarget(),
        ),
        shareSheetTargetProvider.overrideWithValue(shareTarget ?? _RecordingShareTarget()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const PolygonArtApp()),
    );
    await tester.tap(find.text('New Artwork'));
    await tester.pumpAndSettle();
    return (container: container, renderer: renderer);
  }

  Finder exportMenuButton() => find.byKey(const Key('export-menu-button'));

  Future<void> chooseExportAndBackground(
    WidgetTester tester, {
    required Key menuItemKey,
    required Key backgroundKey,
  }) async {
    await tester.tap(exportMenuButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(menuItemKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-background-dialog')), findsOneWidget);
    await tester.tap(find.byKey(backgroundKey));
    await tester.pumpAndSettle();
  }

  group('EditorScreen export menu', () {
    testWidgets('is disabled while the canvas is empty', (tester) async {
      await pumpEditor(tester);

      final button = tester.widget<PopupMenuButton<Object?>>(exportMenuButton());
      expect(button.enabled, isFalse);
    });

    testWidgets(
      'drawing a polygon enables it, and choosing gallery + White calls the '
      'gallery target then shows a success SnackBar',
      (tester) async {
        final galleryTarget = _RecordingGalleryTarget();
        final pumped = await pumpEditor(tester, galleryTarget: galleryTarget);
        await _drawOneTriangle(tester);

        final button = tester.widget<PopupMenuButton<Object?>>(exportMenuButton());
        expect(button.enabled, isTrue);

        await chooseExportAndBackground(
          tester,
          menuItemKey: const Key('export-menu-gallery'),
          backgroundKey: const Key('export-background-white'),
        );

        expect(galleryTarget.callCount, 1);
        expect(pumped.renderer.lastBackgroundColor, kExportBackgroundColor);
        expect(find.text('Saved to gallery'), findsOneWidget);
      },
    );

    testWidgets('choosing Transparent passes the transparent background to the renderer', (
      tester,
    ) async {
      final pumped = await pumpEditor(tester);
      await _drawOneTriangle(tester);

      await chooseExportAndBackground(
        tester,
        menuItemKey: const Key('export-menu-share'),
        backgroundKey: const Key('export-background-transparent'),
      );

      expect(pumped.renderer.lastBackgroundColor, kExportTransparentBackgroundColor);
    });

    testWidgets('choosing Share + White calls the share target', (tester) async {
      final shareTarget = _RecordingShareTarget();
      await pumpEditor(tester, shareTarget: shareTarget);
      await _drawOneTriangle(tester);

      await chooseExportAndBackground(
        tester,
        menuItemKey: const Key('export-menu-share'),
        backgroundKey: const Key('export-background-white'),
      );

      expect(shareTarget.callCount, 1);
    });

    testWidgets(
      'shows a spinner instead of the icon, and disables the button, while an export '
      'is still in flight',
      (tester) async {
        await pumpEditor(tester, shareTarget: _HangingShareTarget());
        await _drawOneTriangle(tester);

        await tester.tap(exportMenuButton());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('export-menu-share')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('export-background-white')));
        await tester.pump(); // Don't settle: the share target never completes.

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final button = tester.widget<PopupMenuButton<Object?>>(exportMenuButton());
        expect(button.enabled, isFalse);
      },
    );

    testWidgets('cancelling the background dialog does not call any export target', (
      tester,
    ) async {
      final galleryTarget = _RecordingGalleryTarget();
      final shareTarget = _RecordingShareTarget();
      final pumped = await pumpEditor(
        tester,
        galleryTarget: galleryTarget,
        shareTarget: shareTarget,
      );
      await _drawOneTriangle(tester);

      await tester.tap(exportMenuButton());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-menu-gallery')));
      await tester.pumpAndSettle();
      // Dismiss by tapping outside / barrier — use Navigator.pop via back.
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();

      expect(galleryTarget.callCount, 0);
      expect(shareTarget.callCount, 0);
      expect(pumped.container.read(exportControllerProvider).isExporting, isFalse);
    });
  });
}
