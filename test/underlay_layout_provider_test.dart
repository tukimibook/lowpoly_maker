import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/underlay_layout.dart';
import 'package:polygon_art_app/providers/underlay_layout_provider.dart';

void main() {
  group('UnderlayLayoutController', () {
    test('starts at the identity layout (nothing imported yet)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(underlayLayoutProvider).value, UnderlayLayout.initial);
    });

    test('setLayout replaces the whole value, e.g. a fit-to-canvas result', () {
      final controller = ProviderContainer().read(underlayLayoutProvider);

      const fitted = UnderlayLayout(offset: Offset(10, 20), scale: 0.5);
      controller.setLayout(fitted);

      expect(controller.value, fitted);
    });

    test('setVisible/setOpacity only touch their own field', () {
      final controller = ProviderContainer().read(underlayLayoutProvider);
      controller.setLayout(const UnderlayLayout(offset: Offset(5, 5), scale: 2.0, opacity: 0.6));

      controller.setVisible(false);
      expect(controller.value.visible, isFalse);
      expect(controller.value.offset, const Offset(5, 5));
      expect(controller.value.opacity, 0.6);

      controller.setOpacity(0.2);
      expect(controller.value.opacity, 0.2);
      expect(controller.value.visible, isFalse);
      expect(controller.value.scale, 2.0);
    });

    test('the provider hands out the same controller instance on repeated reads', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(underlayLayoutProvider),
        same(container.read(underlayLayoutProvider)),
      );
    });

    group('cycleOpacity', () {
      test('advances through the documented steps in order, wrapping at the end', () {
        final controller = ProviderContainer().read(underlayLayoutProvider);
        expect(kUnderlayOpacitySteps, [0.0, 0.25, 0.5, 0.75, 1.0]);

        // Starts fully opaque (UnderlayLayout.initial's default) — the
        // last step — so the very first cycle wraps back to the first.
        expect(controller.value.opacity, 1.0);

        controller.cycleOpacity();
        expect(controller.value.opacity, 0.0);
        controller.cycleOpacity();
        expect(controller.value.opacity, 0.25);
        controller.cycleOpacity();
        expect(controller.value.opacity, 0.5);
        controller.cycleOpacity();
        expect(controller.value.opacity, 0.75);
        controller.cycleOpacity();
        expect(controller.value.opacity, 1.0);
      });

      test('snaps to the nearest step before advancing, for an off-step value', () {
        final controller = ProviderContainer().read(underlayLayoutProvider);
        controller.setOpacity(0.42); // nearest step is 0.5 -> advances to 0.75

        controller.cycleOpacity();

        expect(controller.value.opacity, 0.75);
      });

      test('only touches opacity, leaving offset/scale/visible untouched', () {
        final controller = ProviderContainer().read(underlayLayoutProvider);
        controller.setLayout(
          const UnderlayLayout(offset: Offset(3, 4), scale: 1.5, opacity: 1.0, visible: false),
        );

        controller.cycleOpacity();

        expect(controller.value.offset, const Offset(3, 4));
        expect(controller.value.scale, 1.5);
        expect(controller.value.visible, isFalse);
        expect(controller.value.opacity, 0.0);
      });
    });
  });
}
