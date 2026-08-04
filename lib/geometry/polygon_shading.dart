import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/polygon_shape.dart';

/// Number of discrete shade steps in [computeDistanceShading]'s color ramp
/// (distance 0 … [kShadingRampStops] − 1). Tunable for UX; keep in sync with
/// Phase Select Step 3.0 (`plan_phase_Select.md`).
const int kShadingRampStops = 6;

/// Floor for HSL lightness on the darkest ramp stop. Prevents near-black
/// collapses that are hard to tell apart on a dark canvas.
const double kShadingMinLightness = 0.12;

/// Output of [computeDistanceShading]: per-polygon solid fills plus the
/// discrete ramp used to assign them (for the Shade toolbar hand-tune UI).
///
/// [colorsByPolygonId] contains **only** polygons reachable from the origin
/// within [targetIds]. Unreachable (disconnected) IDs are omitted so callers
/// can leave those polygons' existing `fillColor` untouched.
@immutable
class ShadingResult {
  const ShadingResult({
    required this.colorsByPolygonId,
    required this.ramp,
    required this.maxDistance,
  });

  /// Empty result: no assignments, empty ramp, [maxDistance] = −1.
  static const empty = ShadingResult(
    colorsByPolygonId: {},
    ramp: [],
    maxDistance: -1,
  );

  /// Reachable polygon id → assigned solid [Color].
  final Map<String, Color> colorsByPolygonId;

  /// Length [kShadingRampStops] (or empty when this is [empty]): index 0 is
  /// the base / lightest stop, later indices are progressively darker.
  final List<Color> ramp;

  /// Largest BFS hop count among reachable polygons, or `-1` when nothing
  /// was assigned. The origin alone yields `0`.
  final int maxDistance;
}

/// Distance-based solid shading over a selection of polygons.
///
/// Pure: no providers, no mutation of [polygons]. Adjacency is **shared
/// vertex id** (weld model) within [targetIds] only — two rings are neighbors
/// when their `vertexIds` sets intersect. BFS distance from [originId]
/// (must be in [targetIds]) maps to [kShadingRampStops] HSL-lightness steps
/// derived from [baseColor]: `color = ramp[min(distance, rampStops − 1)]`.
///
/// Returns [ShadingResult.empty] when [originId] is not in [targetIds],
/// [targetIds] is empty, or [originId] is absent from [polygons].
ShadingResult computeDistanceShading({
  required String originId,
  required Set<String> targetIds,
  required List<PolygonShape> polygons,
  required Color baseColor,
  int rampStops = kShadingRampStops,
  double minLightness = kShadingMinLightness,
}) {
  if (targetIds.isEmpty || !targetIds.contains(originId) || rampStops < 1) {
    return ShadingResult.empty;
  }

  final selected = <String, PolygonShape>{
    for (final polygon in polygons)
      if (targetIds.contains(polygon.id)) polygon.id: polygon,
  };
  if (!selected.containsKey(originId)) return ShadingResult.empty;

  final adjacency = _adjacencyBySharedVertexIds(selected);
  final distances = _bfsDistances(originId, adjacency);
  final ramp = _buildLightnessRamp(
    baseColor,
    rampStops: rampStops,
    minLightness: minLightness,
  );

  final colors = <String, Color>{};
  var maxDistance = 0;
  for (final entry in distances.entries) {
    final distance = entry.value;
    if (distance > maxDistance) maxDistance = distance;
    final rampIndex = distance >= rampStops ? rampStops - 1 : distance;
    colors[entry.key] = ramp[rampIndex];
  }

  return ShadingResult(
    colorsByPolygonId: colors,
    ramp: ramp,
    maxDistance: maxDistance,
  );
}

/// Undirected adjacency among [selected] polygons: an edge exists when two
/// rings share at least one vertex id.
Map<String, Set<String>> _adjacencyBySharedVertexIds(
  Map<String, PolygonShape> selected,
) {
  final polygonsByVertex = <String, List<String>>{};
  for (final polygon in selected.values) {
    for (final vertexId in polygon.vertexIds.toSet()) {
      (polygonsByVertex[vertexId] ??= []).add(polygon.id);
    }
  }

  final adjacency = <String, Set<String>>{
    for (final id in selected.keys) id: <String>{},
  };
  for (final polygonIds in polygonsByVertex.values) {
    if (polygonIds.length < 2) continue;
    for (var i = 0; i < polygonIds.length; i++) {
      for (var j = i + 1; j < polygonIds.length; j++) {
        final a = polygonIds[i];
        final b = polygonIds[j];
        adjacency[a]!.add(b);
        adjacency[b]!.add(a);
      }
    }
  }
  return adjacency;
}

/// BFS hop counts from [originId]. Only keys present in [adjacency] are
/// visited; disconnected nodes never appear in the result.
Map<String, int> _bfsDistances(
  String originId,
  Map<String, Set<String>> adjacency,
) {
  final distances = <String, int>{originId: 0};
  final queue = Queue<String>()..add(originId);
  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    final nextDistance = distances[current]! + 1;
    for (final neighbor in adjacency[current] ?? const <String>{}) {
      if (distances.containsKey(neighbor)) continue;
      distances[neighbor] = nextDistance;
      queue.add(neighbor);
    }
  }
  return distances;
}

List<Color> _buildLightnessRamp(
  Color baseColor, {
  required int rampStops,
  required double minLightness,
}) {
  final hsl = HSLColor.fromColor(baseColor);
  final start = hsl.lightness;
  final end = minLightness.clamp(0.0, start);
  if (rampStops == 1) {
    return [hsl.withLightness(start).toColor()];
  }
  return [
    for (var i = 0; i < rampStops; i++)
      hsl
          .withLightness(
            start - (start - end) * (i / (rampStops - 1)),
          )
          .toColor(),
  ];
}
