import 'dart:ui';

import 'point_in_polygon.dart';
import 'polygon_containment.dart';

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
