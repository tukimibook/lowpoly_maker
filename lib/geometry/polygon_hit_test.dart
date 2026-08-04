import 'dart:ui';

import 'point_in_polygon.dart';
import 'polygon_containment.dart';
import 'ring_boundary.dart';

/// True when [point] lies inside [ring], using a cheap AABB reject before
/// the exact even-odd ray-cast ([isPointInPolygon]).
///
/// [ringBounds] is inclusive on its edges; points that miss the box never
/// reach the ray-caster. Points that land exactly on a ring edge/vertex
/// still follow [isPointInPolygon]'s "boundary counts as outside" rule.
bool pointInRingWithAabb(Offset point, List<Offset> ring) {
  if (ring.length < 3) return false;
  if (!ringBounds(ring).contains(point)) return false;
  return isPointInPolygon(point, ring);
}

/// A closed polygon ring paired with a stable identifier, in **draw order**
/// (index 0 = painted first = furthest back).
typedef PolygonHitCandidate = ({String id, List<Offset> ring});

/// Returns the [id] of the front-most candidate whose ring contains [point],
/// or `null` when none do.
///
/// [candidates] must be in the same order as `Artwork.polygons` / the
/// painter (first = back, last = front). Walks **last → first** so the
/// first geometric hit is the topmost shape under the tap.
String? findTopmostPolygonIdAt(
  Offset point, {
  required List<PolygonHitCandidate> candidates,
}) {
  for (var i = candidates.length - 1; i >= 0; i--) {
    final candidate = candidates[i];
    if (pointInRingWithAabb(point, candidate.ring)) return candidate.id;
  }
  return null;
}

/// Index of the closed-ring edge nearest to [point], or `null` when none
/// lie within [tolerance] (or the ring has fewer than 2 vertices).
///
/// Edge `i` runs from `ring[i]` to `ring[(i + 1) % length]` — the same
/// [ringIndex] convention as [resolveEdgeTarget] /
/// [CanvasNotifier.insertVertexAtEdge]. Ties prefer the lower index.
int? findNearestRingEdgeIndex(
  Offset point,
  List<Offset> ring, {
  required double tolerance,
}) {
  if (ring.length < 2 || tolerance < 0) return null;

  int? bestIndex;
  var bestDistance = double.infinity;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final d = distanceToSegment(point, a, b);
    if (d <= tolerance && d < bestDistance) {
      bestDistance = d;
      bestIndex = i;
    }
  }
  return bestIndex;
}
