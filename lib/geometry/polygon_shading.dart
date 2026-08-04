import 'dart:collection';
import 'dart:math' as math;

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

/// Power for the distance→lightness ease-out curve. Values &gt; 1 drop lightness
/// faster near the origin and more gently at far stops (stronger near contrast).
const double kShadingGamma = 1.6;

/// Far-stop saturation scale: final stop keeps this fraction of base saturation
/// (`1.0 - kShadingSaturationFalloff` at `t == 1`).
const double kShadingSaturationFalloff = 0.15;

/// Amplitude of deterministic lightness jitter as a fraction of one ramp step.
const double kShadingLightnessJitter = 0.55;

/// Amplitude of deterministic saturation jitter (absolute HSL saturation units).
const double kShadingSaturationJitter = 0.04;

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
  /// Stops are **pre-jitter** reference colors for the Shade palette UI.
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
/// (must be in [targetIds]) maps to [kShadingRampStops] HSL steps derived
/// from [baseColor] with a gamma ease-out curve and mild far-stop desaturation.
/// Non-origin polygons get a deterministic id-based lightness/saturation
/// jitter so same-distance neighbors rarely look identical.
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
  double gamma = kShadingGamma,
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
    gamma: gamma,
  );

  final baseHsl = HSLColor.fromColor(baseColor);
  final startL = baseHsl.lightness;
  final endL = minLightness.clamp(0.0, startL);
  final step = rampStops > 1 ? (startL - endL) / (rampStops - 1) : 0.0;

  final colors = <String, Color>{};
  var maxDistance = 0;
  for (final entry in distances.entries) {
    final distance = entry.value;
    if (distance > maxDistance) maxDistance = distance;
    final rampIndex = distance >= rampStops ? rampStops - 1 : distance;
    final id = entry.key;

    // Origin keeps the artist's base color exactly (no facet jitter).
    if (distance == 0) {
      colors[id] = ramp[0];
      continue;
    }

    colors[id] = _applyDeterministicJitter(
      ramp[rampIndex],
      polygonId: id,
      step: step,
      minLightness: endL,
      maxLightness: startL,
    );
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

/// Builds the pre-jitter reference ramp: gamma ease-out on lightness plus a
/// mild far-stop saturation falloff for depth.
List<Color> _buildLightnessRamp(
  Color baseColor, {
  required int rampStops,
  required double minLightness,
  required double gamma,
}) {
  final hsl = HSLColor.fromColor(baseColor);
  final start = hsl.lightness;
  final end = minLightness.clamp(0.0, start);
  final baseSat = hsl.saturation;
  if (rampStops == 1) {
    return [hsl.withLightness(start).toColor()];
  }
  final safeGamma = gamma <= 0 ? 1.0 : gamma;
  final ramp = <Color>[];
  for (var i = 0; i < rampStops; i++) {
    final t = i / (rampStops - 1);
    // Ease-out: larger ΔL near the origin, gentler toward the far stop.
    final curved = 1.0 - math.pow(1.0 - t, safeGamma).toDouble();
    final lightness = start - (start - end) * curved;
    final saturation =
        (baseSat * (1.0 - kShadingSaturationFalloff * curved)).clamp(0.0, 1.0);
    ramp.add(
      hsl
          .withLightness(lightness.clamp(0.0, 1.0))
          .withSaturation(saturation)
          .toColor(),
    );
  }
  return ramp;
}

/// FNV-1a 32-bit over UTF-16 code units — stable across runs / isolates.
int _stableHash(String id) {
  var hash = 2166136261;
  for (final unit in id.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0xffffffff;
  }
  return hash;
}

/// Deterministic noise in approximately `[-1.0, 1.0]` from [id] + [salt].
double _unitNoise(String id, {required int salt}) {
  final hash = _stableHash('$salt:$id');
  return ((hash & 0xffff) / 0xffff) * 2.0 - 1.0;
}

Color _applyDeterministicJitter(
  Color base, {
  required String polygonId,
  required double step,
  required double minLightness,
  required double maxLightness,
}) {
  final hsl = HSLColor.fromColor(base);
  final nL = _unitNoise(polygonId, salt: 1);
  final nS = _unitNoise(polygonId, salt: 2);
  final lightness =
      (hsl.lightness + nL * step * kShadingLightnessJitter)
          .clamp(minLightness, maxLightness);
  final saturation =
      (hsl.saturation + nS * kShadingSaturationJitter).clamp(0.0, 1.0);
  return hsl.withLightness(lightness).withSaturation(saturation).toColor();
}
