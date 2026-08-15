import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/services/gallery_quota.dart';

void main() {
  group('GalleryQuota', () {
    test('v1 defaults are 8 free slots and 0 bonus slots', () {
      const quota = GalleryQuota();
      expect(quota.baseSlotLimit, 8);
      expect(quota.bonusSlots, 0);
      expect(quota.totalSlots, 8);
    });

    test('canSaveNew is true below the limit and false at or above it', () {
      const quota = GalleryQuota(baseSlotLimit: 8);
      expect(quota.canSaveNew(7), isTrue);
      expect(quota.canSaveNew(8), isFalse);
      expect(quota.canSaveNew(9), isFalse);
    });

    test('bonusSlots increase totalSlots', () {
      const quota = GalleryQuota(baseSlotLimit: 8, bonusSlots: 2);
      expect(quota.totalSlots, 10);
      expect(quota.canSaveNew(8), isTrue);
      expect(quota.canSaveNew(10), isFalse);
    });
  });
}
