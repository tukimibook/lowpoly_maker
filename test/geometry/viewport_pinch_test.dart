import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/geometry/viewport_pinch.dart';
import 'package:polygon_art_app/services/coordinate_transform.dart';

void main() {
  group('applyPinchPan', () {
    test(
      'a pure 1-finger pan (scale == 1) shifts the offset by exactly the '
      'focal point movement, leaving scale untouched',
      () {
        const baseline = ViewportTransform(scale: 2.0, offset: Offset(10, 20));
        const baselineFocalPoint = Offset(100, 100);

        final result = applyPinchPan(
          baselineTransform: baseline,
          baselineFocalPoint: baselineFocalPoint,
          scale: 1.0,
          focalPoint: const Offset(130, 90),
        );

        expect(result.scale, 2.0);
        // The focal point moved by (30, -10) on screen; a pure pan at a
        // fixed scale should carry the offset by exactly that.
        expect(result.offset, const Offset(40, 10));
      },
    );

    test(
      'pinching (scale != 1) keeps the world point under the focal point '
      'pinned in place while scaling around it',
      () {
        const baseline = ViewportTransform.identity;
        const baselineFocalPoint = Offset(200, 150);

        final result = applyPinchPan(
          baselineTransform: baseline,
          baselineFocalPoint: baselineFocalPoint,
          scale: 2.0,
          focalPoint: baselineFocalPoint,
        );

        expect(result.scale, 2.0);
        // The world point that sat under (200, 150) at scale 1 (i.e.
        // itself, since the baseline was identity) must still render at
        // (200, 150) after doubling the scale around it.
        expect(result.worldToScreen(baselineFocalPoint), baselineFocalPoint);
      },
    );

    test(
      'combines scale and focal-point movement: the world point under the '
      'baseline focal point ends up exactly under the new focal point',
      () {
        const baseline = ViewportTransform(scale: 1.5, offset: Offset(-20, 5));
        const baselineFocalPoint = Offset(80, 60);
        const newFocalPoint = Offset(120, 40);

        final worldUnderFinger = baseline.screenToWorld(baselineFocalPoint);

        final result = applyPinchPan(
          baselineTransform: baseline,
          baselineFocalPoint: baselineFocalPoint,
          scale: 1.8,
          focalPoint: newFocalPoint,
        );

        expect(result.scale, closeTo(1.5 * 1.8, 1e-9));
        expect(result.worldToScreen(worldUnderFinger), newFocalPoint);
      },
    );

    test('clamps the resulting scale to [minScale, maxScale]', () {
      const baseline = ViewportTransform.identity;
      const baselineFocalPoint = Offset.zero;

      final zoomedOut = applyPinchPan(
        baselineTransform: baseline,
        baselineFocalPoint: baselineFocalPoint,
        scale: 0.001,
        focalPoint: baselineFocalPoint,
        minScale: 0.2,
        maxScale: 8.0,
      );
      expect(zoomedOut.scale, 0.2);

      final zoomedIn = applyPinchPan(
        baselineTransform: baseline,
        baselineFocalPoint: baselineFocalPoint,
        scale: 1000,
        focalPoint: baselineFocalPoint,
        minScale: 0.2,
        maxScale: 8.0,
      );
      expect(zoomedIn.scale, 8.0);
    });

    test('defaults minScale/maxScale to kMinViewportScale/kMaxViewportScale', () {
      const baseline = ViewportTransform.identity;
      const baselineFocalPoint = Offset.zero;

      final result = applyPinchPan(
        baselineTransform: baseline,
        baselineFocalPoint: baselineFocalPoint,
        scale: 1000,
        focalPoint: baselineFocalPoint,
      );

      expect(result.scale, kMaxViewportScale);
    });
  });
}
