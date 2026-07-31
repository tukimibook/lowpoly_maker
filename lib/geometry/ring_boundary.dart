import 'dart:ui';

import 'point_in_polygon.dart';

/// Euclidean distance from [p] to the closest point on segment [a]–[b].
double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSq = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSq == 0) return (p - a).distance;
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSq;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  return (p - proj).distance;
}

/// True when [point] lies on any edge of the closed [ring] (within epsilon).
bool isOnRingBoundary(Offset point, List<Offset> ring) {
  const epsilon = 1e-6;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    if (distanceToSegment(point, a, b) <= epsilon) return true;
  }
  return false;
}

/// [isPointInPolygon] with an explicit on-boundary → outside override so a
/// closing chord that reuses an existing edge is not mistaken for a skewer.
bool isStrictlyInsidePolygon(Offset point, List<Offset> ring) {
  if (isOnRingBoundary(point, ring)) return false;
  return isPointInPolygon(point, ring);
}

/// Collapses consecutive coincident corners (and a trailing wrap-around
/// duplicate of the first point) from a closed ring of positions.
List<Offset> collapseConsecutiveDuplicatePoints(List<Offset> points) {
  if (points.isEmpty) return const [];
  final out = <Offset>[points.first];
  for (var i = 1; i < points.length; i++) {
    if (points[i] != out.last) out.add(points[i]);
  }
  if (out.length > 1 && out.first == out.last) out.removeLast();
  return out;
}
