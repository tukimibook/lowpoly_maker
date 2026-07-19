import 'dart:ui';

import 'nearest_point.dart';

/// Abstraction over "find the nearest indexed point to a query position,"
/// decoupled from *how* the candidate set is stored/searched. This lets
/// [CanvasNotifier] (`lib/providers/canvas_provider.dart`) swap the naive
/// O(n) linear scan below ([LinearVertexHitTest]) for a spatial index (grid
/// / quadtree) later without touching any call site — see
/// `.cursor/plans/plan_future_phases.md` #10.
abstract class VertexHitTest<T> {
  /// (Re)builds the searchable candidate set from scratch, replacing
  /// whatever was previously indexed. The O(n) implementation just stores
  /// the list (matching the per-call rebuild cost every existing call site
  /// already paid before this abstraction existed); a spatial-index
  /// implementation would rebuild its structure here instead.
  void rebuild(Iterable<PointCandidate<T>> candidates);

  /// Nearest candidate within [maxDistance] of [point], or null. Same
  /// contract as [findNearestPoint], including the [preferredId]
  /// exact-tie-break rule.
  PointCandidate<T>? nearest(
    Offset point, {
    required double maxDistance,
    T? preferredId,
  });
}

/// Current/default [VertexHitTest] implementation: a thin wrapper over
/// [findNearestPoint]'s plain O(n) linear scan. Sole implementation until a
/// spatial index is introduced; behavior is identical to the pre-
/// abstraction call sites it replaces.
class LinearVertexHitTest<T> implements VertexHitTest<T> {
  List<PointCandidate<T>> _candidates = const [];

  @override
  void rebuild(Iterable<PointCandidate<T>> candidates) {
    _candidates = candidates.toList(growable: false);
  }

  @override
  PointCandidate<T>? nearest(
    Offset point, {
    required double maxDistance,
    T? preferredId,
  }) {
    return findNearestPoint<T>(
      point,
      _candidates,
      maxDistance: maxDistance,
      preferredId: preferredId,
    );
  }
}
