import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/polygon_shape.dart';

/// Raw cycle position for the edit mode's "図形を切り替え" button
/// (`Icons.autorenew`, shown while *no* vertex is selected — see
/// `.cursor/plans/plan_phase_H_alpha.md`, 2026-07-16 検討メモ).
///
/// Unlike `detachCycleIndexProvider` (`providers/detach_cycle_provider.dart`)
/// — which always has at least one real candidate by the time it's read —
/// this feature is live the moment edit mode is entered, before the artist
/// has chosen anything. `-1` is therefore a deliberate sentinel meaning
/// "nothing chosen yet", so [resolvePolygonTarget] can tell "not started"
/// apart from "wrapped back to the first candidate". Otherwise this is the
/// same "unclamped counter + pure modulo resolve" pattern: nothing here
/// ever needs to reach into `Artwork` just to keep the counter in range.
final polygonCycleIndexProvider = StateProvider<int>((ref) => -1);

/// Raw cycle position for the edit mode's "辺を切り替え" button
/// (`Icons.skip_next`), meaningful only once [polygonCycleIndexProvider]
/// resolves to a real target polygon. Same `-1` = "nothing chosen yet"
/// convention as [polygonCycleIndexProvider]; reset to `-1` every time the
/// target *polygon* changes, since an edge index only ever makes sense
/// relative to whichever polygon's ring it's currently read against.
final edgeCycleIndexProvider = StateProvider<int>((ref) => -1);

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
