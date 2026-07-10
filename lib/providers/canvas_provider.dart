import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../geometry/nearest_point.dart';
import '../models/artwork.dart';
import '../models/canvas_mode.dart';
import '../models/polygon_shape.dart';
import '../models/vertex.dart';

const _uuid = Uuid();

/// Minimum number of points required before a shape can be closed into a
/// polygon.
const int kMinPolygonVertices = 3;

/// Tap distance (in world/logical pixels) within which tapping near an
/// existing polygon's vertex snaps onto it, reusing that exact vertex so the
/// two shapes truly share that corner in the data model ("weld"), not just
/// visually (see [CanvasNotifier.findPolygonVertexNear]).
///
/// Sized to roughly a fingertip (~48 logical px / Material's 48dp touch
/// target). When canvas zoom/pan is added later (Phase B), this should be
/// treated as a *screen* tolerance and divided by the current zoom scale
/// before hit-testing in world space.
const double kVertexHitRadius = 48.0;

/// Perpendicular distance (in world/logical pixels) within which an
/// existing confirmed vertex sitting near a freshly drawn segment gets
/// folded into the draft automatically. This lets an artist connect two
/// distant corners with a single tap and have every vertex the line
/// happens to pass close to (e.g. another shape's edge sitting between
/// them) absorbed into the new draft automatically, instead of requiring
/// a separate, precise tap on each one. See [CanvasNotifier.handleDrawTap].
const double kLineAbsorptionTolerance = 15.0;

/// Maximum time between two taps for the second one to be reinterpreted
/// as a "close the shape now" gesture (a pseudo double-tap) instead of an
/// independent point. See [CanvasNotifier.handleDrawTap].
const Duration kDoubleTapMaxInterval = Duration(milliseconds: 300);

