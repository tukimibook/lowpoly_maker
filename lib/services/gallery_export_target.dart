import 'dart:typed_data';

import 'package:gal/gal.dart';

/// The "save this PNG to the device's standard photo gallery" half of
/// Phase Hδ's export — abstracted behind an interface (rather than calling
/// [Gal]'s static methods directly from `ExportController`) purely so tests
/// can substitute a fake that never touches a real platform channel, the
/// same reasoning as `UnderlayPicker` being injected into `UnderlayController`
/// rather than `image_picker` being called inline.
abstract class GalleryExportTarget {
  /// Saves [bytes] (already PNG-encoded) to the gallery under [name].
  /// Rethrows whatever the underlying platform reports (e.g. [GalException]
  /// — permission denied, disk full, unsupported format) — `ExportController`
  /// is responsible for catching it and turning it into a user-facing
  /// message (Phase Hδ #19), never this target itself.
  Future<void> saveImageBytes(Uint8List bytes, {required String name});
}

/// The real, production [GalleryExportTarget] — a thin pass-through to the
/// `gal` plugin.
class GalGalleryExportTarget implements GalleryExportTarget {
  @override
  Future<void> saveImageBytes(Uint8List bytes, {required String name}) {
    return Gal.putImageBytes(bytes, name: name);
  }
}
