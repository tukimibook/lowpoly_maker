import 'dart:ui';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'polygon_shape.dart';
import 'vertex.dart';

part 'artwork.freezed.dart';

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
@freezed
abstract class Artwork with _$Artwork {
  const factory Artwork({
    required String id,
    required String title,
    required Size canvasSize,
    @Default(<String, Vertex>{}) Map<String, Vertex> vertices,
    @Default(<PolygonShape>[]) List<PolygonShape> polygons,
    @Default(<String>[]) List<String> draftVertexIds,
    @Default(false) bool draftStartedFromExistingVertex,
  }) = _Artwork;

  factory Artwork.empty({required String id, String title = '無題の作品'}) {
    return Artwork(id: id, title: title, canvasSize: Size.zero);
  }
}
