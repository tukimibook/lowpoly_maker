import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/geometry/underlay_fit.dart';

void main() {
  group('fitUnderlayToCanvas', () {
    test('a wider-than-canvas image is fit by width, and centered vertically', () {
      final layout = fitUnderlayToCanvas(
        imageSize: const Size(2000, 1000),
        canvasSize: const Size(1000, 1000),
      );

      expect(layout.scale, 0.5);
      // Fitted size is 1000x500; centered within a 1000x1000 canvas.
      expect(layout.offset, const Offset(0, 250));
      expect(layout.visible, isTrue);
      expect(layout.opacity, 1.0);
    });

    test('a taller-than-canvas image is fit by height, and centered horizontally', () {
      final layout = fitUnderlayToCanvas(
        imageSize: const Size(1000, 2000),
        canvasSize: const Size(1000, 1000),
      );

      expect(layout.scale, 0.5);
      expect(layout.offset, const Offset(250, 0));
    });

    test('an image already smaller than the canvas is scaled up, not down', () {
      final layout = fitUnderlayToCanvas(
        imageSize: const Size(100, 50),
        canvasSize: const Size(1000, 1000),
      );

      // Contain-fit still picks the limiting axis (width here: 1000/100=10
      // vs height 1000/50=20) rather than always scaling to fill.
      expect(layout.scale, 10.0);
      expect(layout.offset, const Offset(0, 250));
    });

    test('passes opacity/visible through unchanged, defaulting to fully shown', () {
      final defaulted = fitUnderlayToCanvas(
        imageSize: const Size(100, 100),
        canvasSize: const Size(200, 200),
      );
      expect(defaulted.opacity, 1.0);
      expect(defaulted.visible, isTrue);

      final carried = fitUnderlayToCanvas(
        imageSize: const Size(100, 100),
        canvasSize: const Size(200, 200),
        opacity: 0.4,
        visible: false,
      );
      expect(carried.opacity, 0.4);
      expect(carried.visible, isFalse);
    });

    test('a degenerate (zero) image size falls back to an identity layout '
        'instead of dividing by zero', () {
      final layout = fitUnderlayToCanvas(
        imageSize: Size.zero,
        canvasSize: const Size(200, 200),
      );

      expect(layout.scale, 1.0);
      expect(layout.offset, Offset.zero);
    });

    test('a degenerate (zero) canvas size falls back to an identity layout', () {
      final layout = fitUnderlayToCanvas(
        imageSize: const Size(100, 100),
        canvasSize: Size.zero,
      );

      expect(layout.scale, 1.0);
      expect(layout.offset, Offset.zero);
    });
  });
}
