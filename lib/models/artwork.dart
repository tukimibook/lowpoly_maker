import 'dart:ui';

import 'polygon_shape.dart';
import 'vertex.dart';

/// The full state of a single artwork being edited: its confirmed polygons
/// plus the vertices of the polygon currently being drawn (not yet closed).
class Artwork {
  const Artwork({
    required this.id,
    required this.title,
    required this.canvasSize,
    this.polygons = const [],
    this.draftVertices = const [],
    this.draftStartedFromExistingVertex = false,
  });

  factory Artwork.empty({required String id, String title = '無題の作品'}) {
    return Artwork(id: id, title: title, canvasSize: Size.zero);
  }

  final String id;
  final String title;

  /// Size of the drawable area in world coordinates. Populated once the
  /// canvas widget is laid out.
  final Size canvasSize;
  final List<PolygonShape> polygons;
  final List<Vertex> draftVertices;

  /// Whether the in-progress [draftVertices] were seeded from an existing
  /// polygon's vertex (see `CanvasNotifier.startDraftFromExistingVertex`).
  /// When true, tapping back near the draft's own first point should NOT
  /// auto-close the shape — the shape can only be closed by snapping onto
  /// another existing vertex, so drawing a long path back toward the start
  /// area doesn't accidentally close it early.
  final bool draftStartedFromExistingVertex;

  Artwork copyWith({
    String? title,
    Size? canvasSize,
    List<PolygonShape>? polygons,
    List<Vertex>? draftVertices,
    bool? draftStartedFromExistingVertex,
  }) {
    return Artwork(
      id: id,
      title: title ?? this.title,
      canvasSize: canvasSize ?? this.canvasSize,
      polygons: polygons ?? this.polygons,
      draftVertices: draftVertices ?? this.draftVertices,
      draftStartedFromExistingVertex:
          draftStartedFromExistingVertex ?? this.draftStartedFromExistingVertex,
    );
  }
}
