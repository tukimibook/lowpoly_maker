import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Gallery save-slot policy (Phase R). [baseSlotLimit] is the free allowance;
/// [bonusSlots] is the reserved seam for a later rewarded-ad unlock (v1 keeps
/// it at 0). UI and [AutoSaveService] both read this instead of hardcoding 8.
class GalleryQuota {
  const GalleryQuota({
    this.baseSlotLimit = 8,
    this.bonusSlots = 0,
  });

  /// Free slots available without watching a rewarded ad.
  final int baseSlotLimit;

  /// Extra slots granted later (rewarded ads). v1 is always 0.
  final int bonusSlots;

  int get totalSlots => baseSlotLimit + bonusSlots;

  /// Whether a *new* artwork may be persisted given [currentCount] index
  /// entries. Updates to an id already in the index are not gated here.
  bool canSaveNew(int currentCount) => currentCount < totalSlots;
}

/// Thrown when [AutoSaveService] refuses the first persist of a new artwork
/// because the gallery is at [limit]. Existing-id overwrites never throw this.
class GalleryQuotaExceededException implements Exception {
  const GalleryQuotaExceededException({
    required this.currentCount,
    required this.limit,
  });

  final int currentCount;
  final int limit;

  @override
  String toString() =>
      'GalleryQuotaExceededException(currentCount: $currentCount, limit: $limit)';
}

/// User-facing copy for the quota gates. Japanese matches the Phase R spec.
abstract final class GalleryQuotaMessages {
  static String dialogBody(int limit) =>
      '保存上限（$limit枚）に達しました。新しく保存するにはギャラリーから不要な作品を削除してください。';

  static const String snackBar = '保存上限に達したため保存できません';
}

final galleryQuotaProvider = Provider<GalleryQuota>((ref) => const GalleryQuota());
