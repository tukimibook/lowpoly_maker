import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/underlay_layout.dart';
import 'package:polygon_art_app/models/underlay_ref.dart';

void main() {
  group('UnderlayLayoutPersist', () {
    test('fromLayout / toLayout round-trips offset, scale, opacity (not visible)', () {
      const layout = UnderlayLayout(
        offset: Offset(12.5, -3),
        scale: 1.75,
        opacity: 0.4,
        visible: false,
      );

      final persist = UnderlayLayoutPersist.fromLayout(layout);
      final restored = persist.toLayout();

      expect(restored.offset, layout.offset);
      expect(restored.scale, layout.scale);
      expect(restored.opacity, layout.opacity);
      expect(restored.visible, isTrue);
    });

    test('toJson / fromJson round-trip', () {
      const persist = UnderlayLayoutPersist(
        offsetX: 1,
        offsetY: 2,
        scale: 3,
        opacity: 0.5,
      );

      expect(UnderlayLayoutPersist.fromJson(persist.toJson()), persist);
      expect(persist.toJson().containsKey('visible'), isFalse);
    });
  });

  group('UnderlayRef', () {
    test('toJson / fromJson round-trip imageRelativePath + layout', () {
      const ref = UnderlayRef(
        imageRelativePath: 'underlays/x.jpg',
        layout: UnderlayLayoutPersist(offsetX: 0, offsetY: 0, scale: 1, opacity: 0.8),
      );

      expect(UnderlayRef.fromJson(ref.toJson()), ref);
    });
  });
}
