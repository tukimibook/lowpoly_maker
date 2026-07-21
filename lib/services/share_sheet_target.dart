import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// The "hand this PNG to the OS share sheet" half of Phase Hδ's export —
/// abstracted behind an interface for the same reason as
/// [GalleryExportTarget] (`services/gallery_export_target.dart`): so tests
/// never have to touch `share_plus`'s real platform channel.
abstract class ShareSheetTarget {
  /// Opens the platform share sheet for [bytes] (already PNG-encoded),
  /// suggesting [fileName] as the shared file's name. Rethrows whatever the
  /// underlying platform reports — `ExportController` turns that into a
  /// user-facing message (Phase Hδ #19), never this target itself.
  Future<void> shareImageBytes(Uint8List bytes, {required String fileName});
}

/// The real, production [ShareSheetTarget] — a thin pass-through to
/// `share_plus`.
class SharePlusShareSheetTarget implements ShareSheetTarget {
  @override
  Future<void> shareImageBytes(Uint8List bytes, {required String fileName}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'image/png')],
        fileNameOverrides: [fileName],
      ),
    );
  }
}