/// Maximum distance (in world/logical pixels) between two taps for the
/// second one to be reinterpreted as a "close the shape now" gesture.
/// Combined with [kDoubleTapMaxInterval], this distinguishes a genuine
/// double-tap (two taps landing in roughly the same spot) from fast,
/// deliberate single taps placed in different spots while sketching.
const double kDoubleTapMaxDistance = 20.0;

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

  /// Time and position of the most recent tap handled by [handleDrawTap],
  /// used to detect a "pseudo double-tap" (see [_isPseudoDoubleTap]).
  /// Deliberately kept as plain notifier fields rather than [Artwork] state:
  /// this is transient gesture bookkeeping, not artwork data, so it must
  /// never be persisted, undone, or redone.
  DateTime? _lastTapAt;
  Offset? _lastTapPosition;

  /// How many draft vertices the most recent single tap appended. Used to
  /// discard just the throwaway first tap of a double-tap when self-closing
  /// on the draft's own start (see [_tryCloseAtVertex]).
  int _lastTapInsertedCount = 0;

  /// Records the rendered size of the canvas widget in world coordinates.
  void setCanvasSize(Size size) {
    if (state.canvasSize == size) return;
    state = state.copyWith(canvasSize: size);
  }

  /// Handles a tap while in [CanvasMode.draw].
  ///
  /// A single tap *never* closes a shape — it only ever grows the draft, in
  /// one of two ways:
  /// - snaps onto an existing polygon's vertex (tap near an existing
  ///   vertex, with or without a draft already in progress) — this makes
  ///   the new point reuse that exact vertex ID rather than creating a new
  ///   point at a matching coordinate, so the shapes truly share that
  ///   corner in the data model ("weld"), not just visually (see
  ///   [findPolygonVertexNear]), or
  /// - appends a brand new draft vertex at the tapped position.
  ///
  /// Closing a shape into a filled polygon is a separate, deliberate action.
  /// It happens on a "pseudo double-tap" (a second tap landing within
  /// [kDoubleTapMaxInterval] and [kDoubleTapMaxDistance] of the previous one,
  /// see [_isPseudoDoubleTap]) **only when that tap lands on a vertex that
  /// yields a proper loop** — the draft's own start, or another polygon's
  /// corner (see [_tryCloseAtVertex]). It can also be closed explicitly via
  /// the toolbar's "close" button (wired directly to [closePolygon]).
  ///
  /// A double-tap anywhere else (empty canvas, or next to a mid-draft point)
  /// is deliberately *not* a close: it just leaves the two tapped points,
  /// which the artist can undo. This keeps a fast free-hand stroke — or a
  /// path that sketches straight over its own start and keeps going — from
  /// snapping shut by accident; closing only ever happens on a real corner.
  ///
  /// On a plain (non-double-tap) tap, once the new point's own position is
  /// resolved (snapped onto an existing vertex or placed freehand), any
  /// existing vertex that the *new segment* back to the previous draft
  /// point happens to pass close by gets absorbed into the draft too — see
  /// [_absorbVerticesAlongNewSegment].
  ///
  /// Returns the fill color of the polygon a new draft was started from,
  /// so the caller can sync the color picker to match it, or null
  /// otherwise.
  Color? handleDrawTap(Offset position, {required Color fillColor}) {
    final now = DateTime.now();
    if (_isPseudoDoubleTap(position, now) &&
        _tryCloseAtVertex(position, fillColor)) {
      return null;
    }

    final countBefore = state.draftVertexIds.length;
    final result = _handleSingleDrawTap(position, fillColor: fillColor);
    _lastTapInsertedCount = state.draftVertexIds.length - countBefore;
    _lastTapAt = now;
    _lastTapPosition = position;
    return result;
  }

  /// Tries to close the current draft in response to a double-tap at
  /// [position], but only when that tap lands on a vertex that yields a
  /// proper loop. Returns true when it closed; false (so the caller treats
  /// the tap as an ordinary point) otherwise.
  ///
  /// Two valid targets:
  /// - **another polygon's vertex** → connect-close. The first tap of the
  ///   double-tap already welded the draft's end onto it via the single-tap
  ///   path, so by now that vertex *is* the draft's end (and, being part of
  ///   the draft, is excluded from [findPolygonVertexNear]). It is therefore
  ///   detected directly: the tap sits on the draft's end and that end is a
  ///   corner of a confirmed polygon. The shape simply closes (following the
  ///   shared edge inside [closePolygon] when start and end share a polygon).
  /// - **the draft's own start** → self-close into a loop. Drawing-time
  ///   snapping excludes the draft's own points, so the first tap of the
  ///   double-tap dropped a throwaway point next to the start; it is removed
  ///   first so the shape closes as a clean loop of the points actually
  ///   drawn. (Removing just the first tap's own contribution — with no
  ///   re-search — avoids the old bug where a close could snap back toward
  ///   the start.)
  bool _tryCloseAtVertex(Offset position, Color fillColor) {
    final draftIds = state.draftVertexIds;
    if (draftIds.isEmpty) return false;

    final endPosition = state.vertices[draftIds.last]!.position;
    if ((position - endPosition).distance <= kVertexHitRadius &&
        _isConfirmedPolygonVertex(draftIds.last)) {
      if (draftIds.length < kMinPolygonVertices) return false;
      closePolygon(fillColor);
      return true;
    }

    final startPosition = state.vertices[draftIds.first]!.position;
    if ((position - startPosition).distance <= kVertexHitRadius) {
      final strayCount = _lastTapInsertedCount;
      if (draftIds.length - strayCount < kMinPolygonVertices) return false;
      for (var i = 0; i < strayCount; i++) {
        undoLastVertex();
      }
      closePolygon(fillColor);
      return true;
    }

    return false;
  }

  /// Whether [vertexId] is a corner of any confirmed polygon (i.e. a shared/
  /// welded vertex), as opposed to a draft-only freehand point.
  bool _isConfirmedPolygonVertex(String vertexId) {
    return state.polygons.any((p) => p.vertexIds.contains(vertexId));
  }

  /// The per-tap logic behind [handleDrawTap], run whenever the tap was
  /// *not* a pseudo double-tap.
  Color? _handleSingleDrawTap(Offset position, {required Color fillColor}) {
    final draftIds = state.draftVertexIds;

    final hit = findPolygonVertexNear(position);
    if (hit != null) {
      if (draftIds.isEmpty) {
        startDraftFromExistingVertex(hit.vertexId);
        return hit.polygon.fillColor;
      }
      _insertAbsorbedVertices(
        state.vertices[draftIds.last]!.position,
        state.vertices[hit.vertexId]!.position,
        excludeVertexId: hit.vertexId,
      );
      snapDraftEndToExistingVertex(hit.vertexId);
      return null;
    }

    if (draftIds.isNotEmpty) {
      _insertAbsorbedVertices(
        state.vertices[draftIds.last]!.position,
        position,
      );
    }
    _appendFreehandDraftVertex(position);
    return null;
  }

  /// True when [position]/[now] land close enough — in both time and
  /// space — to the previous tap handled by [handleDrawTap] to be
  /// reinterpreted as the second half of a double-tap (the "close the
  /// shape now" gesture).
  ///
  /// Flutter's built-in double-tap recognizer would need to delay *every*
  /// single tap while it waits to see whether a second one follows, which
  /// would make the whole drawing experience feel sluggish. Instead, every
  /// tap is handled immediately by [handleDrawTap] as normal, and a second
  /// one close enough to the first is treated as a close.
  bool _isPseudoDoubleTap(Offset position, DateTime now) {
    final lastAt = _lastTapAt;
    final lastPosition = _lastTapPosition;
    if (lastAt == null || lastPosition == null) return false;
    return now.difference(lastAt) <= kDoubleTapMaxInterval &&
        (position - lastPosition).distance <= kDoubleTapMaxDistance;
  }

  /// Handles a tap while in [CanvasMode.eraser]: deletes the single nearest
  /// confirmed-polygon vertex to [position] (within [kVertexHitRadius]), if
  /// any. Does nothing when no vertex is close enough.
  void handleEraseTap(Offset position) {
    _resetPendingTap();
    final hit = findPolygonVertexNear(position);
    if (hit == null) return;
    deletePolygonVertex(hit.polygon, hit.vertexId);
  }

  /// Finds existing confirmed-polygon vertices that lie almost exactly on
  /// the new segment from [start] to [end] — within
  /// [kLineAbsorptionTolerance] of perpendicular distance from the line,
  /// and strictly between its two ends — ordered by how far along the
  /// segment they fall. [excludeVertexId] additionally excludes the vertex
  /// [end] itself resolves to, if any (it's the segment's own endpoint,
  /// not one to absorb *into* the middle of it).
  ///
  /// Vertices already part of the current draft (including its own start)
  /// are always excluded too, since they're already accounted for and
  /// re-inserting one mid-draft would create a self-intersecting loop
  /// instead of a straight pass-through.
  ///
  /// This lets an artist connect two distant corners with a single tap and
  /// have every vertex the line happens to pass close to (e.g. another
  /// shape's edge sitting between them) get folded into the new draft
  /// automatically, instead of requiring a separate tap on each one. See
  /// [handleDrawTap].
  List<String> _absorbVerticesAlongNewSegment(
    Offset start,
    Offset end, {
    String? excludeVertexId,
  }) {
    final segment = end - start;
    final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
    if (lengthSquared == 0) return const [];

    final alreadyInDraft = state.draftVertexIds.toSet();
    final candidates = <(double t, String vertexId)>[];

    for (final polygon in state.polygons) {
      for (final vertexId in polygon.vertexIds) {
        if (vertexId == excludeVertexId || alreadyInDraft.contains(vertexId)) {
          continue;
        }
        final vertex = state.vertices[vertexId];
        if (vertex == null) continue;

        final toVertex = vertex.position - start;
        final t =
            (toVertex.dx * segment.dx + toVertex.dy * segment.dy) /
            lengthSquared;
        if (t <= 0 || t >= 1) continue; // strictly between the two endpoints

        final projection = start + segment * t;
        if ((vertex.position - projection).distance <=
            kLineAbsorptionTolerance) {
          candidates.add((t, vertexId));
        }
      }
    }

    candidates.sort((a, b) => a.$1.compareTo(b.$1));
    final seen = <String>{};
    return [
      for (final candidate in candidates)
        if (seen.add(candidate.$2)) candidate.$2,
    ];
  }

  /// Splices every vertex [_absorbVerticesAlongNewSegment] finds between
  /// [start] and [end] into the draft, in order, ahead of whatever the
  /// caller appends next.
  void _insertAbsorbedVertices(
    Offset start,
    Offset end, {
    String? excludeVertexId,
  }) {
    final absorbed = _absorbVerticesAlongNewSegment(
      start,
      end,
      excludeVertexId: excludeVertexId,
    );
    for (final vertexId in absorbed) {
      snapDraftEndToExistingVertex(vertexId);
    }
  }

  /// Finds the nearest vertex belonging to any *confirmed* polygon within
  /// [kVertexHitRadius] of [position], if any.
  ///
  /// [Artwork.polygons] are searched, but any vertex ID already part of the
  /// in-progress draft (`Artwork.draftVertexIds`) is always excluded, even
  /// if it also happens to belong to a confirmed polygon — which happens
  /// whenever the draft was started from (or has since snapped onto) an
  /// existing vertex, since that same vertex lives on in both places at
  /// once in the shared [Artwork.vertices] pool. This guarantees the shape
  /// in progress can never snap onto one of its own points,
  /// confirmed-polygon-owned or not, while it's still being drawn. Closing
  /// (see [handleDrawTap]) then simply finishes the shape on whatever the
  /// last tap already placed — it never runs its own separate snap search.
  ///
  /// This is the one place in the notifier that cares about *which
  /// polygon* a matched vertex belongs to (needed to pick up that
  /// polygon's fill color); the actual nearest-neighbor search itself is
  /// delegated to the plain-geometry [findNearestPoint].
  PolygonVertexHit? findPolygonVertexNear(Offset position) {
    final draftIds = state.draftVertexIds.toSet();
    final owningPolygon = <String, PolygonShape>{};
    final candidates = <PointCandidate<String>>[];
    for (final polygon in state.polygons) {
      for (final vertexId in polygon.vertexIds) {
        if (draftIds.contains(vertexId)) continue;
        final vertex = state.vertices[vertexId];
        if (vertex == null) continue;
        owningPolygon[vertexId] = polygon;
        candidates.add((vertexId, vertex.position));
      }
    }

    final nearest = findNearestPoint(
      position,
      candidates,
      maxDistance: kVertexHitRadius,
    );
    if (nearest == null) return null;
    return (polygon: owningPolygon[nearest.$1]!, vertexId: nearest.$1);
  }

  /// Starts a brand new draft polygon whose first point *is*
  /// [existingVertexId] (the very same vertex, not a copy). The polygon it
  /// belongs to is left completely untouched — this only seeds a new,
  /// independent shape that happens to share a corner with it.
  void startDraftFromExistingVertex(String existingVertexId) {
    state = state.copyWith(draftVertexIds: [existingVertexId]);
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
    state = state.copyWith(
      draftVertexIds: [...state.draftVertexIds, existingVertexId],
    );
  }

  /// Creates a brand new [Vertex] at [position], adds it to the shared pool,
  /// and appends its ID to the in-progress draft.
  void _appendFreehandDraftVertex(Offset position) {
    final vertex = Vertex(id: _uuid.v4(), position: position);
    final draftIds = state.draftVertexIds;
    state = state.copyWith(
      vertices: {...state.vertices, vertex.id: vertex},
      draftVertexIds: [...draftIds, vertex.id],
    );
  }

  /// Deletes [vertexId] from [polygon]. If the polygon still has at least
  /// [kMinPolygonVertices] points afterwards, it remains a polygon with the
  /// point removed. Otherwise there aren't enough points left to form a
  /// shape, so it is dissolved and any remaining points are handed back to
  /// the draft so they are not lost. Either way, [vertexId] itself is
  /// pruned from the shared vertex pool once nothing references it anymore.
  void deletePolygonVertex(PolygonShape polygon, String vertexId) {
    final updatedVertexIds = polygon.vertexIds
        .where((id) => id != vertexId)
        .toList();

    if (updatedVertexIds.length >= kMinPolygonVertices) {
      final updatedPolygons = [
        for (final p in state.polygons)
          if (p.id == polygon.id)
            p.copyWith(vertexIds: updatedVertexIds)
          else
            p,
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
      final remainingPolygons = state.polygons
          .where((p) => p.id != polygon.id)
          .toList();
      state = state.copyWith(
        polygons: remainingPolygons,
        draftVertexIds: updatedVertexIds,
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
  ///
  /// When the draft's first and last points both belong to the *same*
  /// existing polygon, the shape is closed by following that polygon's own
  /// boundary between them (see [_sharedBoundaryClosure]) instead of cutting a
  /// straight edge from the last point back to the first. This lets an artist
  /// draw a free-hand arc from one corner of an existing shape to another and
  /// have the new shape tile seamlessly against it — sharing the whole edge in
  /// between, not just the two endpoints.
  void closePolygon(Color fillColor) {
    _resetPendingTap();
    final draftIds = state.draftVertexIds;
    if (draftIds.length < kMinPolygonVertices) return;
    final vertexIds = [
      ...draftIds,
      ..._sharedBoundaryClosure(draftIds.first, draftIds.last),
    ];
    final polygon = PolygonShape(
      id: _uuid.v4(),
      vertexIds: vertexIds,
      fillColor: fillColor,
      strokeColor: defaultStrokeColor,
      strokeWidth: defaultStrokeWidth,
    );
    state = state.copyWith(
      polygons: [...state.polygons, polygon],
      draftVertexIds: const [],
    );
  }

  /// When [startId] and [endId] are both vertices of the *same* confirmed
  /// polygon, returns that polygon's own boundary vertices lying strictly
  /// between [endId] and [startId] — walking whichever of the two arcs around
  /// the ring is geometrically shorter — so the draft can close by following
  /// that shared edge rather than cutting straight back to its start.
  ///
  /// The returned IDs are appended after the draft's last point, so the closing
  /// path runs `last -> boundary... -> first`. They are the polygon's *own*
  /// vertex IDs (reused, not copied), so the two shapes genuinely share that
  /// edge in the [Artwork.vertices] pool ("weld"). Any vertex already present
  /// in the draft is skipped to avoid duplicating a corner.
  ///
  /// Returns an empty list when the two points don't share a polygon (or are
  /// the same point, or are adjacent with nothing in between); the draft then
  /// closes with a plain straight edge exactly as before.
  List<String> _sharedBoundaryClosure(String startId, String endId) {
    if (startId == endId) return const [];
    final draftSet = state.draftVertexIds.toSet();
    for (final polygon in state.polygons) {
      final ids = polygon.vertexIds;
      final iStart = ids.indexOf(startId);
      final iEnd = ids.indexOf(endId);
      if (iStart < 0 || iEnd < 0) continue;

      final forward = _arcVertices(ids, iEnd, iStart, forward: true);
      final backward = _arcVertices(ids, iEnd, iStart, forward: false);
      final chosen = _pathLength(forward) <= _pathLength(backward)
          ? forward
          : backward;

      // `chosen` runs [endId, ...intermediates..., startId]; keep only the
      // in-between vertices that aren't already in the draft.
      return [
        for (final id in chosen.sublist(1, chosen.length - 1))
          if (!draftSet.contains(id)) id,
      ];
    }
    return const [];
  }

  /// Walks the closed ring [ids] from index [from] to index [to] (inclusive of
  /// both) in the given direction, returning the vertex IDs visited in order.
  List<String> _arcVertices(
    List<String> ids,
    int from,
    int to, {
    required bool forward,
  }) {
    final n = ids.length;
    final result = <String>[ids[from]];
    var i = from;
    while (i != to) {
      i = forward ? (i + 1) % n : (i - 1 + n) % n;
      result.add(ids[i]);
    }
    return result;
  }

  /// Total length of the polyline through [vertexIds], in world pixels.
  double _pathLength(List<String> vertexIds) {
    var total = 0.0;
    for (var i = 0; i + 1 < vertexIds.length; i++) {
      final a = state.vertices[vertexIds[i]];
      final b = state.vertices[vertexIds[i + 1]];
      if (a == null || b == null) continue;
      total += (b.position - a.position).distance;
    }
    return total;
  }

  /// Removes the most recently placed draft vertex, pruning it from the
  /// shared pool if nothing else references it.
  void undoLastVertex() {
    _resetPendingTap();
    final draftIds = state.draftVertexIds;
    if (draftIds.isEmpty) return;
    final removedId = draftIds.last;
    final updatedDraft = draftIds.sublist(0, draftIds.length - 1);
    state = state.copyWith(
      vertices: _prune(
        state.vertices,
        removedId,
        polygons: state.polygons,
        draftVertexIds: updatedDraft,
      ),
      draftVertexIds: updatedDraft,
    );
  }

  /// Clears the in-progress polygon without confirming it, pruning any
  /// draft-only vertices from the shared pool.
  void clearDraft() {
    _resetPendingTap();
    final draftIds = state.draftVertexIds;
    if (draftIds.isEmpty) return;
    var vertices = state.vertices;
    for (final id in draftIds) {
      vertices = _prune(
        vertices,
        id,
        polygons: state.polygons,
        draftVertexIds: const [],
      );
    }
    state = state.copyWith(vertices: vertices, draftVertexIds: const []);
  }

  /// Removes every confirmed polygon and any in-progress draft, along with
  /// every vertex in the shared pool.
  void clearAll() {
    _resetPendingTap();
    state = state.copyWith(
      vertices: const {},
      polygons: const [],
      draftVertexIds: const [],
    );
  }

  /// Clears the pending-tap bookkeeping used by [_isPseudoDoubleTap].
  /// Called by every draft-mutating method other than [handleDrawTap]
  /// itself, so an explicit action (undo, clear, an external "close"
  /// button, an eraser tap, ...) always breaks the chain — a later tap
  /// must never be misread as the second half of a double-tap referring
  /// to a point that, from the artist's perspective, no longer exists in
  /// the same context.
  void _resetPendingTap() {
    _lastTapAt = null;
    _lastTapPosition = null;
    _lastTapInsertedCount = 0;
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
        draftVertexIds.contains(vertexId) ||
        polygons.any((p) => p.vertexIds.contains(vertexId));
    if (stillReferenced) return vertices;
    return {
      for (final entry in vertices.entries)
        if (entry.key != vertexId) entry.key: entry.value,
    };
  }
}

final canvasProvider = StateNotifierProvider<CanvasNotifier, Artwork>((ref) {
  return CanvasNotifier();
});
