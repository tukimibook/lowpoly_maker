import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/ring_collapse.dart';

void main() {
  group('collapseConsecutiveRingIds', () {
    test('returns input unchanged when there are no duplicates', () {
      expect(collapseConsecutiveRingIds(['a', 'b', 'c']), ['a', 'b', 'c']);
    });

    test('collapses a consecutive duplicate in the middle of the ring', () {
      expect(collapseConsecutiveRingIds(['a', 'b', 'b', 'c']), ['a', 'b', 'c']);
    });

    test('collapses multiple separate consecutive duplicates', () {
      expect(
        collapseConsecutiveRingIds(['a', 'a', 'b', 'c', 'c']),
        ['a', 'b', 'c'],
      );
    });

    test('drops the trailing entry when first and last match after collapse', () {
      expect(collapseConsecutiveRingIds(['a', 'b', 'c', 'a']), ['a', 'b', 'c']);
    });

    test('returns a list shorter than kMinPolygonVertices as-is when collapse degenerates it', () {
      expect(collapseConsecutiveRingIds(['a', 'a', 'a']), ['a']);
    });

    test('leaves a list with fewer than 2 entries untouched', () {
      expect(collapseConsecutiveRingIds(['a']), ['a']);
      expect(collapseConsecutiveRingIds([]), <String>[]);
    });
  });

  group('collapseConsecutiveOpenIds', () {
    test('returns input unchanged when there are no duplicates', () {
      expect(collapseConsecutiveOpenIds(['a', 'b', 'c']), ['a', 'b', 'c']);
    });

    test('collapses a consecutive duplicate', () {
      expect(collapseConsecutiveOpenIds(['a', 'b', 'b', 'c']), ['a', 'b', 'c']);
    });

    test('does NOT drop the trailing entry even when it matches the first (open path, not a ring)', () {
      expect(collapseConsecutiveOpenIds(['a', 'b', 'c', 'a']), ['a', 'b', 'c', 'a']);
    });

    test('returns an empty list unchanged', () {
      expect(collapseConsecutiveOpenIds([]), <String>[]);
    });

    test('leaves a single-element list untouched', () {
      expect(collapseConsecutiveOpenIds(['a']), ['a']);
    });
  });

  group('hasNonConsecutiveDuplicate', () {
    test('returns false for a list with no duplicates at all', () {
      expect(hasNonConsecutiveDuplicate(['a', 'b', 'c']), isFalse);
    });

    test('returns true for a non-consecutive duplicate (figure-8 / bowtie pattern)', () {
      expect(hasNonConsecutiveDuplicate(['a', 'keep', 'b', 'keep', 'c']), isTrue);
    });

    test('returns false for an already-collapsed ring with no revisits', () {
      final collapsed = collapseConsecutiveRingIds(['a', 'b', 'b', 'c', 'a']);
      expect(hasNonConsecutiveDuplicate(collapsed), isFalse);
    });

    test('returns false for an empty list', () {
      expect(hasNonConsecutiveDuplicate([]), isFalse);
    });

    test('returns false for a single-element list', () {
      expect(hasNonConsecutiveDuplicate(['a']), isFalse);
    });
  });
}
