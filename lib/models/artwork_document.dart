import '../utils/documents_path.dart';
import 'artwork.dart';
import 'underlay_layout.dart';
import 'underlay_ref.dart';

/// The full persisted "1作品" unit (Phase Hγ v1): geometry ([artwork]) plus
/// document metadata ([schemaVersion], [createdAt], [updatedAt]) and an
/// optional underlay reference.
///
/// [Artwork] itself stays geometry-only (safe to snapshot verbatim in
/// `CanvasNotifier`'s undo stack). Timestamps and underlay live only here
/// so undo can never rewind `updatedAt` or swap underlay paths.
///
/// On-disk JSON is flat — metadata and geometry fields share the root
/// object; [underlay] is an optional nested object.
class ArtworkDocument {
  ArtworkDocument({
    this.schemaVersion = kArtworkSchemaVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
    required this.artwork,
    this.underlay,
  }) : createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  final int schemaVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Artwork artwork;

  /// Underlay photo (documents-relative path) + placement. `null` if this
  /// artwork has no underlay.
  final UnderlayRef? underlay;

  ArtworkDocument copyWith({
    int? schemaVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
    Artwork? artwork,
    UnderlayRef? underlay,
    bool clearUnderlay = false,
  }) {
    return ArtworkDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      artwork: artwork ?? this.artwork,
      underlay: clearUnderlay ? null : (underlay ?? this.underlay),
    );
  }

  /// Builds a document from the live editor session, converting an absolute
  /// underlay path (if any) into a documents-relative [UnderlayRef].
  factory ArtworkDocument.fromSession({
    required Artwork artwork,
    required String documentsPath,
    String? underlayAbsolutePath,
    UnderlayLayout? underlayLayout,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    UnderlayRef? underlay;
    final absolutePath = underlayAbsolutePath;
    if (absolutePath != null) {
      underlay = UnderlayRef(
        imageRelativePath: toDocumentsRelativePath(absolutePath, documentsPath),
        layout: UnderlayLayoutPersist.fromLayout(
          underlayLayout ?? UnderlayLayout.initial,
        ),
      );
    }
    return ArtworkDocument(
      artwork: artwork,
      underlay: underlay,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Absolute filesystem path for [underlay], resolved against
  /// [documentsPath]. `null` when there is no underlay.
  String? resolvedUnderlayAbsolutePath(String documentsPath) {
    final ref = underlay;
    if (ref == null) return null;
    return resolveDocumentsAbsolutePath(ref.imageRelativePath, documentsPath);
  }

  /// Deserializes the `ArtworkDocument` v1 schema. Callers are responsible
  /// for any `schemaVersion` migration *before* calling this.
  ///
  /// Each confirmed polygon ring is checked with [assertConfirmedRingIds]
  /// (via [Artwork.fromJson]).
  factory ArtworkDocument.fromJson(Map<String, dynamic> json) {
    final underlayJson = json['underlay'] as Map<String, dynamic>?;
    final createdAtRaw = json['createdAt'] as String?;
    final updatedAtRaw = json['updatedAt'] as String?;
    final now = DateTime.now().toUtc();

    return ArtworkDocument(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? kArtworkSchemaVersion,
      createdAt: createdAtRaw != null ? DateTime.parse(createdAtRaw).toUtc() : now,
      updatedAt: updatedAtRaw != null ? DateTime.parse(updatedAtRaw).toUtc() : now,
      artwork: Artwork.fromJson(json),
      underlay: underlayJson == null ? null : UnderlayRef.fromJson(underlayJson),
    );
  }
}

extension ArtworkDocumentJson on ArtworkDocument {
  /// Serializes the flat v1 document: metadata + geometry + optional underlay.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      ...artwork.toJson(),
    };
    final underlayRef = underlay;
    if (underlayRef != null) {
      json['underlay'] = underlayRef.toJson();
    }
    return json;
  }
}

/// Whether this document is a "discard-worthy" empty new piece for
/// auto-save skip (Phase Hγ): no geometry, no underlay, and still the
/// default title.
extension ArtworkDocumentBlank on ArtworkDocument {
  bool get isBlank {
    return artwork.polygons.isEmpty &&
        artwork.draftVertexIds.isEmpty &&
        artwork.vertices.isEmpty &&
        underlay == null &&
        artwork.title == kDefaultArtworkTitle;
  }
}
