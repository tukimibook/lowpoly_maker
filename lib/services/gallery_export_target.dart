import 'dart:typed_data';

import 'package:gal/gal.dart';

/// The "save this PNG to the device's standard photo gallery" half of
/// Phase Hδ's export — abstracted behind an interface (rather than calling
/// [Gal]'s static methods directly from `ExportController`) purely so tests
/// can substitute a fake that never touches a real platform channel, the
/// same reasoning as `UnderlayPicker` being injected into `UnderlayController`
/// rather than `image_picker` being called inline.
abstract class GalleryExportTarget {
  /// Whether the app already has gallery write access.
  Future<bool> hasAccess();

  /// Prompts the OS permission dialog if needed. Returns whether access was
  /// granted. Callers must treat a `false` return as denial (do not proceed
  /// to a heavy render / `saveImageBytes`).
  Future<bool> requestAccess();

  /// Saves [bytes] (already PNG-encoded) to the gallery under [name].
  ///
  /// [name] must NOT include a file extension: the real ([Gal]-backed)
  /// implementation detects one from [bytes] itself and appends it — a
  /// caller that already appends its own (e.g. `"$title.png"`) ends up
  /// with a broken, double-extensioned file name (`"$title.png.png"`) on
  /// the device's gallery. See `ExportController`'s `_baseFileNameFor`,
  /// which callers should use to build [name].
  ///
  /// Rethrows whatever the underlying platform reports (e.g. [GalException]
  /// — permission denied, disk full, unsupported format) — `ExportController`
  /// is responsible for catching it and turning it into a user-facing
  /// message (Phase Hδ #19), never this target itself.
  Future<void> saveImageBytes(Uint8List bytes, {required String name});
}

/// Thrown when [GalleryExportTarget.requestAccess] returns `false` (or
/// [hasAccess] is false and the request is denied). [ExportController]
/// maps this to a stable English SnackBar string via `_describeError`.
class ExportPermissionDeniedException implements Exception {
  const ExportPermissionDeniedException([this.message = 'Permission denied']);

  final String message;

  @override
  String toString() => message;
}

/// The real, production [GalleryExportTarget] — a thin pass-through to the
/// `gal` plugin.
class GalGalleryExportTarget implements GalleryExportTarget {
  @override
  Future<bool> hasAccess() => Gal.hasAccess();

  @override
  Future<bool> requestAccess() => Gal.requestAccess();

  @override
  Future<void> saveImageBytes(Uint8List bytes, {required String name}) {
    return Gal.putImageBytes(bytes, name: name);
  }
}
