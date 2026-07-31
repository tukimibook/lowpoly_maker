import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/polygon_shape.dart';
import '../models/vertex.dart';

/// Finds existing confirmed-polygon vertices that lie almost exactly on
/// the segment from [start] to [end] — within [tolerance] of perpendicular
/// distance from the line, and strictly between its two ends — ordered by
/// how far along the segment they fall. [excludeVertexId] additionally
/// excludes that one vertex ID even if it would otherwise qualify (used by
/// callers to skip the segment's own endpoint when it resolved to an
/// existing vertex).
///
/// Every ID in [draftVertexIds] is always excluded too, since callers use
/// this to grow an in-progress draft and re-inserting one of its own
/// points mid-draft would create a self-intersecting loop instead of a
/// straight pass-through.
///
/// This lets an artist connect two distant corners with a single tap and
/// have every vertex the line happens to pass close to (e.g. another
/// shape's edge sitting between them) folded into the new draft
/// automatically, instead of requiring a separate tap on each one. It is
/// also reused for the implicit polygon-closing edge, so that edge never
/// skips a vertex sitting on it just because it wasn't drawn by an
/// explicit tap.
List<String> findVerticesAlongSegment(
  Offset start,
  Offset end, {
  required Map<String, Vertex> vertices,
  required List<PolygonShape> polygons,
  required Set<String> draftVertexIds,
  required double tolerance,
  String? excludeVertexId,
}) {
  final segment = end - start;
  final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
  if (lengthSquared == 0) return const [];

  final candidates = <(double t, String vertexId)>[];

  for (final polygon in polygons) {
    for (final vertexId in polygon.vertexIds) {
      if (vertexId == excludeVertexId || draftVertexIds.contains(vertexId)) {
        continue;
      }
      final vertex = vertices[vertexId];
      if (vertex == null) continue;

      final toVertex = vertex.position - start;
      final t =
          (toVertex.dx * segment.dx + toVertex.dy * segment.dy) /
          lengthSquared;
      if (t <= 0 || t >= 1) continue; // strictly between the two endpoints

      final projection = start + segment * t;
      if ((vertex.position - projection).distance <= tolerance) {
        candidates.add((t, vertexId));
      }
    }
  }

  candidates.sort((a, b) => a.$1.compareTo(b.$1));
  final seen = <String>{};
  final result = [
    for (final candidate in candidates)
      if (seen.add(candidate.$2)) candidate.$2,
  ];

  // #region agent log
  final blockedOnSegment = <String>[];
  for (final vertexId in draftVertexIds) {
    final vertex = vertices[vertexId];
    if (vertex == null) continue;
    final toVertex = vertex.position - start;
    final t =
        (toVertex.dx * segment.dx + toVertex.dy * segment.dy) / lengthSquared;
    if (t <= 0 || t >= 1) continue;
    final projection = start + segment * t;
    if ((vertex.position - projection).distance <= tolerance) {
      blockedOnSegment.add(vertexId);
    }
  }
  debugPrint(
    '[TRACE_DEBUG] findVerticesAlongSegment '
    'Target Path: segment, '
    'Excluded: [${draftVertexIds.join(', ')}], '
    'DraftVerticesBlockedOnSegment: [${blockedOnSegment.join(', ')}], '
    'Result Path: [${result.join(' -> ')}]',
  );
  // #endregion

  return result;
}
