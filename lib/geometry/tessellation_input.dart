import 'dart:ui';

import 'ring_collapse.dart';
import 'self_intersection.dart';
import '../models/vertex.dart';

/// Why [sanitizeTessellationBoundary] refused to accept a ring as
/// tessellation input.
enum TessellationRejectReason {
  /// Fewer than the minimum vertices remained after welding
  /// coincident-but-unwelded points and collapsing consecutive duplicates.
  tooFewVertices,

  /// The ring is self-intersecting — either two non-adjacent vertex IDs
  /// coincide (a "figure-8" weld) or two edges geometrically cross. Neither
  /// is safely auto-repairable (e.g. by splitting into two simple
  /// polygons), so this rejects rather than normalizes; see plan #7/#8.
  selfIntersecting,

  /// [sanitizeTessellationBoundary] passed, but the `compute()`-dispatched
  /// triangulation itself (`TessellationController.tessellate`, plan #17)
  /// threw. `Artwork` is left unchanged — nothing was committed — so the
  /// caller only needs to surface this to the user, not roll anything back.
  computeFailed,
}

/// Result of [sanitizeTessellationBoundary]: either a cleaned-up, safe-to-
/// triangulate ring of vertex IDs, or the reason it was rejected.
sealed class TessellationBoundaryResult {
  const TessellationBoundaryResult();
}

final class TessellationBoundaryOk extends TessellationBoundaryResult {
  const TessellationBoundaryOk(this.vertexIds);

  /// The (possibly welded/collapsed) ring, safe to hand to tessellation.
  final List<String> vertexIds;
}

final class TessellationBoundaryRejected extends TessellationBoundaryResult {
  const TessellationBoundaryRejected(this.reason);

  final TessellationRejectReason reason;
}

/// Rewrites [vertexIds] so that any ID sharing its *exact* position (see
/// [Vertex.position]) with an earlier ID in the same ring is replaced by
/// that earlier ID — collapsing "coincident-but-unwelded" points (e.g. from
/// `CanvasNotifier.moveVertex` dragging one vertex exactly onto another's
/// spot) into one genuinely shared corner. This is always safe: two points
/// at the exact same position already render identically, so merging their
/// IDs cannot change anything visually.
///
/// Pure with respect to its arguments; does not touch `Artwork` itself —
/// callers that want the weld to persist must still apply it via
/// `CanvasNotifier.weldVertices` or equivalent.
List<String> weldCoincidentRingVertices(
  List<String> vertexIds, {
  required Map<String, Vertex> vertices,
}) {
  final firstIdAtPosition = <Offset, String>{};
  return [
    for (final id in vertexIds)
      firstIdAtPosition.putIfAbsent(vertices[id]!.position, () => id),
  ];
}

/// Validates and normalizes a closed polygon ring before it is handed to
/// tessellation (Phase G).
///
/// - Coincident-but-unwelded vertices are welded ([weldCoincidentRingVertices])
///   and consecutive duplicates collapsed ([collapseConsecutiveRingIds]) —
///   both harmless normalizations.
/// - A ring left with fewer than [minVertices] points after that, a
///   non-consecutive duplicate ID ([hasNonConsecutiveDuplicate], e.g. a
///   diagonal weld pinching the ring into a bowtie), or a geometric edge
///   crossing ([isSelfIntersectingRing]) is rejected outright rather than
///   auto-repaired — see [TessellationRejectReason].
TessellationBoundaryResult sanitizeTessellationBoundary(
  List<String> vertexIds, {
  required Map<String, Vertex> vertices,
  int minVertices = 3,
}) {
  final welded = weldCoincidentRingVertices(vertexIds, vertices: vertices);
  final collapsed = collapseConsecutiveRingIds(welded);

  if (collapsed.length < minVertices) {
    return const TessellationBoundaryRejected(
      TessellationRejectReason.tooFewVertices,
    );
  }
  if (hasNonConsecutiveDuplicate(collapsed)) {
    return const TessellationBoundaryRejected(
      TessellationRejectReason.selfIntersecting,
    );
  }

  final points = [for (final id in collapsed) vertices[id]!.position];
  if (isSelfIntersectingRing(points)) {
    return const TessellationBoundaryRejected(
      TessellationRejectReason.selfIntersecting,
    );
  }

  return TessellationBoundaryOk(collapsed);
}
