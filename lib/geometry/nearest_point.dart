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
/// empty. When multiple candidates are equally close, [preferredId] — if
/// given and one of the tied candidates — wins; otherwise the last one
/// encountered in iteration order wins, exactly as before [preferredId]
/// existed.
///
/// [preferredId] exists for exact-coincidence ties specifically — e.g. a
/// vertex just detached (`CanvasNotifier.detachVertexFromPolygon`) sits at
/// the *exact same* [Offset] as the original it was copied from, so a
/// later hit-test at that same spot is genuinely ambiguous between the two.
/// Passing whichever vertex the artist was already engaged with (typically
/// `selectedVertexProvider`'s current value) resolves that ambiguity in
/// the direction the artist actually intended, rather than by whatever
/// order the candidates happened to be produced in — see
/// `.cursor/plans/plan_phase_H_alpha.md`, 2026-07-16 検討メモ, for the bug
/// this was added to fix (a detach immediately followed by a long-press
/// drag could grab the wrong one of the two coincident vertices, purely
/// because of `Artwork.polygons`' list order).
PointCandidate<T>? findNearestPoint<T>(
  Offset point,
  Iterable<PointCandidate<T>> candidates, {
  required double maxDistance,
  T? preferredId,
}) {
  PointCandidate<T>? closest;
  var closestDistance = maxDistance;
  for (final candidate in candidates) {
    final distance = (candidate.$2 - point).distance;
    if (distance > closestDistance) continue;
    if (closest == null || distance < closestDistance) {
      closest = candidate;
      closestDistance = distance;
    } else {
      // An exact tie against the current best (distance == closestDistance):
      // prefer `preferredId` if it's involved, otherwise keep the
      // pre-existing "last one wins" behavior.
      if (candidate.$1 == preferredId || closest.$1 != preferredId) {
        closest = candidate;
      }
    }
  }
  return closest;
}
