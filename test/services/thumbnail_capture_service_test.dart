import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/services/thumbnail_capture_service.dart';

/// The first 8 bytes of any PNG file (the fixed signature Flutter's own
/// `ui.ImageByteFormat.png` encoder always emits) — asserting on this
/// (rather than an exact byte-for-byte fixture) keeps the test independent
/// of whatever exact pixels/compression the engine happens to produce.
const List<int> _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  group('ThumbnailCaptureService.capture', () {
    testWidgets('captures a mounted RepaintBoundary as PNG bytes', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: const SizedBox(
              width: 100,
              height: 100,
              child: ColoredBox(color: Colors.red),
            ),
          ),
        ),
      );

      // `toImage()`/`toByteData()` complete via a real engine callback, not
      // a fake `Timer` — `runAsync` is required so the test binding's fake
      // async zone doesn't block them from ever resolving.
      final bytes = await tester.runAsync(
        () => ThumbnailCaptureService().capture(key, pixelRatio: 1.0),
      );

      expect(bytes, isNotNull);
      expect(bytes!.sublist(0, 8), _pngSignature);
    });

    testWidgets('returns null for a key that was never attached to anything', (tester) async {
      final key = GlobalKey();

      final bytes = await tester.runAsync(() => ThumbnailCaptureService().capture(key));

      expect(bytes, isNull);
    });

    testWidgets('returns null for a key attached to a widget that is not a RepaintBoundary', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(home: SizedBox(key: key, width: 10, height: 10)),
      );

      final bytes = await tester.runAsync(() => ThumbnailCaptureService().capture(key));

      expect(bytes, isNull);
    });

    testWidgets('respects a custom pixelRatio (smaller ratio -> smaller PNG payload)', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: const SizedBox(
              width: 200,
              height: 200,
              child: ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      );

      final small = await tester.runAsync(
        () => ThumbnailCaptureService().capture(key, pixelRatio: 0.1),
      );
      final large = await tester.runAsync(
        () => ThumbnailCaptureService().capture(key, pixelRatio: 1.0),
      );

      expect(small, isNotNull);
      expect(large, isNotNull);
      expect(small!.length, lessThan(large!.length));
    });
  });
}
