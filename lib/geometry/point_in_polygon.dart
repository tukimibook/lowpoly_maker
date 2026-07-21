import 'dart:ui';

/// True when [point] lies inside the closed polygon ring [ring]
/// (last vertex implicitly connects back to the first), using the classic
/// even-odd ray-casting rule: cast a horizontal half-line from [point]
/// to `+∞` on x and count crossings with ring edges; an odd count means
/// inside.
///
/// Deliberately a plain function of [Offset] values only — no Flutter UI /
/// Riverpod / Material dependencies — so it is safe to call from inside
/// `compute()`'s Isolate (see `TessellationService.triangulate`) as well
/// as from ordinary synchronous unit tests.
///
/// Returns `false` when [ring] has fewer than 3 vertices (nothing that
/// can enclose an area). Points that land exactly on a vertex or edge
/// are treated as outside by this implementation; callers that care
/// about boundary cases (e.g. tessellation's centroid filter) should not
/// rely on exact-on-boundary hits — a triangle's centroid of a clearly
/// exterior / interior triangle never lands on an edge in practice.
bool isPointInPolygon(Offset point, List<Offset> ring) {
  if (ring.length < 3) return false;

  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final vi = ring[i];
    final vj = ring[j];

    // Crosses the horizontal ray from `point` to +∞ on x iff the edge
    // straddles `point.dy` vertically and the crossing's x is to the
    // right of `point.dx`.
    final crosses =
        ((vi.dy > point.dy) != (vj.dy > point.dy)) &&
        (point.dx <
            (vj.dx - vi.dx) * (point.dy - vi.dy) / (vj.dy - vi.dy) + vi.dx);
    if (crosses) inside = !inside;
  }
  return inside;
}
