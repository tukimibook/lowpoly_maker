import 'artwork.dart';
import 'underlay_layout.dart';

/// The full persisted "1作品" unit (Phase Hγ): [artwork]'s geometry plus —
/// if this artwork has one — its underlay photo's in-app path and
/// placement.
///
/// [Artwork] itself stays geometry-only (see its own class doc: every field
/// there must be safe to snapshot verbatim in `CanvasNotifier`'s undo
/// stack, and underlay placement is presentation, not geometry). This class
/// is the wider unit [ArtworkRepository] actually reads/writes to disk —
/// composing [underlayImagePath]/[underlayLayout] into the same JSON file
/// as [artwork]'s own fields — so `GalleryScreen`'s "開く（復帰）" action can
/// restore every provider a saved artwork touched (`CanvasNotifier`,
/// `underlayProvider`, `underlayLayoutProvider`), not just the geometry.
class ArtworkDocument {
  const ArtworkDocument({
    required this.artwork,
    this.underlayImagePath,
    this.underlayLayout,
  });

  final Artwork artwork;

  /// Path to the artwork's underlay photo, already copied into this app's
  /// own documents directory (`ArtworkRepository.copyUnderlayImage`) —
  /// never the original picked-from-gallery path, which may later be
  /// deleted or moved. `null` if this artwork has no underlay.
  final String? underlayImagePath;

  /// Placement (offset/scale/opacity) of [underlayImagePath]. `null` if
  /// this artwork has no underlay; ignored (never serialized) when
  /// [underlayImagePath] is `null` even if a caller happens to pass one.
  final UnderlayLayout? underlayLayout;

  /// Deserializes the `ArtworkDocument` v1 schema — [Artwork.fromJson] for
  /// the geometry fields, plus this class's own `underlay` sub-object if
  /// present. Callers are responsible for any `schemaVersion` migration
  /// before calling this, exactly like [Artwork.fromJson].
  factory ArtworkDocument.fromJson(Map<String, dynamic> json) {
    final underlayJson = json['underlay'] as Map<String, dynamic>?;
    final layoutJson = underlayJson?['layout'] as Map<String, dynamic>?;
    return ArtworkDocument(
      artwork: Artwork.fromJson(json),
      underlayImagePath: underlayJson?['imagePath'] as String?,
      underlayLayout: layoutJson == null ? null : UnderlayLayout.fromJson(layoutJson),
    );
  }
}

/// [ArtworkDocument.toJson] — see `ArtworkJson`'s doc (`models/artwork.dart`)
/// for why this is an extension rather than a class-body method (matches
/// that same freezed-adjacent convention for consistency, even though this
/// particular class isn't itself freezed).
extension ArtworkDocumentJson on ArtworkDocument {
  Map<String, dynamic> toJson() {
    final json = artwork.toJson();
    final imagePath = underlayImagePath;
    if (imagePath != null) {
      json['underlay'] = {
        'imagePath': imagePath,
        'layout': (underlayLayout ?? UnderlayLayout.initial).toJson(),
      };
    }
    return json;
  }
}
