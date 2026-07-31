import 'dart:ui';

import '../models/polygon_shape.dart';
import '../models/vertex.dart';
import 'polygon_containment.dart';
import 'ring_boundary.dart';
import 'self_intersection.dart';

/// True when closing into [ringIds] would produce a geometrically safe
/// confirmed polygon: no self-intersection, and the implicit closing chord
/// (`last → first`) neither properly crosses an existing polygon edge nor
/// has its midpoint strictly inside an existing polygon (classic skewer).
///
/// Only the closing chord is checked against existing geometry — freehand
/// draft edges were already accepted while drawing and must not block an
/// otherwise-valid boundary weld.
bool isSafeClosedRing(
  List<String> ringIds, {
  required Map<String, Vertex> vertices,
  required List<PolygonShape> polygons,
  required int minVertices,
}) {
  if (ringIds.length < minVertices) return false;
  final points = <Offset>[];
  for (final id in ringIds) {
    final vertex = vertices[id];
    if (vertex == null) return false;
    points.add(vertex.position);
  }
  // Collapse consecutive coincident corners (e.g. an extra weld tap that
  // minted a duplicate ID at the same spot) before the self-intersection
  // check — zero-length edges otherwise look like crossings.
  final simple = collapseConsecutiveDuplicatePoints(points);
  if (simple.length < minVertices) return false;
  if (isSelfIntersectingRing(simple)) return false;

  final closeA = points.last;
  final closeB = points.first;
  final closeMid = Offset(
    (closeA.dx + closeB.dx) / 2,
    (closeA.dy + closeB.dy) / 2,
  );
  // One-edge "ring" used with [ringsEdgesProperlyIntersect] so shared
  // endpoints with existing polygon edges are skipped the same way.
  final closingEdge = <Offset>[closeA, closeB];

  final closeEndIds = {ringIds.last, ringIds.first};
  for (final polygon in polygons) {
    final ring = <Offset>[];
    for (final id in polygon.vertexIds) {
      final vertex = vertices[id];
      if (vertex == null) return false;
      ring.add(vertex.position);
    }
    // Classic skewer: both ends are corners of this polygon and the chord
    // cuts through its interior. A fully contained inner polygon (hole)
    // has endpoints that are *not* on the outer ring, so it stays allowed;
    // a chord that pierces an unrelated shape is caught by the proper-
    // intersection check below.
    final endsOnThisPolygon = closeEndIds.every(polygon.vertexIds.contains);
    if (endsOnThisPolygon && isStrictlyInsidePolygon(closeMid, ring)) {
      return false;
    }
    if (ringsEdgesProperlyIntersect(closingEdge, ring)) return false;
  }
  return true;
}
