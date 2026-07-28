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
  @override
  Future<Uint8List?> render(
    Artwork artwork,
    Size canvasSize, {
    Color backgroundColor = kExportBackgroundColor,
  }) async => Uint8List.fromList([1, 2, 3]);
}

class _RecordingGalleryTarget implements GalleryExportTarget {
  int callCount = 0;

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
  Future<ProviderContainer> pumpEditor(
    WidgetTester tester, {
    GalleryExportTarget? galleryTarget,
    ShareSheetTarget? shareTarget,
  }) async {
    final container = ProviderContainer(
      overrides: [
        artworkPngRendererProvider.overrideWithValue(_FakeRenderer()),
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
    return container;
  }

  Finder exportMenuButton() => find.byKey(const Key('export-menu-button'));

  group('EditorScreen export menu', () {
    testWidgets('is disabled while the canvas is empty', (tester) async {
      await pumpEditor(tester);

      final button = tester.widget<PopupMenuButton<Object?>>(exportMenuButton());
      expect(button.enabled, isFalse);
    });

    testWidgets(
      'drawing a polygon enables it, and choosing "ギャラリーに保存" calls the gallery '
      'target then shows a success SnackBar',
      (tester) async {
        final galleryTarget = _RecordingGalleryTarget();
        await pumpEditor(tester, galleryTarget: galleryTarget);
        await _drawOneTriangle(tester);

        final button = tester.widget<PopupMenuButton<Object?>>(exportMenuButton());
        expect(button.enabled, isTrue);

        await tester.tap(exportMenuButton());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('export-menu-gallery')));
        await tester.pumpAndSettle();

        expect(galleryTarget.callCount, 1);
        expect(find.text('Saved to gallery'), findsOneWidget);
      },
    );

    testWidgets('choosing "共有" calls the share target', (tester) async {
      final shareTarget = _RecordingShareTarget();
      await pumpEditor(tester, shareTarget: shareTarget);
      await _drawOneTriangle(tester);

      await tester.tap(exportMenuButton());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-menu-share')));
      await tester.pumpAndSettle();

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
        await tester.pump(); // Don't settle: the share target never completes.

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final button = tester.widget<PopupMenuButton<Object?>>(exportMenuButton());
        expect(button.enabled, isFalse);
      },
    );
  });
}
