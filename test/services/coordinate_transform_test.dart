import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/services/coordinate_transform.dart';

void main() {
  group('ViewportTransform', () {
    test('identity maps screen coordinates straight through to world', () {
      const transform = ViewportTransform.identity;

      expect(transform.screenToWorld(const Offset(10, 20)), const Offset(10, 20));
      expect(transform.worldToScreen(const Offset(10, 20)), const Offset(10, 20));
    });

    test('worldToScreen applies scale then offset', () {
      const transform = ViewportTransform(scale: 2.0, offset: Offset(50, 30));

      expect(transform.worldToScreen(const Offset(10, 10)), const Offset(70, 50));
    });

    test('screenToWorld is the exact inverse of worldToScreen', () {
      const transform = ViewportTransform(scale: 2.5, offset: Offset(-40, 15));
      const worldPoint = Offset(123.4, -56.7);

      final screenPoint = transform.worldToScreen(worldPoint);
      expect(transform.screenToWorld(screenPoint), worldPoint);
    });

    test('copyWith overrides only the given fields', () {
      const transform = ViewportTransform(scale: 2.0, offset: Offset(5, 5));

      final rescaled = transform.copyWith(scale: 3.0);
      expect(rescaled.scale, 3.0);
      expect(rescaled.offset, const Offset(5, 5));

      final panned = transform.copyWith(offset: const Offset(1, 2));
      expect(panned.scale, 2.0);
      expect(panned.offset, const Offset(1, 2));
    });

    test('equality and hashCode are value-based', () {
      const a = ViewportTransform(scale: 1.5, offset: Offset(3, 4));
      const b = ViewportTransform(scale: 1.5, offset: Offset(3, 4));
      const c = ViewportTransform(scale: 1.5, offset: Offset(3, 5));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
