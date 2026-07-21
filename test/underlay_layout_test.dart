import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/models/underlay_layout.dart';

void main() {
  group('UnderlayLayout', () {
    test('copyWith only overrides the given fields', () {
      const layout = UnderlayLayout(
        offset: Offset(10, 20),
        scale: 2.0,
        opacity: 0.6,
        visible: false,
      );

      final moved = layout.copyWith(offset: const Offset(30, 40));

      expect(moved.offset, const Offset(30, 40));
      expect(moved.scale, 2.0);
      expect(moved.opacity, 0.6);
      expect(moved.visible, isFalse);
    });

    test('toMap/fromMap round-trips offset, scale, and opacity', () {
      const layout = UnderlayLayout(offset: Offset(12.5, -3), scale: 1.75, opacity: 0.4);

      final restored = UnderlayLayout.fromMap(layout.toMap());

      expect(restored.offset, layout.offset);
      expect(restored.scale, layout.scale);
      expect(restored.opacity, layout.opacity);
    });

    test('fromMap defaults opacity to fully opaque when absent (older documents)', () {
      final restored = UnderlayLayout.fromMap({'offsetX': 0.0, 'offsetY': 0.0, 'scale': 1.0});

      expect(restored.opacity, 1.0);
    });

    test('toMap deliberately omits visible (Hγ decision, 2026-07-20: not persisted)', () {
      const layout = UnderlayLayout(offset: Offset.zero, scale: 1.0, visible: false);

      expect(layout.toMap().containsKey('visible'), isFalse);
    });

    test('toJson/fromJson are aliases of toMap/fromMap (ArtworkDocument naming)', () {
      const layout = UnderlayLayout(offset: Offset(12.5, -3), scale: 1.75, opacity: 0.4);

      expect(layout.toJson(), layout.toMap());

      final restored = UnderlayLayout.fromJson(layout.toJson());
      expect(restored.offset, layout.offset);
      expect(restored.scale, layout.scale);
      expect(restored.opacity, layout.opacity);
    });

    test('worldToLocal inverts the offset/scale placement', () {
      const layout = UnderlayLayout(offset: Offset(100, 50), scale: 2.0);

      expect(layout.worldToLocal(const Offset(120, 70)), const Offset(10, 10));
    });

    test('equality and hashCode are value-based', () {
      const a = UnderlayLayout(offset: Offset(1, 2), scale: 1.5, opacity: 0.8, visible: false);
      const b = UnderlayLayout(offset: Offset(1, 2), scale: 1.5, opacity: 0.8, visible: false);
      const c = UnderlayLayout(offset: Offset(1, 2), scale: 1.5, opacity: 0.8);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
