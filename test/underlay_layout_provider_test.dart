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
  });
}
