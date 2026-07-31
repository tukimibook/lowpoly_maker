import 'package:freezed_annotation/freezed_annotation.dart';

import '../geometry/ring_collapse.dart';
import 'polygon_shape.dart';
import 'vertex.dart';

part 'artwork.freezed.dart';

/// Current `ArtworkDocument` JSON schema version. Owned by
/// [ArtworkDocument] on disk; kept here so geometry and document code share
/// one constant. Bump together with a migration step whenever a breaking
/// change is made to the persisted shape (Phase Hγ).
const int kArtworkSchemaVersion = 1;

/// Default [Artwork.title] for a brand-new, never-renamed piece — also the
/// sentinel [ArtworkDocumentBlank.isBlank] uses so a title-only edit is
/// treated as worth persisting (rename-ready; empty-canvas auto-save skip).
const String kDefaultArtworkTitle = 'Untitled';

/// The full state of a single artwork being edited.
///
/// Vertices are normalized into a single shared pool ([vertices]), keyed by
/// [Vertex.id]. Both [polygons] and the in-progress [draftVertexIds] only
/// ever reference vertices by ID — they never carry their own private copy
/// of a point's coordinates. This is what guarantees that two shapes which
/// share a corner (see `CanvasNotifier`'s vertex-snapping) are always
/// perfectly, structurally identical at that corner: there is only one
/// [Vertex] in [vertices] for it, referenced by every polygon that meets
/// there.
///
/// Deliberately holds **only** persisted geometry/identity data — every
/// field here is safe to snapshot verbatim in `CanvasNotifier`'s undo
/// stack. Document metadata (`schemaVersion`, `createdAt`, `updatedAt`) and
/// underlay live on [ArtworkDocument], outside this model. Device/session-
/// only state (canvas size, viewport zoom/pan) stays in its own providers.
///
/// Ring ID rules (asymmetric): each confirmed [polygons] ring must have no
/// duplicate vertex IDs (see [assertConfirmedRingIds]). [draftVertexIds] may
/// contain duplicates — e.g. a self-close snap `[S, …, S]` is valid.
@freezed
abstract class Artwork with _$Artwork {
  const factory Artwork({
    required String id,
    required String title,
    @Default(<String, Vertex>{}) Map<String, Vertex> vertices,
    @Default(<PolygonShape>[]) List<PolygonShape> polygons,
    @Default(<String>[]) List<String> draftVertexIds,
  }) = _Artwork;

  factory Artwork.empty({required String id, String title = kDefaultArtworkTitle}) {
    return Artwork(id: id, title: title);
  }

  /// Deserializes the geometry/identity fields of an `ArtworkDocument` v1
  /// payload (flat root). Ignores document-level keys such as
  /// `schemaVersion` / timestamps / `underlay`.
  ///
  /// [draftVertexIds] is included (Hγ decision, 2026-07-20): an in-progress,
  /// unclosed shape must survive an app kill + relaunch. Callers migrate
  /// `schemaVersion` *before* calling this when needed.
  factory Artwork.fromJson(Map<String, dynamic> json) {
    final verticesJson = json['vertices'] as Map<String, dynamic>;
    final polygonsJson = json['polygons'] as List<dynamic>;
    final draftVertexIdsJson = json['draftVertexIds'] as List<dynamic>? ?? const [];
    final polygons = polygonsJson
        .map((p) => PolygonShape.fromJson(p as Map<String, dynamic>))
        .toList();
    for (final polygon in polygons) {
      assertConfirmedRingIds(polygon.vertexIds);
    }
    return Artwork(
      id: json['id'] as String,
      title: json['title'] as String,
      vertices: verticesJson.map(
        (id, value) => MapEntry(id, Vertex.fromJson(id, value as Map<String, dynamic>)),
      ),
      polygons: polygons,
      draftVertexIds: draftVertexIdsJson.cast<String>(),
    );
  }
}

/// [Artwork.toJson] — an extension rather than a method in the class body:
/// freezed's generated `_Artwork` only *implements* [Artwork] (it doesn't
/// `extend` it), so a concrete method on the abstract class would compile
/// but never run for real instances.
extension ArtworkJson on Artwork {
  /// Serializes geometry/identity only. Document envelope fields
  /// (`schemaVersion`, timestamps, underlay) are owned by
  /// [ArtworkDocument.toJson].
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'vertices': vertices.map((id, vertex) => MapEntry(id, vertex.toJson())),
      'polygons': polygons.map((polygon) => polygon.toJson()).toList(),
      'draftVertexIds': draftVertexIds,
    };
  }
}
