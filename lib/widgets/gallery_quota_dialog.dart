import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/gallery_provider.dart';
import '../services/gallery_quota.dart';

/// Primary-gate dialog when the gallery is at [GalleryQuota.totalSlots].
Future<void> showGalleryQuotaReachedDialog(
  BuildContext context,
  GalleryQuota quota,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        key: const Key('gallery-quota-reached-dialog'),
        content: Text(GalleryQuotaMessages.dialogBody(quota.totalSlots)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

/// Refreshes the on-disk index, blocks with [showGalleryQuotaReachedDialog]
/// when full, otherwise resets providers for a new artwork.
///
/// Returns true when the caller should open the editor. Returns false if
/// the slot check failed, the dialog was shown, or [context] unmounted.
Future<bool> prepareNewArtworkIfSlotAvailable({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final allowed = await ref.read(galleryControllerProvider).hasAvailableSlot();
  if (!context.mounted) return false;
  if (!allowed) {
    await showGalleryQuotaReachedDialog(context, ref.read(galleryQuotaProvider));
    return false;
  }
  ref.read(galleryControllerProvider).createNewArtwork();
  return true;
}
