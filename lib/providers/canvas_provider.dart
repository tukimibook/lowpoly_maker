import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/artwork.dart';
import '../models/canvas_mode.dart';
import '../models/polygon_shape.dart';
import '../models/vertex.dart';

const _uuid = Uuid();

/// Minimum number of points required before a shape can be closed into a
/// polygon.
const int kMinPolygonVertices = 3;

/// Tap distance (in world/logical pixels) within which tapping near the
/// first draft vertex auto-closes the polygon.
const double kClosePolygonThreshold = 24.0;

/// Tap distance (in world/logical pixels) within which tapping near an
/// existing polygon's vertex starts a brand new polygon from that point
/// (the existing polygon is left untouched).
const double kVertexHitRadius = 20.0;

/// Preset fill colors offered in Phase 1. A full color picker / palette
/// manager is introduced in a later phase.
const List<Color> kDefaultPolygonPalette = [
  Color(0xFFEF5350),
  Color(0xFF42A5F5),
  Color(0xFF66BB6A),
  Color(0xFFFFCA28),
  Color(0xFFAB47BC),
  Color(0xFF26A69A),
];

/// Currently selected fill color for the next polygon to be closed.
final selectedFillColorProvider = StateProvider<Color>((ref) {
  return kDefaultPolygonPalette.first;
});

/// Current canvas interaction mode (draw vs. eraser). Switching modes never
/// mutates artwork state by itself — it only changes how the next tap is
/// interpreted.
final canvasModeProvider = StateProvider<CanvasMode>((ref) {
  return CanvasMode.draw;
});

/// Identifies a specific vertex of a confirmed polygon, as returned by a
/// hit-test against the current artwork.
typedef PolygonVertexHit = ({PolygonShape polygon, int vertexIndex});

class CanvasNotifier extends StateNotifier<Artwork> {
  CanvasNotifier() : super(Artwork.empty(id: _uuid.v4()));

  static const Color defaultStrokeColor = Color(0xFF212121);
  static const double defaultStrokeWidth = 2.5;

  /// Records the rendered size of the canvas widget in world coordinates.
  void setCanvasSize(Size size) {
    if (state.canvasSize == size) return;
    state = state.copyWith(canvasSize: size);
  }

  /// Handles a tap while in [CanvasMode.draw]. Depending on where [position]
  /// lands, this either:
  /// - closes the in-progress polygon back to its own start point (tap near
  ///   its first draft vertex) — only when that draft was started from an
  ///   empty tap, not from an existing vertex (see
  ///   [Artwork.draftStartedFromExistingVertex]),
  /// - snaps onto an existing polygon's vertex and, if that completes at
  ///   least [kMinPolygonVertices] points, immediately closes the polygon
  ///   there (tap near an existing vertex while a draft is already in
  ///   progress),
  /// - starts a brand new polygon whose first point coincides with an
  ///   existing polygon's vertex, without altering that polygon in any way
  ///   (tap near an existing vertex while there is no draft in progress), or
  /// - appends a new draft vertex at the tapped position.
  ///
  /// In every case where an existing vertex is involved, that vertex's
  /// polygon is left completely untouched — only the new draft is snapped to
  /// its position. Returns the fill color of the polygon a new draft was
  /// started from, so the caller can sync the color picker to match it, or
  /// null otherwise.
  Color? handleDrawTap(Offset position, {required Color fillColor}) {
    final draft = state.draftVertices;

    final canAutoCloseToOwnStart =
        draft.length >= kMinPolygonVertices && !state.draftStartedFromExistingVertex;
    if (canAutoCloseToOwnStart) {
      final distanceToFirst = (draft.first.position - position).distance;
      if (distanceToFirst <= kClosePolygonThreshold) {
        closePolygon(fillColor);
        return null;
      }
    }

    final hit = findPolygonVertexNear(position);
    if (hit != null) {
      final existingVertex = hit.polygon.vertices[hit.vertexIndex];
      if (draft.isEmpty) {
        startDraftFromExistingVertex(existingVertex);
        return hit.polygon.fillColor;
      }
      snapDraftEndToExistingVertex(existingVertex, fillColor);
      return null;
    }

    final vertex = Vertex(id: _uuid.v4(), position: position);
    state = state.copyWith(
      draftVertices: [...draft, vertex],
      // A plain tap that starts a fresh draft is never "from an existing
      // vertex"; otherwise keep whatever the draft already had.
      draftStartedFromExistingVertex: draft.isEmpty ? false : state.draftStartedFromExistingVertex,
    );
    return null;
  }

  /// Handles a tap while in [CanvasMode.eraser]: deletes the single nearest
  /// confirmed-polygon vertex to [position] (within [kVertexHitRadius]), if
  /// any. Does nothing when no vertex is close enough.
  void handleEraseTap(Offset position) {
    final hit = findPolygonVertexNear(position);
    if (hit == null) return;
    deletePolygonVertex(hit.polygon, hit.vertexIndex);
  }

