import 'dart:ui';

/// A candidate point paired with an identifier of type [T].
///
/// This is the only vocabulary [findNearestPoint] speaks: plain points and
/// opaque identifiers. It has no notion of vertices, polygons, or artwork,
/// so it can be reused by any feature that boils down to "what's the
/// closest point to here" — vertex snapping today; future features like
/// self-intersection cleanup or auto-subdivision can reuse the exact same
/// primitive without depending on the canvas/state layer at all.
typedef PointCandidate<T> = (T id, Offset position);

/// Finds the entry in [candidates] whose position is closest to [point],
/// as long as that distance is no more than [maxDistance].
///
/// Returns null if no candidate qualifies, including when [candidates] is
/// empty. When multiple candidates are equally close, the last one
/// encountered in iteration order wins.
PointCandidate<T>? findNearestPoint<T>(
  Offset point,
  Iterable<PointCandidate<T>> candidates, {
  required double maxDistance,
}) {
  PointCandidate<T>? closest;
  var closestDistance = maxDistance;
  for (final candidate in candidates) {
    final distance = (candidate.$2 - point).distance;
    if (distance <= closestDistance) {
      closestDistance = distance;
      closest = candidate;
    }
  }
  return closest;
}
