import 'dart:ui';

/// Cross-product-based orientation of the turn `p -> q -> r`: positive for
/// counter-clockwise, negative for clockwise, and (near) zero when the
/// three points are collinear. Shared by [segmentsIntersect].
double _orientation(Offset p, Offset q, Offset r) {
  return (q.dy - p.dy) * (r.dx - q.dx) - (q.dx - p.dx) * (r.dy - q.dy);
}

/// True when [q] lies on the closed bounding box of segment `p`-`r`, given
/// the three points are already known to be collinear. Used only by the
/// degenerate (collinear-touching) branches of [segmentsIntersect].
bool _onSegment(Offset p, Offset q, Offset r) {
  return q.dx <= (p.dx > r.dx ? p.dx : r.dx) &&
      q.dx >= (p.dx < r.dx ? p.dx : r.dx) &&
      q.dy <= (p.dy > r.dy ? p.dy : r.dy) &&
      q.dy >= (p.dy < r.dy ? p.dy : r.dy);
}

/// True when segments (`a1`,`a2`) and (`b1`,`b2`) intersect — either by
/// properly crossing each other, or by touching in a collinear-overlap
/// configuration (one segment's endpoint lying exactly on the other). A
/// shared endpoint between the two segments (e.g. adjacent ring edges)
/// counts as an intersection too; callers that consider that expected
/// (adjacent edges of a polygon ring always share a vertex) must exclude
/// those pairs before calling this, as [isSelfIntersectingRing] does.
bool segmentsIntersect(Offset a1, Offset a2, Offset b1, Offset b2) {
  int sign(double value) {
    if (value > 0) return 1;
    if (value < 0) return -1;
    return 0;
  }

  final o1 = sign(_orientation(a1, a2, b1));
  final o2 = sign(_orientation(a1, a2, b2));
  final o3 = sign(_orientation(b1, b2, a1));
  final o4 = sign(_orientation(b1, b2, a2));

  if (o1 != o2 && o3 != o4) return true;

  if (o1 == 0 && _onSegment(a1, b1, a2)) return true;
  if (o2 == 0 && _onSegment(a1, b2, a2)) return true;
  if (o3 == 0 && _onSegment(b1, a1, b2)) return true;
  if (o4 == 0 && _onSegment(b1, a2, b2)) return true;

  return false;
}

/// True when the closed ring described by [points] — in order, with the
/// last point implicitly connecting back to the first — is self-
/// intersecting: any two of its edges that are not immediate neighbors
/// (and don't merely share the ring's own wrap-around vertex) cross.
///
/// This assumes [points] has already been through vertex-coincidence
/// welding and consecutive/non-consecutive duplicate checks (see
/// `tessellation_input.dart`) — it only detects *geometric* crossings
/// between edges that don't already share an endpoint ID.
///
/// O(e²) in the number of edges; acceptable since this runs once per
/// tessellation request rather than per frame.
bool isSelfIntersectingRing(List<Offset> points) {
  final n = points.length;
  if (n < 4) return false; // fewer than 4 edges can never self-intersect.

  for (var i = 0; i < n; i++) {
    final a1 = points[i];
    final a2 = points[(i + 1) % n];
    for (var j = i + 1; j < n; j++) {
      if (j == i + 1) continue; // shares vertex a2/b1 — adjacent edge.
      if (i == 0 && j == n - 1) continue; // wrap-around adjacency.
      final b1 = points[j];
      final b2 = points[(j + 1) % n];
      if (segmentsIntersect(a1, a2, b1, b2)) return true;
    }
  }
  return false;
}