  /// Finds the nearest vertex among all confirmed polygons within
  /// [kVertexHitRadius] of [position], if any.
  PolygonVertexHit? findPolygonVertexNear(Offset position) {
    PolygonShape? closestPolygon;
    var closestIndex = -1;
    var closestDistance = kVertexHitRadius;

    for (final polygon in state.polygons) {
      for (var i = 0; i < polygon.vertices.length; i++) {
        final distance = (polygon.vertices[i].position - position).distance;
        if (distance <= closestDistance) {
          closestDistance = distance;
          closestPolygon = polygon;
          closestIndex = i;
        }
      }
    }

    if (closestPolygon == null) return null;
    return (polygon: closestPolygon, vertexIndex: closestIndex);
  }

  /// Starts a brand new draft polygon whose first point sits at the same
  /// position as [existingVertex]. The polygon [existingVertex] belongs to
  /// is left completely untouched — this only seeds a new, independent
  /// shape that happens to share a corner with it.
  ///
  /// Marks the draft as [Artwork.draftStartedFromExistingVertex] so it can
  /// only be closed by docking onto another existing vertex, not by
  /// wandering back near its own start point.
  void startDraftFromExistingVertex(Vertex existingVertex) {
    final startVertex = Vertex(id: _uuid.v4(), position: existingVertex.position);
    state = state.copyWith(
      draftVertices: [startVertex],
      draftStartedFromExistingVertex: true,
    );
  }

  /// Appends a new draft vertex snapped to [existingVertex]'s position,
  /// merging the end of the in-progress line onto that point. If this
  /// completes at least [kMinPolygonVertices] points, the shape is closed
  /// into a polygon immediately using [fillColor]; otherwise the snapped
  /// point is simply added and drawing continues. The polygon that
  /// [existingVertex] belongs to is left completely untouched.
  void snapDraftEndToExistingVertex(Vertex existingVertex, Color fillColor) {
    final snappedVertex = Vertex(id: _uuid.v4(), position: existingVertex.position);
    final updatedDraft = [...state.draftVertices, snappedVertex];
    state = state.copyWith(draftVertices: updatedDraft);

    if (updatedDraft.length >= kMinPolygonVertices) {
      closePolygon(fillColor);
    }
  }

  /// Deletes a single vertex (at [vertexIndex]) from [polygon]. If the
  /// polygon still has at least [kMinPolygonVertices] points afterwards, it
  /// remains a polygon with the point removed. Otherwise there aren't enough
  /// points left to form a shape, so it is dissolved and any remaining
  /// points are handed back to the draft so they are not lost.
  void deletePolygonVertex(PolygonShape polygon, int vertexIndex) {
    final updatedVertices = List<Vertex>.of(polygon.vertices)..removeAt(vertexIndex);

    if (updatedVertices.length >= kMinPolygonVertices) {
      final updatedPolygons = [
        for (final p in state.polygons)
          if (p.id == polygon.id) p.copyWith(vertices: updatedVertices) else p,
      ];
      state = state.copyWith(polygons: updatedPolygons);
    } else {
      final remainingPolygons = state.polygons.where((p) => p.id != polygon.id).toList();
      state = state.copyWith(
        polygons: remainingPolygons,
        draftVertices: updatedVertices,
        draftStartedFromExistingVertex: false,
      );
    }
  }

  /// Confirms the current draft vertices as a new filled polygon.
  void closePolygon(Color fillColor) {
    if (state.draftVertices.length < kMinPolygonVertices) return;
    final polygon = PolygonShape(
      id: _uuid.v4(),
      vertices: state.draftVertices,
      fillColor: fillColor,
      strokeColor: defaultStrokeColor,
      strokeWidth: defaultStrokeWidth,
    );
    state = state.copyWith(
      polygons: [...state.polygons, polygon],
      draftVertices: const [],
      draftStartedFromExistingVertex: false,
    );
  }

  /// Removes the most recently placed draft vertex.
  void undoLastVertex() {
    if (state.draftVertices.isEmpty) return;
    final updated = List<Vertex>.of(state.draftVertices)..removeLast();
    state = state.copyWith(
      draftVertices: updated,
      draftStartedFromExistingVertex: updated.isEmpty ? false : state.draftStartedFromExistingVertex,
    );
  }

  /// Clears the in-progress polygon without confirming it.
  void clearDraft() {
    if (state.draftVertices.isEmpty) return;
    state = state.copyWith(draftVertices: const [], draftStartedFromExistingVertex: false);
  }

  /// Removes every confirmed polygon and any in-progress draft.
  void clearAll() {
    state = state.copyWith(
      polygons: const [],
      draftVertices: const [],
      draftStartedFromExistingVertex: false,
    );
  }
}

final canvasProvider = StateNotifierProvider<CanvasNotifier, Artwork>((ref) {
  return CanvasNotifier();
});
