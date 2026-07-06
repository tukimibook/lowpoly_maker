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
typedef PolygonVertexHit = ({PolygonShape polygon, String vertexId});

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
  /// - snaps onto an existing polygon's vertex (tap near an existing vertex,
  ///   with or without a draft already in progress) — this *only* makes the
  ///   new point share that exact vertex ID; it never closes the polygon by
  ///   itself, no matter how many points that completes, or
  /// - appends a brand new draft vertex at the tapped position.
  ///
  /// Sharing a corner (a vertex ID) and finishing a shape (closing it into a
  /// filled polygon) are deliberately two separate concerns: tying two
  /// shapes together at a point must never, by itself, decide that the
  /// shape being drawn is now finished. Closing only ever happens
  /// explicitly, either via the toolbar's "close" button or the "tap near
  /// own start" shortcut above, once the artist has placed every point they
  /// want.
  ///
  /// In every case where an existing vertex is involved, the new draft
  /// reuses that vertex's ID directly rather than creating a new point at a
  /// matching coordinate — see [findPolygonVertexNear] — so the shapes
  /// truly share that corner in the data model, not just visually. Returns
  /// the fill color of the polygon a new draft was started from, so the
  /// caller can sync the color picker to match it, or null otherwise.
  Color? handleDrawTap(Offset position, {required Color fillColor}) {
    final draftIds = state.draftVertexIds;

    final canAutoCloseToOwnStart =
        draftIds.length >= kMinPolygonVertices && !state.draftStartedFromExistingVertex;
    if (canAutoCloseToOwnStart) {
      final firstVertex = state.vertices[draftIds.first]!;
      final distanceToFirst = (firstVertex.position - position).distance;
      if (distanceToFirst <= kClosePolygonThreshold) {
        closePolygon(fillColor);
        return null;
      }
    }

    final hit = findPolygonVertexNear(position);
    if (hit != null) {
      if (draftIds.isEmpty) {
        startDraftFromExistingVertex(hit.vertexId);
        return hit.polygon.fillColor;
      }
      snapDraftEndToExistingVertex(hit.vertexId);
      return null;
    }

    _appendFreehandDraftVertex(position);
    return null;
  }

  /// Handles a tap while in [CanvasMode.eraser]: deletes the single nearest
  /// confirmed-polygon vertex to [position] (within [kVertexHitRadius]), if
  /// any. Does nothing when no vertex is close enough.
  void handleEraseTap(Offset position) {
    final hit = findPolygonVertexNear(position);
    if (hit == null) return;
    deletePolygonVertex(hit.polygon, hit.vertexId);
  }

  /// Finds the nearest vertex belonging to any *confirmed* polygon within
  /// [kVertexHitRadius] of [position], if any.
  ///
  /// Only [Artwork.polygons] are ever searched here — the polygon currently
  /// being drawn (`Artwork.draftVertexIds`) is never a candidate, even
  /// though its vertices also live in the same shared [Artwork.vertices]
  /// pool. This guarantees the shape in progress can never snap onto (or
  /// close against) one of its own, not-yet-confirmed points.
  PolygonVertexHit? findPolygonVertexNear(Offset position) {
    PolygonShape? closestPolygon;
    String? closestVertexId;
    var closestDistance = kVertexHitRadius;

    for (final polygon in state.polygons) {
      for (final vertexId in polygon.vertexIds) {
        final vertex = state.vertices[vertexId];
        if (vertex == null) continue;
        final distance = (vertex.position - position).distance;
        if (distance <= closestDistance) {
          closestDistance = distance;
          closestPolygon = polygon;
          closestVertexId = vertexId;
        }
      }
    }

    if (closestPolygon == null || closestVertexId == null) return null;
    return (polygon: closestPolygon, vertexId: closestVertexId);
  }

  /// Starts a brand new draft polygon whose first point *is*
  /// [existingVertexId] (the very same vertex, not a copy). The polygon it
  /// belongs to is left completely untouched — this only seeds a new,
  /// independent shape that happens to share a corner with it.
  ///
  /// Marks the draft as [Artwork.draftStartedFromExistingVertex] so the "tap
  /// near own start" auto-close shortcut is disabled for it — its own start
  /// point is a real, shared vertex that may need to be walked past on the
  /// way to wherever this shape actually finishes, so wandering back near
  /// it must not accidentally close the shape early (it must be closed
  /// explicitly instead; see [handleDrawTap]).
  void startDraftFromExistingVertex(String existingVertexId) {
    state = state.copyWith(
      draftVertexIds: [existingVertexId],
      draftStartedFromExistingVertex: true,
    );
  }

  /// Appends [existingVertexId] to the end of the in-progress draft,
  /// merging the end of the new line onto that exact vertex (the very same
  /// point, not a copy at a matching coordinate). The polygon
  /// [existingVertexId] already belongs to is left completely untouched.
  ///
  /// This purely shares a corner — it never closes the shape by itself.
  /// Sharing a vertex and finishing a shape are independent decisions; a
  /// polygon that starts on one shape and needs to touch several other
  /// shapes' corners along the way must be free to keep going after each
  /// snap instead of being forced shut the moment it reaches
  /// [kMinPolygonVertices] points. See [handleDrawTap] and [closePolygon].
  void snapDraftEndToExistingVertex(String existingVertexId) {
    state = state.copyWith(draftVertexIds: [...state.draftVertexIds, existingVertexId]);
  }

  /// Creates a brand new [Vertex] at [position], adds it to the shared pool,
  /// and appends its ID to the in-progress draft.
  void _appendFreehandDraftVertex(Offset position) {
    final vertex = Vertex(id: _uuid.v4(), position: position);
    final draftIds = state.draftVertexIds;
    state = state.copyWith(
      vertices: {...state.vertices, vertex.id: vertex},
      draftVertexIds: [...draftIds, vertex.id],
      // A plain tap that starts a fresh draft is never "from an existing
      // vertex"; otherwise keep whatever the draft already had.
      draftStartedFromExistingVertex: draftIds.isEmpty ? false : state.draftStartedFromExistingVertex,
    );
  }

  /// Deletes [vertexId] from [polygon]. If the polygon still has at least
  /// [kMinPolygonVertices] points afterwards, it remains a polygon with the
  /// point removed. Otherwise there aren't enough points left to form a
  /// shape, so it is dissolved and any remaining points are handed back to
  /// the draft so they are not lost. Either way, [vertexId] itself is
  /// pruned from the shared vertex pool once nothing references it anymore.
  void deletePolygonVertex(PolygonShape polygon, String vertexId) {
    final updatedVertexIds = polygon.vertexIds.where((id) => id != vertexId).toList();

    if (updatedVertexIds.length >= kMinPolygonVertices) {
      final updatedPolygons = [
        for (final p in state.polygons)
          if (p.id == polygon.id) p.copyWith(vertexIds: updatedVertexIds) else p,
      ];
      state = state.copyWith(
        polygons: updatedPolygons,
        vertices: _prune(
          state.vertices,
          vertexId,
          polygons: updatedPolygons,
          draftVertexIds: state.draftVertexIds,
        ),
      );
    } else {
      final remainingPolygons = state.polygons.where((p) => p.id != polygon.id).toList();
      state = state.copyWith(
        polygons: remainingPolygons,
        draftVertexIds: updatedVertexIds,
        draftStartedFromExistingVertex: false,
        vertices: _prune(
          state.vertices,
          vertexId,
          polygons: remainingPolygons,
          draftVertexIds: updatedVertexIds,
        ),
      );
    }
  }

  /// Confirms the current draft vertices as a new filled polygon.
  void closePolygon(Color fillColor) {
    if (state.draftVertexIds.length < kMinPolygonVertices) return;
    final polygon = PolygonShape(
      id: _uuid.v4(),
      vertexIds: state.draftVertexIds,
      fillColor: fillColor,
      strokeColor: defaultStrokeColor,
      strokeWidth: defaultStrokeWidth,
    );
    state = state.copyWith(
      polygons: [...state.polygons, polygon],
      draftVertexIds: const [],
      draftStartedFromExistingVertex: false,
    );
  }

  /// Removes the most recently placed draft vertex, pruning it from the
  /// shared pool if nothing else references it.
  void undoLastVertex() {
    final draftIds = state.draftVertexIds;
    if (draftIds.isEmpty) return;
    final removedId = draftIds.last;
    final updatedDraft = draftIds.sublist(0, draftIds.length - 1);
    state = state.copyWith(
      vertices: _prune(state.vertices, removedId, polygons: state.polygons, draftVertexIds: updatedDraft),
      draftVertexIds: updatedDraft,
      draftStartedFromExistingVertex: updatedDraft.isEmpty ? false : state.draftStartedFromExistingVertex,
    );
  }

  /// Clears the in-progress polygon without confirming it, pruning any
  /// draft-only vertices from the shared pool.
  void clearDraft() {
    final draftIds = state.draftVertexIds;
    if (draftIds.isEmpty) return;
    var vertices = state.vertices;
    for (final id in draftIds) {
      vertices = _prune(vertices, id, polygons: state.polygons, draftVertexIds: const []);
    }
    state = state.copyWith(
      vertices: vertices,
      draftVertexIds: const [],
      draftStartedFromExistingVertex: false,
    );
  }

  /// Removes every confirmed polygon and any in-progress draft, along with
  /// every vertex in the shared pool.
  void clearAll() {
    state = state.copyWith(
      vertices: const {},
      polygons: const [],
      draftVertexIds: const [],
      draftStartedFromExistingVertex: false,
    );
  }

  /// Returns [vertices] with [vertexId] removed, but only if it is no
  /// longer referenced by any confirmed [polygons] or by [draftVertexIds].
  /// Keeps the pool from accumulating orphaned points once their owning
  /// shape is undone, dissolved, or erased. Pure with respect to its
  /// arguments so callers can chain it across multiple removals in one go.
  Map<String, Vertex> _prune(
    Map<String, Vertex> vertices,
    String vertexId, {
    required List<PolygonShape> polygons,
    required List<String> draftVertexIds,
  }) {
    final stillReferenced =
        draftVertexIds.contains(vertexId) || polygons.any((p) => p.vertexIds.contains(vertexId));
    if (stillReferenced) return vertices;
    return {for (final entry in vertices.entries) if (entry.key != vertexId) entry.key: entry.value};
  }
}

final canvasProvider = StateNotifierProvider<CanvasNotifier, Artwork>((ref) {
  return CanvasNotifier();
});
