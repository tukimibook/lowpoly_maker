import 'package:freezed_annotation/freezed_annotation.dart';

import 'polygon_shape.dart';
import 'vertex.dart';

part 'artwork.freezed.dart';

/// Current `ArtworkDocument` JSON schema version produced by [Artwork.toJson]
/// and understood by [Artwork.fromJson]. Bump this — together with a
/// migration step wherever a document is loaded — whenever a breaking
/// change is made to the persisted shape; never repurpose an existing field
/// in place without one (Phase Hγ, U1 / `.cursor/plans/plan_phase_H_gamma.md`).
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
/// Deliberately holds **only** persisted geometry/document data — every
/// field here is both a) part of [toJson]'s `ArtworkDocument` (Phase Hγ) and
/// b) safe to snapshot verbatim in `CanvasNotifier`'s undo stack. Anything
/// that is device/session-only (canvas size, viewport zoom/pan, underlay
/// placement — see `CanvasSizeController`, `ViewportController`,
/// `UnderlayLayoutController`) is deliberately kept in its own provider
/// *outside* this model instead, so it can never leak into either the saved
/// file or an undo snapshot.
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

  /// Deserializes the `ArtworkDocument` v1 schema produced by [toJson].
  ///
  /// [draftVertexIds] is included (Hγ decision, 2026-07-20): an in-progress,
  /// unclosed shape must survive an app kill + relaunch just like confirmed
  /// polygons do, or auto-save/resume would silently discard whatever the
  /// artist was mid-way through drawing. Callers are responsible for any
  /// `schemaVersion` migration *before* calling this — it always reads the
  /// current (v1) field layout.
  factory Artwork.fromJson(Map<String, dynamic> json) {
    final verticesJson = json['vertices'] as Map<String, dynamic>;
    final polygonsJson = json['polygons'] as List<dynamic>;
    final draftVertexIdsJson = json['draftVertexIds'] as List<dynamic>? ?? const [];
    return Artwork(
      id: json['id'] as String,
      title: json['title'] as String,
      vertices: verticesJson.map(
        (id, value) => MapEntry(id, Vertex.fromJson(id, value as Map<String, dynamic>)),
      ),
      polygons: polygonsJson
          .map((p) => PolygonShape.fromJson(p as Map<String, dynamic>))
          .toList(),
      draftVertexIds: draftVertexIdsJson.cast<String>(),
    );
  }
}

/// [Artwork.toJson] — an extension rather than a method in the class body:
/// freezed's generated `_Artwork` only *implements* [Artwork] (it doesn't
/// `extend` it, to support freezed's sealed-union pattern in general), so a
/// concrete method written directly in the `abstract class` above would
/// compile but never actually run for real instances — an extension is the
/// pattern freezed itself recommends for this.
extension ArtworkJson on Artwork {
  /// Serializes this artwork's geometry into the `ArtworkDocument` v1
  /// schema (Phase Hγ). Deliberately excludes anything that isn't geometry
  /// — there is nothing to exclude on this model any more (`canvasSize` was
  /// removed outright, see `CanvasSizeController`) — and never embeds
  /// underlay placement (`UnderlayLayout`), which the save service
  /// serializes and composes separately.
  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': kArtworkSchemaVersion,
      'id': id,
      'title': title,
      'vertices': vertices.map((id, vertex) => MapEntry(id, vertex.toJson())),
      'polygons': polygons.map((polygon) => polygon.toJson()).toList(),
      'draftVertexIds': draftVertexIds,
    };
  }
}
