import 'dart:ui';

import 'package:collection/collection.dart';
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

/// Tap distance (in world/logical pixels *at zoom scale 1*) within which
/// tapping near an existing polygon's vertex snaps onto it, reusing that
/// exact vertex so the two shapes truly share that corner in the data model
/// ("weld"), not just visually (see [CanvasNotifier.findPolygonVertexNear]).
///
/// Sized to roughly a fingertip (~48 logical px / Material's 48dp touch
/// target). This is a *screen* tolerance — finger precision doesn't change
/// with zoom — so every method below that hit-tests against it takes an
/// explicit `hitRadius` parameter (defaulting to this constant) rather than
/// using it directly. Callers that know the current viewport scale (e.g.
/// `PolygonCanvas`) pass `kVertexHitRadius / transform.scale` so the
/// on-screen tolerance stays constant regardless of zoom.
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

  /// Snapshots of [Artwork] before each user-visible mutation, newest last.
  /// Transient gesture state ([_lastTapAt], [dragPreviewProvider], etc.) is
  /// never stored here — only committed artwork changes are undoable.
  final List<Artwork> _undoStack = [];

  /// Whether at least one committed artwork change can be reversed via [undo].
  bool get canUndo => _undoStack.isNotEmpty;

  /// Pushes the current [state] onto [_undoStack] so the next mutation can
  /// be reversed. Called immediately before every user-visible artwork
  /// change (point placement, close, erase, clear, …) but never for
  /// layout-only updates ([setCanvasSize]) or internal bookkeeping such as
  /// [_removeLastDraftVertex] during double-tap self-close.
  void _recordUndo() {
    _undoStack.add(state);
  }

  /// Reverses the most recent committed artwork change.
  ///
  /// Restores the [Artwork] snapshot pushed by [_recordUndo] before that
  /// operation — including closing a polygon (undoing a close brings back
  /// the open draft), erasing a vertex, or placing a point. Returns false
  /// when there is nothing to undo; true when a snapshot was restored.
  bool undo() {
    if (_undoStack.isEmpty) return false;
    _resetPendingTap();
    state = _undoStack.removeLast();
    return true;
  }

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
  ///
  /// [position] must already be in world coordinates (see
  /// `CoordinateTransform.screenToWorld`). [hitRadius] is the vertex-snap
  /// tolerance in that same world space — pass `kVertexHitRadius /
  /// transform.scale` so the tolerance stays a constant *screen* distance
  /// regardless of zoom; it defaults to [kVertexHitRadius] unscaled for
  /// callers (e.g. tests) that don't have a viewport transform.
  Color? handleDrawTap(
    Offset position, {
    required Color fillColor,
    double hitRadius = kVertexHitRadius,
  }) {
    final now = DateTime.now();
    if (_isPseudoDoubleTap(position, now) &&
        _tryCloseAtVertex(position, fillColor, hitRadius: hitRadius)) {
      return null;
    }

    final countBefore = state.draftVertexIds.length;
    _recordUndo();
    final result = _handleSingleDrawTap(
      position,
      fillColor: fillColor,
      hitRadius: hitRadius,
    );
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
  ///   shared edge inside [closePolygon] when start and end share a polygon)
  ///   — unless doing so right now would silently cut a straight, unwelded
  ///   edge between two unrelated existing polygons (see
  ///   [_wouldCloseWithUnweldedGap]); in that case this returns false so the
  ///   tap is kept as an ordinary point instead of surprising the artist
  ///   with a seam they didn't ask for. The toolbar's explicit "close"
  ///   button (calling [closePolygon] directly) always still works.
  /// - **the draft's own start** → self-close into a loop. Drawing-time
  ///   snapping excludes the draft's own points, so the first tap of the
  ///   double-tap dropped a throwaway point next to the start; it is removed
  ///   first so the shape closes as a clean loop of the points actually
  ///   drawn. (Removing just the first tap's own contribution — with no
  ///   re-search — avoids the old bug where a close could snap back toward
  ///   the start.) Closing onto the draft's own start is never a "gap" —
  ///   there's nothing else to weld to — so no such check applies here.
  bool _tryCloseAtVertex(
    Offset position,
    Color fillColor, {
    required double hitRadius,
  }) {
    final draftIds = state.draftVertexIds;
    if (draftIds.isEmpty) return false;

    final endPosition = state.vertices[draftIds.last]!.position;
    if ((position - endPosition).distance <= hitRadius &&
        _isConfirmedPolygonVertex(draftIds.last)) {
      if (draftIds.length < kMinPolygonVertices) return false;
      if (_wouldCloseWithUnweldedGap(draftIds.first, draftIds.last)) {
        return false;
      }
      closePolygon(fillColor);
      return true;
    }

    final startPosition = state.vertices[draftIds.first]!.position;
    if ((position - startPosition).distance <= hitRadius) {
      final strayCount = _lastTapInsertedCount;
      if (draftIds.length - strayCount < kMinPolygonVertices) return false;
      for (var i = 0; i < strayCount; i++) {
        _removeLastDraftVertex();
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
  Color? _handleSingleDrawTap(
    Offset position, {
    required Color fillColor,
    required double hitRadius,
  }) {
    final draftIds = state.draftVertexIds;

    final hit = findPolygonVertexNear(position, hitRadius: hitRadius);
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
  /// confirmed-polygon vertex to [position] (within [hitRadius]), if any.
  /// Does nothing when no vertex is close enough.
  ///
  /// [position] must already be in world coordinates; [hitRadius] follows
  /// the same screen-tolerance convention as [handleDrawTap].
  void handleEraseTap(Offset position, {double hitRadius = kVertexHitRadius}) {
    _resetPendingTap();
    final hit = findPolygonVertexNear(position, hitRadius: hitRadius);
    if (hit == null) return;
    _recordUndo();
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
  /// [handleDrawTap]. [_closingEdgeVertices] reuses this same welding for
  /// the implicit closing edge, so it never skips a vertex sitting on it
  /// just because that edge wasn't drawn by an explicit tap.
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
  ///
  /// [hitRadius] follows the same screen-tolerance convention as
  /// [handleDrawTap]: it defaults to unscaled [kVertexHitRadius], but
  /// callers with a viewport transform should pass it divided by the
  /// current zoom scale.
  PolygonVertexHit? findPolygonVertexNear(
    Offset position, {
    double hitRadius = kVertexHitRadius,
  }) {
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
      maxDistance: hitRadius,
    );
    if (nearest == null) return null;
    return (polygon: owningPolygon[nearest.$1]!, vertexId: nearest.$1);
  }

  /// Finds the nearest vertex referenced by the current artwork — confirmed
  /// [Artwork.polygons] *and* the in-progress [Artwork.draftVertexIds] —
  /// within [hitRadius] of [position], if any.
  ///
  /// Unlike [findPolygonVertexNear] (draw-mode magnet snap onto *confirmed*
  /// corners only, excluding the draft), this is the edit-mode hit-test:
  /// every corner the artist can see and might want to move is a candidate.
  /// The nearest-neighbor search itself is still delegated to
  /// [findNearestPoint].
  String? findVertexNear(
    Offset position, {
    double hitRadius = kVertexHitRadius,
  }) {
    final referencedIds = <String>{...state.draftVertexIds};
    for (final polygon in state.polygons) {
      referencedIds.addAll(polygon.vertexIds);
    }

    final candidates = <PointCandidate<String>>[];
    for (final vertexId in referencedIds) {
      final vertex = state.vertices[vertexId];
      if (vertex == null) continue;
      candidates.add((vertexId, vertex.position));
    }

    final nearest = findNearestPoint(
      position,
      candidates,
      maxDistance: hitRadius,
    );
    return nearest?.$1;
  }

  /// Commits a new world position for [vertexId] in the shared vertex pool.
  ///
  /// Every polygon and draft segment that references this ID — including
  /// welded corners shared across multiple shapes — follows automatically
  /// because they all read from the same [Vertex] entry. Records one undo
  /// entry when the position actually changes.
  void moveVertex(String vertexId, Offset newPosition) {
    final vertex = state.vertices[vertexId];
    if (vertex == null) return;
    if (vertex.position == newPosition) return;

    _recordUndo();
    state = state.copyWith(
      vertices: {
        ...state.vertices,
        vertexId: vertex.copyWith(position: newPosition),
      },
    );
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
  /// The closing edge — from the draft's last point back to its first — is
  /// resolved by one rule that applies no matter which polygons (if any)
  /// the two ends happen to belong to (see [_closingEdgeVertices]): follow
  /// the shortest existing chain of polygon boundaries connecting them —
  /// whether that's one polygon's own two arcs or a route hopping across
  /// several polygons that happen to share welded vertices — when there is
  /// one, otherwise weld onto any existing vertex that happens to sit on
  /// the straight line between them. Either way the shape tiles seamlessly
  /// against whatever it touches, instead of the specific start/end
  /// combination changing how (or whether) it welds.
  void closePolygon(Color fillColor) {
    _resetPendingTap();
    final draftIds = state.draftVertexIds;
    if (draftIds.length < kMinPolygonVertices) return;
    _recordUndo();
    final vertexIds = [
      ...draftIds,
      ..._closingEdgeVertices(draftIds.first, draftIds.last),
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

  /// Resolves what, if anything, belongs *between* the draft's last point
  /// ([endId]) and its first ([startId]) when closing — the single rule
  /// behind [closePolygon]:
  /// - If there is any chain of existing polygons' own edges connecting
  ///   them — whether that's the two arcs of one polygon they're both
  ///   corners of, or a longer route hopping across several polygons that
  ///   happen to share welded vertices along the way — follow the
  ///   geometrically shortest such chain (see [_sharedBoundaryClosure])
  ///   rather than cutting a straight edge. This lets an artist draw a
  ///   free-hand arc from one shape's corner to another's and have the new
  ///   shape tile seamlessly against everything already welded in
  ///   between, not just the two endpoints it directly touches.
  /// - Otherwise (no such chain exists) fall back to
  ///   [_absorbVerticesAlongNewSegment], exactly the same welding every
  ///   other, explicitly-drawn segment already gets. Without this
  ///   fallback, the implicit closing edge was the one segment in the
  ///   whole drawing model that could silently cut straight across
  ///   (instead of weld to) another shape's corner sitting in its path,
  ///   leaving a gap the artist never asked for.
  ///
  /// The returned IDs are appended after the draft's last point, so the
  /// closing path runs `last -> ...returned... -> first` either way.
  List<String> _closingEdgeVertices(String startId, String endId) {
    final sharedBoundary = _sharedBoundaryClosure(startId, endId);
    if (sharedBoundary.isNotEmpty) return sharedBoundary;

    final startPosition = state.vertices[startId]!.position;
    final endPosition = state.vertices[endId]!.position;
    return _absorbVerticesAlongNewSegment(endPosition, startPosition);
  }

  /// True when closing the draft from [startId] to [endId] right now, via
  /// [_closingEdgeVertices], would silently cut a straight, unwelded edge
  /// between two *different* existing polygons that share no boundary or
  /// welded chain — i.e. would create a seam the artist likely didn't
  /// intend, rather than follow a real shared boundary or weld onto
  /// something sitting in between.
  ///
  /// Used by [_tryCloseAtVertex] to keep the implicit double-tap gesture
  /// "safe": it should only ever close when the result is unsurprising —
  /// a fresh loop back to the draft's own start, a shared or chained
  /// boundary, or a weld onto a vertex sitting on the closing line. When
  /// either end isn't a confirmed polygon vertex at all, there is nothing
  /// to unexpectedly cut across, so this returns false. The toolbar's
  /// explicit "close" button (which calls [closePolygon] directly,
  /// bypassing this check) remains available to force a plain straight
  /// edge when the artist deliberately wants one even though nothing
  /// connects the two ends.
  bool _wouldCloseWithUnweldedGap(String startId, String endId) {
    if (startId == endId) return false;
    if (!_isConfirmedPolygonVertex(startId) ||
        !_isConfirmedPolygonVertex(endId)) {
      return false;
    }
    if (_shortestBoundaryPath(endId, startId) != null) return false;

    final startPosition = state.vertices[startId]!.position;
    final endPosition = state.vertices[endId]!.position;
    return _absorbVerticesAlongNewSegment(endPosition, startPosition).isEmpty;
  }

  /// When [startId] and [endId] are connected by some chain of existing
  /// polygons' own edges (see [_shortestBoundaryPath]), returns the
  /// vertices strictly between them along the geometrically shortest such
  /// chain, so the draft can close by following it rather than cutting
  /// straight back to its start.
  ///
  /// The returned IDs are appended after the draft's last point, so the
  /// closing path runs `last -> boundary... -> first`. They are reused
  /// vertex IDs (not copies), so every polygon along the chain genuinely
  /// shares that edge in the [Artwork.vertices] pool ("weld").
  ///
  /// Returns an empty list when no such chain exists (or the two points are
  /// the same, or directly adjacent with nothing in between);
  /// [_closingEdgeVertices] then falls back to absorbing any existing
  /// vertex that sits on the straight closing line instead of a shared
  /// boundary.
  List<String> _sharedBoundaryClosure(String startId, String endId) {
    final path = _shortestBoundaryPath(endId, startId);
    if (path == null || path.length <= 2) return const [];
    return path.sublist(1, path.length - 1);
  }

  /// Geometrically shortest path from [fromId] to [toId] that travels only
  /// along existing confirmed polygons' own edges (every vertex connected
  /// to its immediate ring neighbors in each polygon it's a corner of),
  /// weighted by on-screen distance — or `null` when no such path exists.
  ///
  /// This is what lets a new draft tile seamlessly against whatever it
  /// touches: when [fromId] and [toId] are both corners of the *same*
  /// polygon, this naturally reduces to whichever of that polygon's two
  /// boundary arcs between them is shorter (the graph has no other edges
  /// to offer there). When they belong to two *different* polygons that
  /// happen to share a welded vertex somewhere — directly, or via a chain
  /// of further shared vertices — this finds the route through that chain
  /// instead, so drawing a shape from one existing corner to another never
  /// cuts straight across a boundary that's actually already there.
  ///
  /// Vertices belonging to the *current* draft are never used as a
  /// mid-path hop (only [toId] itself — the draft's own other end — is
  /// allowed as the destination): they're already accounted for elsewhere
  /// in the draft, so routing through one would duplicate a corner into a
  /// self-intersecting loop instead of a clean weld.
  List<String>? _shortestBoundaryPath(String fromId, String toId) {
    if (fromId == toId) return [fromId];
    final graph = _polygonEdgeGraph();
    if (!graph.containsKey(fromId) || !graph.containsKey(toId)) return null;

    final blockedHops = state.draftVertexIds.toSet()..remove(toId);
    final best = <String, double>{fromId: 0};
    final previous = <String, String>{};
    final settled = <String>{};
    final queue = PriorityQueue<(double, String)>(
      (a, b) => a.$1.compareTo(b.$1),
    );
    queue.add((0.0, fromId));

    while (queue.isNotEmpty) {
      final (dist, current) = queue.removeFirst();
      if (!settled.add(current)) continue;
      if (current == toId) break;
      for (final (neighborId, weight)
          in graph[current] ?? const <(String, double)>[]) {
        if (blockedHops.contains(neighborId)) continue;
        final candidate = dist + weight;
        if (candidate < (best[neighborId] ?? double.infinity)) {
          best[neighborId] = candidate;
          previous[neighborId] = current;
          queue.add((candidate, neighborId));
        }
      }
    }

    if (!settled.contains(toId)) return null;
    final path = <String>[toId];
    var node = toId;
    while (node != fromId) {
      final prev = previous[node];
      if (prev == null) return null;
      path.add(prev);
      node = prev;
    }
    return path.reversed.toList();
  }

  /// Builds an undirected graph over every confirmed polygon's own ring of
  /// edges (each vertex linked to its immediate neighbors within each
  /// polygon it belongs to), weighted by on-screen distance between them.
  /// Used by [_shortestBoundaryPath] to route a closing edge along
  /// whatever boundary is already there instead of cutting straight
  /// through it.
  Map<String, List<(String, double)>> _polygonEdgeGraph() {
    final graph = <String, List<(String, double)>>{};
    void addEdge(String a, String b) {
      final va = state.vertices[a];
      final vb = state.vertices[b];
      if (va == null || vb == null) return;
      final weight = (vb.position - va.position).distance;
      (graph[a] ??= []).add((b, weight));
      (graph[b] ??= []).add((a, weight));
    }

    for (final polygon in state.polygons) {
      final ids = polygon.vertexIds;
      for (var i = 0; i < ids.length; i++) {
        addEdge(ids[i], ids[(i + 1) % ids.length]);
      }
    }
    return graph;
  }

  /// Removes the most recently placed draft vertex without recording an undo
  /// entry. Used internally when double-tap self-close discards the
  /// throwaway first tap of the pair before [closePolygon] records a single
  /// undo for the close itself.
  void _removeLastDraftVertex() {
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
    _recordUndo();
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
    if (state.polygons.isEmpty && state.draftVertexIds.isEmpty) return;
    _recordUndo();
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
