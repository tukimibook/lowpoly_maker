import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../geometry/boundary_closure.dart';
import '../geometry/closing_safety.dart';
import '../geometry/edge_midpoint.dart';
import '../geometry/line_absorption.dart';
import '../geometry/nearest_point.dart';
import '../geometry/polygon_hit_test.dart';
import '../geometry/ring_collapse.dart';
import '../geometry/vertex_hit_test.dart';
import '../models/artwork.dart';
import '../models/canvas_mode.dart';
import '../models/draw_mode.dart';
import '../models/polygon_shape.dart';
import '../models/vertex.dart';
import '../services/tessellation_service.dart';

const _uuid = Uuid();

/// Minimum number of points required before a shape can be closed into a
/// polygon.
const int kMinPolygonVertices = 3;

/// Outcome of [CanvasNotifier.closePolygon].
enum ClosePolygonResult {
  /// Draft was closed into a confirmed polygon.
  closed,

  /// Proposed ring would self-intersect or skewer existing geometry; draft
  /// is left unchanged.
  rejectedUnsafeClosingEdge,

  /// Fewer than [kMinPolygonVertices] draft points — nothing to close.
  tooFewVertices,
}

/// User-facing copy when [ClosePolygonResult.rejectedUnsafeClosingEdge].
const String kClosePolygonRejectedMessage =
    'Cannot close shape (edges cross or pierce)';


/// Tap distance (in world/logical pixels *at zoom scale 1*) within which
/// tapping near an existing polygon's vertex snaps onto it, reusing that
/// exact vertex so the two shapes truly share that corner in the data model
/// ("weld"), not just visually (see [CanvasNotifier.findPolygonVertexNear]).
///
/// Sized to roughly a fingertip (~30 logical px — tightened from Material's
/// 48dp touch target after real-device UX tuning). This is a *screen*
/// tolerance — finger precision doesn't change with zoom — so every method
/// below that hit-tests against it takes an explicit `hitRadius` parameter
/// (defaulting to this constant) rather than using it directly. Callers that
/// know the current viewport scale (e.g. `PolygonCanvas`) pass
/// `kVertexHitRadius / transform.scale` so the on-screen tolerance stays
/// constant regardless of zoom.
const double kVertexHitRadius = 30.0;

/// Perpendicular distance (in world/logical pixels) within which an
/// existing confirmed vertex sitting near a freshly drawn segment gets
/// folded into the draft automatically. This lets an artist connect two
/// distant corners with a single tap and have every vertex the line
/// happens to pass close to (e.g. another shape's edge sitting between
/// them) absorbed into the new draft automatically, instead of requiring
/// a separate, precise tap on each one. See [CanvasNotifier.handleDrawTap].
const double kLineAbsorptionTolerance = 10.0;

/// Fixed world-coordinate distance between two consecutive vertices
/// [generateTracePoints] generates along a なぞりモード ("trace mode")
/// stroke (Phase F, `.cursor/plans/plan_phase_F.md`). Unlike
/// [kVertexHitRadius] et al., this is deliberately *not* a screen
/// tolerance — callers must pass it straight through, unscaled by the
/// viewport transform, so a stroke always produces the same vertex
/// density in world space regardless of zoom. Scaling this by
/// `1 / transform.scale` (as an earlier revision did) made a stroke drawn
/// zoomed-in resample far more densely in world space than one drawn at
/// 1:1, so resetting the viewport back to 1:1 afterward left visibly
/// over-dense clusters of vertices. This also keeps the constant a
/// straightforward default for a future user-facing spacing slider, whose
/// value is itself a plain world-space distance.
const double kTraceVertexSpacing = 50.0;

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

/// Maximum number of committed [Artwork] snapshots kept in [_undoStack].
/// Once exceeded, the oldest entry is dropped so undo history doesn't grow
/// without bound — relevant once later phases (e.g. Phase G's bulk
/// tessellation output, or a long Phase F trace) can push many commits, or
/// a single commit containing thousands of vertices, in one session.
/// Redo and cross-session persistence of this history are out of scope
/// here (see Phase H+). → 検討メモ（2026-07-13 追記続き2）参照。
const int kUndoStackLimit = 100;

/// Draft vertices that must not be magnet-snap targets.
/// The in-progress shape's start remains eligible so self-close can weld.
/// Note: After a start snap ([S,...,S]), the start ID enters the skip(1) exclusion,
/// which may allow snapping to other nearby vertices if drawn further without closing.
Set<String> draftVertexSnapExclusions(List<String> draftVertexIds) =>
    draftVertexIds.skip(1).toSet();

