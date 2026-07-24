import 'dart:ui';

import 'point_in_polygon.dart';
import 'self_intersection.dart';

/// Axis-aligned bounding box of a closed [ring]. Returns [Rect.zero] when
/// [ring] is empty.
Rect ringBounds(List<Offset> ring) {
  if (ring.isEmpty) return Rect.zero;
  var minX = ring.first.dx;
  var maxX = ring.first.dx;
  var minY = ring.first.dy;
  var maxY = ring.first.dy;
  for (final p in ring.skip(1)) {
    if (p.dx < minX) minX = p.dx;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dy > maxY) maxY = p.dy;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Absolute shoelace area of [ring]. Returns `0` when [ring] has fewer than
/// 3 points. Local to containment so this module stays dependency-light.
double ringAbsArea(List<Offset> ring) {
  if (ring.length < 3) return 0;
  var sum = 0.0;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    sum += ring[j].dx * ring[i].dy - ring[i].dx * ring[j].dy;
  }
  return sum.abs() * 0.5;
}

/// True when [outer] fully contains [inner]'s bbox (inclusive on edges).
bool boundsContainsBounds(Rect outer, Rect inner) {
  return outer.left <= inner.left &&
      outer.top <= inner.top &&
      outer.right >= inner.right &&
      outer.bottom >= inner.bottom;
}

/// True when any edge of [a] properly intersects any edge of [b]
/// (shared endpoints alone do not count — rings that merely touch at a
/// vertex are still rejected later by the strict-interior vertex check).
bool ringsEdgesProperlyIntersect(List<Offset> a, List<Offset> b) {
  if (a.length < 2 || b.length < 2) return false;
  for (var i = 0; i < a.length; i++) {
    final a1 = a[i];
    final a2 = a[(i + 1) % a.length];
    for (var j = 0; j < b.length; j++) {
      final b1 = b[j];
      final b2 = b[(j + 1) % b.length];
      if (_samePoint(a1, b1) ||
          _samePoint(a1, b2) ||
          _samePoint(a2, b1) ||
          _samePoint(a2, b2)) {
        continue;
      }
      if (segmentsIntersect(a1, a2, b1, b2)) return true;
    }
  }
  return false;
}

bool _samePoint(Offset p, Offset q) => p.dx == q.dx && p.dy == q.dy;

/// True when [inner] is a **strictly fully contained** hole candidate of
/// [outer]:
/// - AABB of [inner] ⊆ AABB of [outer] (cheap reject),
/// - area([inner]) < area([outer]) (cheap reject),
/// - every vertex of [inner] lies strictly inside [outer]
///   ([isPointInPolygon] treats boundary as outside),
/// - no edge of [inner] properly crosses an edge of [outer].
///
/// Partial overlaps, touching boundaries, and equal/larger areas all
/// return `false` (fail-safe: do not treat as a hole).
bool isRingFullyContained({
  required List<Offset> outer,
  required List<Offset> inner,
}) {
  if (outer.length < 3 || inner.length < 3) return false;

  final outerArea = ringAbsArea(outer);
  final innerArea = ringAbsArea(inner);
  if (innerArea <= 0 || outerArea <= 0) return false;
  if (innerArea >= outerArea) return false;

  if (!boundsContainsBounds(ringBounds(outer), ringBounds(inner))) {
    return false;
  }

  for (final p in inner) {
    if (!isPointInPolygon(p, outer)) return false;
  }

  if (ringsEdgesProperlyIntersect(outer, inner)) return false;

  return true;
}

/// Filters [candidates] to those rings fully contained in [outer], in the
/// same order they appear. Pure — used by [TessellationController] before
/// building a [TessellationRequest].
List<List<Offset>> collectFullyContainedHoleRings({
  required List<Offset> outer,
  required List<List<Offset>> candidates,
}) {
  return [
    for (final candidate in candidates)
      if (isRingFullyContained(outer: outer, inner: candidate)) candidate,
  ];
}
