import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart' show GalException;

import '../models/artwork.dart';
import '../services/artwork_png_renderer.dart';
import '../services/gallery_export_target.dart';
import '../services/share_sheet_target.dart';

/// The outcome of the most recent Phase Hδ export attempt (ギャラリー保存 or
/// 共有), surfaced by [ExportController] so `EditorScreen` can show it as a
/// `SnackBar` — same "state carries the message, the screen just listens
/// and shows it once" shape as `UnderlayState.errorMessage`.
@immutable
class ExportState {
  const ExportState({this.isExporting = false, this.errorMessage, this.successMessage});

  /// True while a render + save/share is in flight — lets the UI disable
  /// the export button rather than let an artist queue up a second export
  /// (e.g. gallery *and* share) of the same in-progress bytes.
  final bool isExporting;

  /// A user-facing failure message from the most recent attempt (render
  /// failure, permission denial, disk full, ...), or `null` if it succeeded
  /// (or none has been attempted yet) — Phase Hδ #19: never let any of
  /// these crash the app.
  final String? errorMessage;

  /// A user-facing success message ("ギャラリーに保存しました" etc.) from the
  /// most recent attempt, or `null` otherwise. Sharing itself doesn't get
  /// one — the OS share sheet is its own confirmation UI.
  final String? successMessage;

  ExportState copyWith({
    bool? isExporting,
    Object? errorMessage = _unset,
    Object? successMessage = _unset,
  }) {
    return ExportState(
      isExporting: isExporting ?? this.isExporting,
      errorMessage: errorMessage == _unset ? this.errorMessage : errorMessage as String?,
      successMessage: successMessage == _unset ? this.successMessage : successMessage as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ExportState &&
            other.isExporting == isExporting &&
            other.errorMessage == errorMessage &&
            other.successMessage == successMessage);
  }

  @override
  int get hashCode => Object.hash(isExporting, errorMessage, successMessage);
}

const Object _unset = Object();

/// Drives Phase Hδ's PNG export: renders [Artwork] (via [ArtworkPngRenderer],
/// no underlay — see that class's doc) and hands the resulting bytes to
/// either [GalleryExportTarget] (ギャラリー保存) or [ShareSheetTarget] (共有),
/// never letting either's failure escape uncaught (#19 — permission denial,
/// disk full, or any other platform error becomes [ExportState.errorMessage]
/// instead of a crash).
class ExportController extends StateNotifier<ExportState> {
  ExportController(this._renderer, this._galleryTarget, this._shareTarget)
    : super(const ExportState());

  final ArtworkPngRenderer _renderer;
  final GalleryExportTarget _galleryTarget;
  final ShareSheetTarget _shareTarget;

  /// Saves a standard PNG render of [artwork] (at [canvasSize]) to the
  /// device's photo gallery. Returns whether it succeeded — callers that
  /// don't need that (e.g. a fire-and-forget button `onPressed`) can ignore
  /// it and rely on [state] for the `SnackBar` message instead.
  Future<bool> exportToGallery(Artwork artwork, Size canvasSize) async {
    return _runExport(artwork, canvasSize, (bytes) async {
      // `gal`'s `name` must NOT include an extension — it detects one from
      // the bytes themselves and appends it internally (see
      // `GalleryExportTarget.saveImageBytes`'s doc). Passing the
      // extension-suffixed name here would produce a double-extensioned
      // file (e.g. `My Art.png.png`) on the device's gallery.
      await _galleryTarget.saveImageBytes(bytes, name: _baseFileNameFor(artwork));
      return 'ギャラリーに保存しました';
    });
  }

  /// Opens the platform share sheet with a standard PNG render of [artwork]
  /// (at [canvasSize]). Returns whether it succeeded.
  Future<bool> exportViaShareSheet(Artwork artwork, Size canvasSize) async {
    return _runExport(artwork, canvasSize, (bytes) async {
      // Unlike `gal` (see `exportToGallery`), `share_plus`'s
      // `fileNameOverrides` *is* the full, displayed file name, so this one
      // needs the extension.
      await _shareTarget.shareImageBytes(bytes, fileName: '${_baseFileNameFor(artwork)}.png');
      return null; // The share sheet itself is the confirmation UI.
    });
  }

  /// Shared render-then-hand-off-to-[deliver] plumbing for both export
  /// paths above — every failure point (render, deliver) funnels into the
  /// same catch-and-describe handling exactly once, so neither path can
  /// diverge in whether a given failure surfaces a message.
  Future<bool> _runExport(
    Artwork artwork,
    Size canvasSize,
    Future<String?> Function(Uint8List bytes) deliver,
  ) async {
    state = state.copyWith(isExporting: true, errorMessage: null, successMessage: null);
    try {
      final bytes = await _renderer.render(artwork, canvasSize);
      if (bytes == null) {
        state = state.copyWith(
          isExporting: false,
          errorMessage: 'キャンバスの準備ができていません。もう一度お試しください。',
        );
        return false;
      }
      final successMessage = await deliver(bytes);
      state = state.copyWith(isExporting: false, successMessage: successMessage);
      return true;
    } catch (error) {
      state = state.copyWith(isExporting: false, errorMessage: _describeError(error));
      return false;
    }
  }

  /// A short, artist-facing filename *without* an extension — the
  /// artwork's own title (already freeform Japanese/emoji-safe text the
  /// artist chose) with characters that are invalid across every target
  /// filesystem stripped, falling back to the artwork's [Artwork.id] if
  /// that leaves nothing usable (e.g. a title made up entirely of stripped
  /// characters). Callers append whatever extension their own target
  /// actually expects — see [exportToGallery] vs [exportViaShareSheet].
  String _baseFileNameFor(Artwork artwork) {
    final sanitized = artwork.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    // A title made up *entirely* of stripped characters (e.g. "///") would
    // otherwise sanitize into a useless all-underscore name ("___") — just
    // as unusable as an empty one, so it falls back the same way.
    final isUsable = sanitized.isNotEmpty && sanitized.replaceAll('_', '').isNotEmpty;
    return isUsable ? sanitized : artwork.id;
  }

  /// Turns a caught export failure into Japanese, artist-facing text
  /// (Phase Hδ #19) — [GalException] (from `gal`) already carries a
  /// specific reason (`accessDenied`/`notEnoughSpace`/...), so that's
  /// surfaced verbatim; anything else (a `share_plus` platform failure, or
  /// this renderer's own exceptions) falls back to a generic message that
  /// still never exposes a raw stack trace to the artist.
  String _describeError(Object error) {
    if (error is GalException) return error.type.message;
    return '保存に失敗しました: $error';
  }
}

final artworkPngRendererProvider = Provider<ArtworkPngRenderer>((ref) => ArtworkPngRenderer());

final galleryExportTargetProvider = Provider<GalleryExportTarget>(
  (ref) => GalGalleryExportTarget(),
);

final shareSheetTargetProvider = Provider<ShareSheetTarget>((ref) => SharePlusShareSheetTarget());

final exportControllerProvider = StateNotifierProvider<ExportController, ExportState>((ref) {
  // `read`, not `watch` — same reasoning as `underlayPickerProvider`'s use
  // in `underlayProvider`: these are fixed dependencies for the session
  // (only ever swapped in tests), not values whose *changes* should recreate
  // this controller.
  return ExportController(
    ref.read(artworkPngRendererProvider),
    ref.read(galleryExportTargetProvider),
    ref.read(shareSheetTargetProvider),
  );
});
