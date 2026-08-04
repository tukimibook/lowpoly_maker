import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/polygon_shape.dart';
import 'canvas_provider.dart';

/// Paired raw cycle indices for edit-mode whole-shape targeting
/// (図形切替 / 辺切替). Kept as one immutable value so polygon and edge
/// can never be mutated independently without going through
/// [EditSelectionNotifier] — which enforces the invariant that selecting
/// or cycling a polygon always clears the edge target.
@immutable
class EditSelectionState {
  const EditSelectionState({
    this.polygonIndex = -1,
    this.edgeIndex = -1,
  });

  /// `-1` = nothing chosen yet. See [resolvePolygonTarget].
  final int polygonIndex;

  /// `-1` = no edge chosen yet. Only meaningful relative to the polygon
  /// currently resolved from [polygonIndex].
  final int edgeIndex;

  @override
  bool operator ==(Object other) {
    return other is EditSelectionState &&
        other.polygonIndex == polygonIndex &&
        other.edgeIndex == edgeIndex;
  }

  @override
  int get hashCode => Object.hash(polygonIndex, edgeIndex);
}

/// Owns [EditSelectionState] and guarantees the polygon/edge pair invariant:
/// any change of polygon target clears the edge (`edgeIndex = -1`).
class EditSelectionNotifier extends StateNotifier<EditSelectionState> {
  EditSelectionNotifier() : super(const EditSelectionState());

  /// Sets the polygon cycle index and clears any prior edge target.
  void selectPolygon(int index) {
    state = EditSelectionState(polygonIndex: index, edgeIndex: -1);
  }

  /// Sets the edge cycle index without touching the polygon index
  /// (drill-down / 辺切替).
  void selectEdge(int index) {
    state = EditSelectionState(
      polygonIndex: state.polygonIndex,
      edgeIndex: index,
    );
  }

  /// Advances the polygon cycle by one and clears the edge target.
  void cyclePolygon() {
    state = EditSelectionState(
      polygonIndex: state.polygonIndex + 1,
      edgeIndex: -1,
    );
  }

  /// Advances the edge cycle by one (wrap handled by [resolveEdgeTarget]).
  void cycleEdge() {
    state = EditSelectionState(
      polygonIndex: state.polygonIndex,
      edgeIndex: state.edgeIndex + 1,
    );
  }

  /// Clears both indices back to the `-1` sentinel.
  void clearBoth() {
    state = const EditSelectionState();
  }
}

/// Single source of truth for edit-mode polygon/edge cycle indices.
final editSelectionProvider =
    StateNotifierProvider<EditSelectionNotifier, EditSelectionState>((ref) {
  return EditSelectionNotifier();
});

/// Resolves which polygon [rawCycleIndex] currently targets, out of
/// [polygons] in their existing order. `null` when [rawCycleIndex] is the
/// initial `-1` sentinel or [polygons] is empty — callers should not be
/// showing a highlight, nor enabling the edge-cycle/insert/delete buttons,
/// in that case.
String? resolvePolygonTarget({
  required List<PolygonShape> polygons,
  required int rawCycleIndex,
}) {
  if (rawCycleIndex < 0 || polygons.isEmpty) return null;
  return polygons[rawCycleIndex % polygons.length].id;
}

/// One edge of a [PolygonShape.vertexIds] ring: the segment running from
/// [startVertexId] to [endVertexId]. [ringIndex] is [startVertexId]'s own
/// index within `vertexIds` (i.e. exactly where
/// [CanvasNotifier.insertVertexAtEdge] should splice a new vertex in), so
/// callers never need to re-derive it by searching `vertexIds` themselves.
typedef PolygonEdge = ({String startVertexId, String endVertexId, int ringIndex});

/// Resolves which edge of [polygon] [rawCycleIndex] currently targets.
/// Same `-1` = "nothing chosen yet" convention as [resolvePolygonTarget].
/// A ring of fewer than 2 vertices has no meaningful edge and also
/// resolves to `null` (defensive — [PolygonShape]s are never actually
/// constructed with fewer than `kMinPolygonVertices` points).
PolygonEdge? resolveEdgeTarget({
  required PolygonShape polygon,
  required int rawCycleIndex,
}) {
  final vertexIds = polygon.vertexIds;
  if (rawCycleIndex < 0 || vertexIds.length < 2) return null;
  final index = rawCycleIndex % vertexIds.length;
  return (
    startVertexId: vertexIds[index],
    endVertexId: vertexIds[(index + 1) % vertexIds.length],
    ringIndex: index,
  );
}

/// Resolved edit-mode whole-shape target: the polygon (and optional edge)
/// currently implied by [editSelectionProvider] against the live artwork.
///
/// Single source of truth for canvas highlight and toolbar actions — both
/// must watch this instead of re-running [resolvePolygonTarget] /
/// [resolveEdgeTarget] locally.
typedef EditTarget = ({String? polygonId, PolygonEdge? edge});

/// Derives the active [EditTarget] from [editSelectionProvider] + artwork.
///
/// Returns `(polygonId: null, edge: null)` when nothing is chosen yet, the
/// artwork has no polygons, or the resolved id is no longer present.
final editTargetProvider = Provider<EditTarget>((ref) {
  final artwork = ref.watch(canvasProvider);
  final selection = ref.watch(editSelectionProvider);

  final polygonId = resolvePolygonTarget(
    polygons: artwork.polygons,
    rawCycleIndex: selection.polygonIndex,
  );
  if (polygonId == null) {
    return (polygonId: null, edge: null);
  }

  final polygon =
      artwork.polygons.where((p) => p.id == polygonId).firstOrNull;
  if (polygon == null) {
    return (polygonId: null, edge: null);
  }

  final edge = resolveEdgeTarget(
    polygon: polygon,
    rawCycleIndex: selection.edgeIndex,
  );
  return (polygonId: polygonId, edge: edge);
});