/// Preset fill colors offered in Phase 1. A full color picker / palette
/// manager is introduced in a later phase.
const List<Color> kDefaultPolygonPalette = [
  Color(0xFF783F33),
  Color(0xFF8C6239),
  Color(0xFF4A533E),
  Color(0xFF2D4255),
  Color(0xFF5E5A55),
  Color(0xFF3B2F2F),
  Color(0xFF7A6A53),
  Color(0xFF4C6271),
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

/// Sub-mode of [CanvasMode.draw] — tap-to-place vs. なぞり (trace). Only
/// meaningful while [canvasModeProvider] is [CanvasMode.draw]; switching
/// away from draw mode (see `editor_toolbar.dart`'s `selectMode`) leaves
/// this untouched so the artist's choice survives a round trip through
/// eraser/edit mode and back.
final drawModeProvider = StateProvider<DrawMode>((ref) {
  return DrawMode.tap;
});

/// Identifies a specific vertex of a confirmed polygon, as returned by a
/// hit-test against the current artwork.
typedef PolygonVertexHit = ({PolygonShape polygon, String vertexId});

class CanvasNotifier extends StateNotifier<Artwork> {
  CanvasNotifier({VertexHitTest<String>? vertexHitTest})
    : _vertexHitTest = vertexHitTest ?? LinearVertexHitTest<String>(),
      super(Artwork.empty(id: _uuid.v4()));

  static const Color defaultStrokeColor = Color(0xFF212121);
  static const double defaultStrokeWidth = 1.5;

  /// Backing search structure for [findPolygonVertexNear]/[findVertexNear].
  /// Defaults to the plain O(n) linear scan ([LinearVertexHitTest]);
  /// injectable so a future spatial index can replace it — and so tests can
  /// substitute a fake — without touching either call site. See plan #10.
  final VertexHitTest<String> _vertexHitTest;

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
  /// internal bookkeeping such as [_removeLastDraftVertex] during
  /// double-tap self-close. Layout-only state (canvas size, viewport,
  /// underlay placement) never even reaches here — it lives in its own
  /// provider outside [Artwork] entirely (see `CanvasSizeController`,
  /// `ViewportController`, `UnderlayLayoutController`), so [state] itself
  /// is always pure geometry/document data (Phase Hγ, #9).
  ///
  /// Caps the stack at [kUndoStackLimit], dropping the oldest snapshot once
  /// exceeded, so a long session can't grow this list without bound.
  void _recordUndo() {
    _undoStack.add(state);
    if (_undoStack.length > kUndoStackLimit) {
      _undoStack.removeAt(0);
    }
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
  /// [_insertAbsorbedVertices] / [findVerticesAlongSegment].
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
  /// [doubleTapMaxDistance] and [lineAbsorptionTolerance] follow the exact
  /// same screen-tolerance convention, for [_isPseudoDoubleTap] and the
  /// line-absorption search (see [_insertAbsorbedVertices]/
  /// [closingEdgeVertices]) respectively — Phase Hβ's screen-px
  /// unification (`.cursor/plans/plan_phase_H_beta.md`, 着手前チェックリス
  /// ト #1): before this, both were compared directly against
  /// world-space distances, so they silently shrank/grew on screen once a
  /// pinch-zoom gesture existed.
  Color? handleDrawTap(
    Offset position, {
    required Color fillColor,
    double hitRadius = kVertexHitRadius,
    double doubleTapMaxDistance = kDoubleTapMaxDistance,
    double lineAbsorptionTolerance = kLineAbsorptionTolerance,
  }) {
    // Clear any prior close outcome so UI (e.g. commitDrawDrag's SnackBar)
    // only reacts to a close attempted during *this* tap — a sticky
    // rejectedUnsafeClosingEdge previously re-toasted on every later point.
    lastClosePolygonResult = null;

    final now = DateTime.now();
    if (_isPseudoDoubleTap(position, now, maxDistance: doubleTapMaxDistance) &&
        _tryCloseAtVertex(
          position,
          fillColor,
          hitRadius: hitRadius,
          lineAbsorptionTolerance: lineAbsorptionTolerance,
        )) {
      return null;
    }

    final countBefore = state.draftVertexIds.length;
    _recordUndo();
    final result = _handleSingleDrawTap(
      position,
      fillColor: fillColor,
      hitRadius: hitRadius,
      lineAbsorptionTolerance: lineAbsorptionTolerance,
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
  /// Two valid targets (never mid-draft vertices or unrelated corners):
  /// - **the draft's end, when it is already a confirmed polygon vertex**
  ///   → connect-close (the first tap of the double-tap welded the end
  ///   onto that corner via the single-tap path).
  /// - **the draft's own start** → self-close into a loop (throwaway first
  ///   tap of the pair is stripped first).
  ///
  /// When *both* are within [hitRadius], the nearer tap-to-vertex distance
  /// wins — connect-close is no longer unconditionally preferred over
  /// self-close (dense shared-boundary drawings previously closed onto a
  /// nearby welded end even when the artist was aiming at the start).
  /// Equal distances prefer the start (self-close).
  ///
  /// Connect-close still refuses [wouldCloseWithUnweldedGap]; if that
  /// blocks and the start is also in range, self-close is tried next.
  /// The toolbar's explicit "close" button (calling [closePolygon]
  /// directly) is unchanged.
  bool _tryCloseAtVertex(
    Offset position,
    Color fillColor, {
    required double hitRadius,
    required double lineAbsorptionTolerance,
  }) {
    final draftIds = state.draftVertexIds;
    if (draftIds.isEmpty) return false;

    final endPosition = state.vertices[draftIds.last]!.position;
    final endDistance = (position - endPosition).distance;
    final endEligible =
        endDistance <= hitRadius && _isConfirmedPolygonVertex(draftIds.last);

    final startPosition = state.vertices[draftIds.first]!.position;
    final startDistance = (position - startPosition).distance;
    final startEligible = startDistance <= hitRadius;

    // Prefer the nearer eligible candidate; on a tie, prefer self-close.
    final preferStart = startEligible &&
        (!endEligible || startDistance <= endDistance);
    final preferEnd = endEligible && !preferStart;

    if (preferEnd) {
      if (draftIds.length < kMinPolygonVertices) return false;
      if (!wouldCloseWithUnweldedGap(
        draftIds.first,
        draftIds.last,
        polygons: state.polygons,
        vertices: state.vertices,
        draftVertexIds: draftIds,
        lineAbsorptionTolerance: lineAbsorptionTolerance,
      )) {
        closePolygon(fillColor, lineAbsorptionTolerance: lineAbsorptionTolerance);
        return true;
      }
      // End was nearer but connect-close is unsafe — fall back to
      // self-close when the start is also in range.
      if (!startEligible) return false;
      // fall through to self-close
    }

    if (preferStart || (endEligible && startEligible)) {
      // preferStart, or end-was-preferred but gap-blocked with start eligible.
      final strayCount = _lastTapInsertedCount;
      if (draftIds.length - strayCount < kMinPolygonVertices) return false;
      for (var i = 0; i < strayCount; i++) {
        _removeLastDraftVertex();
      }
      closePolygon(fillColor, lineAbsorptionTolerance: lineAbsorptionTolerance);
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
    required double lineAbsorptionTolerance,
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
        tolerance: lineAbsorptionTolerance,
        excludeVertexId: hit.vertexId,
      );
      snapDraftEndToExistingVertex(hit.vertexId);
      return null;
    }

    if (draftIds.isNotEmpty) {
      _insertAbsorbedVertices(
        state.vertices[draftIds.last]!.position,
        position,
        tolerance: lineAbsorptionTolerance,
      );
    }
    _appendFreehandDraftVertex(position);
    return null;
  }

  /// Batch-commits an entire なぞりモード ("trace mode") stroke — a whole
  /// list of already-resampled world-coordinate points (see
  /// `generateTracePoints`) — as a *single* [_recordUndo] entry and a
  /// *single* [state] update, appending them to the in-progress draft in
  /// order (Phase F, `.cursor/plans/plan_phase_F.md`).
  ///
  /// Each point follows the exact same per-point rule
  /// [_handleSingleDrawTap] applies to a lone tap — snap onto a nearby
  /// existing polygon vertex (welding the draft onto it, absorbing
  /// whatever sits on the segment leading to it, same as
  /// [_insertAbsorbedVertices]), or otherwise place a brand new freehand
  /// vertex — just applied [points.length] times over local mutable
  /// copies of [Artwork.vertices]/[Artwork.draftVertexIds] rather than
  /// committing to [state] after every single one. This is what keeps a
  /// stroke of, say, 50 resampled points to exactly one [Artwork]
  /// rebuild/deep-equality pass and one undo entry instead of 50 of each.
  ///
  /// Deliberately bypasses [_isPseudoDoubleTap]/[_tryCloseAtVertex]
  /// entirely (via [_resetPendingTap]) — a trace stroke never implicitly
  /// closes a shape no matter where it ends or how quickly a later one
  /// follows; closing stays the explicit, separate action it already is
  /// for a drawn-by-tap draft ([closePolygon], normally wired to the
  /// toolbar's "閉じる" button). It also never creates a confirmed
  /// [PolygonShape] by itself — v1 only ever grows the draft, so an
  /// already-established shape stays reachable via the same "閉じる"
  /// button regardless of whether tap or trace grew it.
  ///
  /// No-op when [points] is empty (so no undo entry is recorded for an
  /// aborted/degenerate stroke). [hitRadius]/[lineAbsorptionTolerance]
  /// follow the same screen-tolerance convention as [handleDrawTap]'s
  /// parameters of the same name.
  void commitTraceStroke(
    List<Offset> points, {
    double hitRadius = kVertexHitRadius,
    double lineAbsorptionTolerance = kLineAbsorptionTolerance,
  }) {
    if (points.isEmpty) return;
    _resetPendingTap();
    _recordUndo();

    var vertices = state.vertices;
    var draftIds = state.draftVertexIds;

    void absorbAlong(Offset start, Offset end, {String? excludeVertexId}) {
      final absorbed = findVerticesAlongSegment(
        start,
        end,
        vertices: vertices,
        polygons: state.polygons,
        draftVertexIds: draftIds.toSet(),
        tolerance: lineAbsorptionTolerance,
        excludeVertexId: excludeVertexId,
      );
      if (absorbed.isNotEmpty) {
        draftIds = [...draftIds, ...absorbed];
      }
    }

    for (final point in points) {
      final hit = _findPolygonVertexNearIn(
        vertices,
        draftVertexSnapExclusions(draftIds),
        point,
        hitRadius: hitRadius,
      );
      if (hit != null) {
        if (draftIds.isEmpty) {
          draftIds = [hit.vertexId];
        } else {
          absorbAlong(
            vertices[draftIds.last]!.position,
            vertices[hit.vertexId]!.position,
            excludeVertexId: hit.vertexId,
          );
          draftIds = [...draftIds, hit.vertexId];
        }
        continue;
      }

      if (draftIds.isNotEmpty) {
        absorbAlong(vertices[draftIds.last]!.position, point);
      }
      final vertex = Vertex(id: _uuid.v4(), position: point);
      vertices = {...vertices, vertex.id: vertex};
      draftIds = [...draftIds, vertex.id];
    }

    state = state.copyWith(vertices: vertices, draftVertexIds: draftIds);
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
  bool _isPseudoDoubleTap(
    Offset position,
    DateTime now, {
    required double maxDistance,
  }) {
    final lastAt = _lastTapAt;
    final lastPosition = _lastTapPosition;
    if (lastAt == null || lastPosition == null) return false;
    return now.difference(lastAt) <= kDoubleTapMaxInterval &&
        (position - lastPosition).distance <= maxDistance;
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

  /// Splices every vertex [findVerticesAlongSegment] finds between [start]
  /// and [end] into the draft, in order, ahead of whatever the caller
  /// appends next. [excludeVertexId] excludes the vertex [end] itself
  /// resolves to, if any (it's the segment's own endpoint, not one to
  /// absorb *into* the middle of it).
  void _insertAbsorbedVertices(
    Offset start,
    Offset end, {
    String? excludeVertexId,
    double tolerance = kLineAbsorptionTolerance,
  }) {
    final absorbed = findVerticesAlongSegment(
      start,
      end,
      vertices: state.vertices,
      polygons: state.polygons,
      draftVertexIds: state.draftVertexIds.toSet(),
      tolerance: tolerance,
      excludeVertexId: excludeVertexId,
    );
    for (final vertexId in absorbed) {
      snapDraftEndToExistingVertex(vertexId);
    }
  }

  /// Finds the nearest vertex belonging to any *confirmed* polygon within
  /// [kVertexHitRadius] of [position], if any.
  ///
  /// [Artwork.polygons] are searched. Mid-draft vertex IDs
  /// ([draftVertexSnapExclusions] — everything after the draft's start) are
  /// excluded even when they also belong to a confirmed polygon, so the
  /// in-progress shape does not remagnet onto its own intermediate welds.
  /// The draft's **start** stays eligible: when it is a shared confirmed
  /// corner, tapping it can weld the draft closed for a subsequent
  /// self-close (see [handleDrawTap] / [_tryCloseAtVertex]). Freehand-only
  /// starts are not candidates here (they are not on any confirmed
  /// polygon). Closing itself never runs a separate snap search — it
  /// finishes on whatever the last tap already placed.
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
    return _findPolygonVertexNearIn(
      state.vertices,
      draftVertexSnapExclusions(state.draftVertexIds),
      position,
      hitRadius: hitRadius,
    );
  }

  /// The actual search behind [findPolygonVertexNear], parameterized over
  /// an explicit [vertices] pool and [excludedIds] set rather than always
  /// reading them from [state] — so [commitTraceStroke] can run this same
  /// search repeatedly, once per resampled trace point, against a *local*
  /// snapshot that grows as the batch progresses, without ever touching
  /// [state] itself until the whole stroke is done. [state.polygons]
  /// itself is passed through unchanged either way, since a trace stroke
  /// never creates a confirmed polygon mid-batch (see that method's doc).
  PolygonVertexHit? _findPolygonVertexNearIn(
    Map<String, Vertex> vertices,
    Set<String> excludedIds,
    Offset position, {
    required double hitRadius,
  }) {
    final owningPolygon = <String, PolygonShape>{};
    final candidates = <PointCandidate<String>>[];
    for (final polygon in state.polygons) {
      for (final vertexId in polygon.vertexIds) {
        if (excludedIds.contains(vertexId)) continue;
        final vertex = vertices[vertexId];
        if (vertex == null) continue;
        owningPolygon[vertexId] = polygon;
        candidates.add((vertexId, vertex.position));
      }
    }

    _vertexHitTest.rebuild(candidates);
    final nearest = _vertexHitTest.nearest(position, maxDistance: hitRadius);
    if (nearest == null) return null;
    return (polygon: owningPolygon[nearest.$1]!, vertexId: nearest.$1);
  }

  /// Finds the nearest vertex referenced by the current artwork — confirmed
  /// [Artwork.polygons] *and* the in-progress [Artwork.draftVertexIds] —
  /// within [hitRadius] of [position], if any.
  ///
  /// Unlike [findPolygonVertexNear] (draw-mode magnet snap onto *confirmed*
  /// corners, with mid-draft IDs excluded via [draftVertexSnapExclusions]),
  /// this is the edit-mode hit-test:
  /// every corner the artist can see and might want to move is a candidate.
  /// The nearest-neighbor search itself is still delegated to
  /// [findNearestPoint].
  ///
  /// [preferredVertexId] is forwarded to [findNearestPoint]'s own
  /// `preferredId` — pass whichever vertex was already selected right
  /// before this hit-test runs (`selectedVertexProvider`'s current value)
  /// so an exact-coincidence tie (e.g. right after
  /// [detachVertexFromPolygon]/[detachVertexFromDraft], where the new copy
  /// sits at the exact same spot as the original it came from) resolves
  /// toward the vertex the artist was already engaged with, rather than
  /// toward whichever one happens to appear later in [Artwork.polygons]'
  /// own list order (see `.cursor/plans/plan_phase_H_alpha.md`, 2026-07-16
  /// 検討メモ, for the bug this fixes).
  String? findVertexNear(
    Offset position, {
    double hitRadius = kVertexHitRadius,
    String? preferredVertexId,
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

    _vertexHitTest.rebuild(candidates);
    final nearest = _vertexHitTest.nearest(
      position,
      maxDistance: hitRadius,
      preferredId: preferredVertexId,
    );
    return nearest?.$1;
  }

  /// Front-most confirmed polygon whose filled ring contains [worldPosition],
  /// or `null` when the point misses every shape.
  ///
  /// Pure lookup — does not mutate [state], record undo, or touch session
  /// selection providers. Z-order matches [PolygonPainter]: later entries in
  /// [Artwork.polygons] are painted on top and win on overlap.
  String? findPolygonContaining(Offset worldPosition) {
    final candidates = <PolygonHitCandidate>[
      for (final polygon in state.polygons)
        (
          id: polygon.id,
          ring: [
            for (final id in polygon.vertexIds) state.vertices[id]!.position,
          ],
        ),
    ];
    return findTopmostPolygonIdAt(worldPosition, candidates: candidates);
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

  /// Translates every vertex [polygonId] references by [delta], as a
  /// single undo entry — the commit-on-release counterpart of the edit
  /// mode's whole-polygon drag (a plain pan, active only while no vertex
  /// is selected; see `PolygonDragPreview` and
  /// `.cursor/plans/plan_phase_H_alpha.md`, 2026-07-16 検討メモ). Called
  /// exactly once, when the finger lifts — the live drag itself only ever
  /// touches `PolygonDragPreview`, never [state].
  ///
  /// A corner welded to a neighboring polygon moves for *both* shapes,
  /// exactly like dragging that single shared vertex with [moveVertex]
  /// already does today — this is simply that same rule applied to every
  /// vertex of one polygon at once, not a new kind of propagation. No-op
  /// when [polygonId] doesn't exist or [delta] is zero.
  void translatePolygon(String polygonId, Offset delta) {
    if (delta == Offset.zero) return;
    final polygon = state.polygons.where((p) => p.id == polygonId).firstOrNull;
    if (polygon == null) return;

    _recordUndo();
    final updatedVertices = {...state.vertices};
    for (final vertexId in polygon.vertexIds) {
      final vertex = updatedVertices[vertexId];
      if (vertex == null) continue;
      updatedVertices[vertexId] = vertex.copyWith(position: vertex.position + delta);
    }
    state = state.copyWith(vertices: updatedVertices);
  }

  /// Subdivides [polygonId]'s edge starting at ring index [ringIndex] —
  /// i.e. between `vertexIds[ringIndex]` and its successor, wrapping after
  /// the last — by inserting a brand-new [Vertex] at the segment's
  /// [edgeMidpoint], spliced into the ring right between the two (see the
  /// edit mode's "➕ ここに追加" button, active once a target polygon *and*
  /// edge have been chosen via `resolvePolygonTarget`/`resolveEdgeTarget`).
  ///
  /// The new vertex belongs *only* to [polygonId] — unshared, exactly like
  /// a freshly placed freehand point — so the artist can immediately drag
  /// it to reshape this one edge without disturbing any neighboring
  /// polygon it happens to run alongside. Returns the new vertex's ID (so
  /// the caller can select it immediately, letting drag-to-move start with
  /// no extra tap), or `null` when [polygonId] doesn't exist or
  /// [ringIndex] is out of range.
  String? insertVertexAtEdge(String polygonId, int ringIndex) {
    final polygon = state.polygons.where((p) => p.id == polygonId).firstOrNull;
    if (polygon == null) return null;
    final vertexIds = polygon.vertexIds;
    if (ringIndex < 0 || ringIndex >= vertexIds.length) return null;

    final start = state.vertices[vertexIds[ringIndex]];
    final end = state.vertices[vertexIds[(ringIndex + 1) % vertexIds.length]];
    if (start == null || end == null) return null;

    _recordUndo();
    final newVertex = Vertex(
      id: _uuid.v4(),
      position: edgeMidpoint(start.position, end.position),
    );
    final updatedVertexIds = [
      ...vertexIds.sublist(0, ringIndex + 1),
      newVertex.id,
      ...vertexIds.sublist(ringIndex + 1),
    ];
    state = state.copyWith(
      polygons: [
        for (final p in state.polygons)
          if (p.id == polygonId) p.copyWith(vertexIds: updatedVertexIds) else p,
      ],
      vertices: {...state.vertices, newVertex.id: newVertex},
    );
    return newVertex.id;
  }

  /// Replaces [polygonId] with the triangles [result] describes (Phase G
  /// auto-tessellation, plan #17), called by `TessellationController`
  /// once `compute()`'s background triangulation succeeds.
  ///
  /// [boundaryRing] must be the exact (sanitized) ring [result] was
  /// computed from — its IDs are reused for [result]'s leading points (so
  /// any edge already welded to a neighboring polygon stays welded);
  /// every later point in [result.points] is a genuinely new interior/
  /// subdivision point and gets a fresh [Vertex] ID. Every output triangle
  /// inherits [polygonId]'s own fill/stroke styling. No-op when [polygonId]
  /// doesn't exist (e.g. deleted while the `Isolate` call was in flight).
  ///
  /// A single [_recordUndo] + a single [state] update — "一括生成 = Undo
  /// 1回" (`.cursor/plans/plan_phase_G.md`).
  /// Replaces [polygonId] with the triangles in [result].
  ///
  /// [result.points] layout must match [triangulate]: outer [boundaryRing]
  /// IDs first, then each hole ring in [holeRings] flattened in order, then
  /// edge-split inserts and interior Steiner points (minted as fresh
  /// vertices). Hole polygons themselves are left untouched — only
  /// [polygonId] is removed.
  void commitTessellationResult({
    required String polygonId,
    required List<String> boundaryRing,
    List<List<String>> holeRings = const [],
    required TessellationResult result,
  }) {
    final polygon = state.polygons.where((p) => p.id == polygonId).firstOrNull;
    if (polygon == null) return;

    _recordUndo();
    final indexToVertexId = <int, String>{
      for (var i = 0; i < boundaryRing.length; i++) i: boundaryRing[i],
    };
    var nextIndex = boundaryRing.length;
    for (final holeRing in holeRings) {
      for (final id in holeRing) {
        indexToVertexId[nextIndex++] = id;
      }
    }
    final newVertices = <String, Vertex>{};
    for (var i = nextIndex; i < result.points.length; i++) {
      final vertex = Vertex(id: _uuid.v4(), position: result.points[i]);
      indexToVertexId[i] = vertex.id;
      newVertices[vertex.id] = vertex;
    }

    final triangles = [
      for (final (a, b, c) in result.triangleIndices)
        PolygonShape(
          id: _uuid.v4(),
          vertexIds: [indexToVertexId[a]!, indexToVertexId[b]!, indexToVertexId[c]!],
          fillColor: polygon.fillColor,
          strokeColor: polygon.strokeColor,
          strokeWidth: polygon.strokeWidth,
        ),
    ];
    for (final triangle in triangles) {
      assertConfirmedRingIds(triangle.vertexIds);
    }

    state = state.copyWith(
      polygons: [
        ...state.polygons.where((p) => p.id != polygonId),
        ...triangles,
      ],
      vertices: {...state.vertices, ...newVertices},
    );
  }

  /// Updates [polygonId]'s [PolygonShape.fillColor] to [newColor].
  ///
  /// No-op when the ID is unknown or the fill is already [newColor], so a
  /// repeated palette tap never pollutes the undo stack. A real change is
  /// one [_recordUndo] entry — same D0 pattern as [deletePolygon] /
  /// [translatePolygon]. Stroke style is intentionally untouched (v1.1).
  void changePolygonColor(String polygonId, Color newColor) {
    applyPolygonColors({polygonId: newColor});
  }

  /// Applies each entry of [colorsByPolygonId] as a solid [PolygonShape.fillColor].
  ///
  /// One [_recordUndo] for the whole batch (Phase Select shade solid / light).
  /// Unknown ids are ignored. Returns `false` (and does not push undo) when
  /// every known target already has the requested color or the map is empty.
  bool applyPolygonColors(Map<String, Color> colorsByPolygonId) {
    if (colorsByPolygonId.isEmpty) return false;

    var anyChange = false;
    for (final entry in colorsByPolygonId.entries) {
      final polygon =
          state.polygons.where((p) => p.id == entry.key).firstOrNull;
      if (polygon != null && polygon.fillColor != entry.value) {
        anyChange = true;
        break;
      }
    }
    if (!anyChange) return false;

    _recordUndo();
    final updated = [
      for (final polygon in state.polygons)
        if (colorsByPolygonId.containsKey(polygon.id))
          polygon.copyWith(fillColor: colorsByPolygonId[polygon.id]!)
        else
          polygon,
    ];
    state = state.copyWith(polygons: updated);
    return true;
  }

  /// Deletes [polygonId] entirely (the edit mode's "🗑️ 図形の削除" button).
  /// Any of its vertices still referenced elsewhere — a corner welded to a
  /// neighboring polygon, or to the open draft — are kept; the rest are
  /// pruned from the shared pool, mirroring [deletePolygonVertex]'s
  /// dissolve branch and [clearAll]'s pruning loop. No-op when [polygonId]
  /// doesn't exist.
  void deletePolygon(String polygonId) {
    final polygon = state.polygons.where((p) => p.id == polygonId).firstOrNull;
    if (polygon == null) return;

    _recordUndo();
    final remainingPolygons = state.polygons.where((p) => p.id != polygonId).toList();
    var vertices = state.vertices;
    for (final vertexId in polygon.vertexIds) {
      vertices = _prune(
        vertices,
        vertexId,
        polygons: remainingPolygons,
        draftVertexIds: state.draftVertexIds,
      );
    }
    state = state.copyWith(polygons: remainingPolygons, vertices: vertices);
  }

  /// How many independent owners reference [vertexId]: one per polygon that
  /// lists it, plus one if the in-progress draft lists it.
  int _vertexOwnerCount(String vertexId) {
    var count = 0;
    if (state.draftVertexIds.contains(vertexId)) count++;
    for (final polygon in state.polygons) {
      if (polygon.vertexIds.contains(vertexId)) count++;
    }
    return count;
  }

  /// Whether [vertexId] is referenced by more than one polygon and/or draft.
  bool isVertexShared(String vertexId) => _vertexOwnerCount(vertexId) > 1;

  /// Every confirmed polygon whose ring lists [vertexId].
  List<PolygonShape> polygonsReferencing(String vertexId) {
    return [
      for (final polygon in state.polygons)
        if (polygon.vertexIds.contains(vertexId)) polygon,
    ];
  }

  /// Whether the in-progress draft lists [vertexId].
  bool draftReferencesVertex(String vertexId) =>
      state.draftVertexIds.contains(vertexId);

  /// Duplicates [vertexId] and swaps only [polygonId]'s reference to the copy,
  /// leaving every other owner still welded to the original. No-op when the
  /// vertex isn't shared or [polygonId] doesn't reference it. Returns the
  /// new copy's ID on success.
  String? detachVertexFromPolygon(String vertexId, String polygonId) {
    if (!isVertexShared(vertexId)) return null;
    final polygon = state.polygons
        .where((p) => p.id == polygonId)
        .firstOrNull;
    if (polygon == null || !polygon.vertexIds.contains(vertexId)) return null;

    _recordUndo();
    final original = state.vertices[vertexId]!;
    final copy = Vertex(id: _uuid.v4(), position: original.position);

    final updatedPolygons = [
      for (final p in state.polygons)
        if (p.id == polygonId)
          p.copyWith(
            vertexIds: [
              for (final id in p.vertexIds) id == vertexId ? copy.id : id,
            ],
          )
        else
          p,
    ];

    state = state.copyWith(
      polygons: updatedPolygons,
      vertices: {...state.vertices, copy.id: copy},
    );
    return copy.id;
  }

  /// Duplicates [vertexId] and swaps only the draft's reference to the copy.
  /// No-op when the vertex isn't shared or the draft doesn't list it. Returns
  /// the new copy's ID on success.
  String? detachVertexFromDraft(String vertexId) {
    if (!state.draftVertexIds.contains(vertexId)) return null;
    if (!isVertexShared(vertexId)) return null;

    _recordUndo();
    final original = state.vertices[vertexId]!;
    final copy = Vertex(id: _uuid.v4(), position: original.position);

    state = state.copyWith(
      draftVertexIds: [
        for (final id in state.draftVertexIds) id == vertexId ? copy.id : id,
      ],
      vertices: {...state.vertices, copy.id: copy},
    );
    return copy.id;
  }

  /// Merges [mergeId] into [keepId] by replacing every reference to
  /// [mergeId] with [keepId], collapsing consecutive duplicates in rings,
  /// and pruning [mergeId] from the shared pool. Returns false when the weld
  /// would dissolve a polygon below [kMinPolygonVertices].
  bool weldVertices(String keepId, String mergeId) {
    if (!_canWeldVertices(keepId, mergeId)) return false;

    _recordUndo();

    final updatedPolygons = [
      for (final polygon in state.polygons)
        polygon.copyWith(
          vertexIds: collapseConsecutiveRingIds([
            for (final id in polygon.vertexIds) id == mergeId ? keepId : id,
          ]),
        ),
    ];

    final draftIds = collapseConsecutiveOpenIds([
      for (final id in state.draftVertexIds) id == mergeId ? keepId : id,
    ]);

    state = state.copyWith(
      polygons: updatedPolygons,
      draftVertexIds: draftIds,
      vertices: _prune(
        state.vertices,
        mergeId,
        polygons: updatedPolygons,
        draftVertexIds: draftIds,
      ),
    );
    return true;
  }

  bool _canWeldVertices(String keepId, String mergeId) {
    if (keepId == mergeId) return false;
    if (state.vertices[keepId] == null || state.vertices[mergeId] == null) {
      return false;
    }

    for (final polygon in state.polygons) {
      final collapsed = collapseConsecutiveRingIds([
        for (final id in polygon.vertexIds) id == mergeId ? keepId : id,
      ]);
      if (collapsed.length < kMinPolygonVertices) return false;
      if (hasNonConsecutiveDuplicate(collapsed)) return false;
    }

    final collapsedDraft = collapseConsecutiveOpenIds([
      for (final id in state.draftVertexIds) id == mergeId ? keepId : id,
    ]);
    if (hasNonConsecutiveDuplicate(collapsedDraft)) return false;

    return true;
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
  /// the two ends happen to belong to (see [closingEdgeVertices]): follow
  /// the shortest existing chain of polygon boundaries connecting them —
  /// whether that's one polygon's own two arcs or a route hopping across
  /// several polygons that happen to share welded vertices — when there is
  /// one, otherwise weld onto any existing vertex that happens to sit on
  /// the straight line between them. Either way the shape tiles seamlessly
  /// against whatever it touches, instead of the specific start/end
  /// combination changing how (or whether) it welds.
  ///
  /// [lineAbsorptionTolerance] follows the same screen-tolerance convention
  /// as [handleDrawTap]'s own parameter of the same name — callers with a
  /// viewport transform (the toolbar's "閉じる" button included) should
  /// pass `kLineAbsorptionTolerance / transform.scale`.
  ///
  /// Returns [ClosePolygonResult.closed] on success. When the proposed ring
  /// would self-intersect or skewer existing geometry, returns
  /// [ClosePolygonResult.rejectedUnsafeClosingEdge], leaves the draft
  /// untouched, and records nothing on the undo stack. Callers should surface
  /// [kClosePolygonRejectedMessage] (e.g. via SnackBar) on that result.
  ///
  /// The most recent result is also mirrored on [lastClosePolygonResult] so
  /// gesture handlers that close through [handleDrawTap] can read it afterward.
  /// Cleared at the start of each [handleDrawTap] so a rejected close does
  /// not keep toasting on later, non-close taps.
  ClosePolygonResult? lastClosePolygonResult;

  ClosePolygonResult closePolygon(
    Color fillColor, {
    double lineAbsorptionTolerance = kLineAbsorptionTolerance,
  }) {
    _resetPendingTap();
    final draftIds = state.draftVertexIds;
    if (draftIds.length < kMinPolygonVertices) {
      return lastClosePolygonResult = ClosePolygonResult.tooFewVertices;
    }
    final vertexIds = collapseConsecutiveRingIds([
      ...draftIds,
      ...closingEdgeVertices(
        draftIds.first,
        draftIds.last,
        polygons: state.polygons,
        vertices: state.vertices,
        draftVertexIds: draftIds,
        tolerance: lineAbsorptionTolerance,
      ),
    ]);
    if (!isSafeClosedRing(
      vertexIds,
      vertices: state.vertices,
      polygons: state.polygons,
      minVertices: kMinPolygonVertices,
    )) {
      return lastClosePolygonResult =
          ClosePolygonResult.rejectedUnsafeClosingEdge;
    }
    assertConfirmedRingIds(vertexIds);
    _recordUndo();
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
    return lastClosePolygonResult = ClosePolygonResult.closed;
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

  /// Replaces the entire artwork in one shot — used when opening a saved
  /// artwork or starting a brand new one (Phase Hγ gallery, `GalleryController`).
  /// Clears the undo stack entirely: an artwork's edit history has no
  /// meaning once the artwork itself has been swapped out from under it,
  /// and carrying it over would let [undo] reach back into a *different*
  /// artwork's past state.
  void loadArtwork(Artwork artwork) {
    _resetPendingTap();
    _undoStack.clear();
    for (final polygon in artwork.polygons) {
      assertConfirmedRingIds(polygon.vertexIds);
    }
    state = artwork;
  }

  /// Updates [Artwork.title] (document metadata, not geometry). Trims
  /// whitespace; an empty result falls back to [kDefaultArtworkTitle].
  /// No-op when the resolved title equals the current one. Deliberately
  /// does **not** call [_recordUndo] — undo is geometry-only.
  void setTitle(String title) {
    final trimmed = title.trim();
    final resolved = trimmed.isEmpty ? kDefaultArtworkTitle : trimmed;
    if (resolved == state.title) return;
    state = state.copyWith(title: resolved);
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
