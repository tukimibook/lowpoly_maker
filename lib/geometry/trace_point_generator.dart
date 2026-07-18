import 'dart:ui';

/// Resamples a raw, freehand-traced path into points spaced evenly
/// [spacing] apart along its length — the vertex list [CanvasNotifier.
/// commitTraceStroke] turns into draft vertices for a "なぞりモード" stroke
/// (Phase F, `.cursor/plans/plan_phase_F.md`).
///
/// [rawPath] is whatever raw sequence of touch positions the gesture
/// reported (however densely — one point per `onPointerMove`, typically far
/// closer together than [spacing]); this walks its total arc length and
/// emits a point every [spacing] units, so the final vertex count depends
/// only on how far the finger travelled, never on how many raw samples the
/// platform happened to report. [rawPath]'s own first and last points are
/// always preserved exactly (even if the final segment between the last
/// even sample and the true end is shorter than [spacing]) so the stroke's
/// visible start/end are never rounded away.
///
/// Deliberately its own top-level pure function — like `edgeMidpoint`/
/// `findNearestPoint` — so it can be unit-tested with plain lists of
/// [Offset], with no `Artwork`/gesture/notifier setup at all, and reused
/// unchanged regardless of what eventually feeds it (a live single-finger
/// trace today; conceivably a smoothed/simplified path later).
///
/// Returns [rawPath] itself (a copy) when it has fewer than 2 points — there
/// is no length to resample. A single point among duplicates (zero-length
/// segments, e.g. the finger paused) is handled the same as any other
/// segment: they simply contribute no arc length, so no sample point ever
/// lands on them.
List<Offset> generateTracePoints(List<Offset> rawPath, {required double spacing}) {
  assert(spacing > 0, 'spacing must be positive');
  if (rawPath.length < 2) return List<Offset>.of(rawPath);

  final cumulative = <double>[0];
  for (var i = 1; i < rawPath.length; i++) {
    cumulative.add(cumulative.last + (rawPath[i] - rawPath[i - 1]).distance);
  }
  final totalLength = cumulative.last;
  if (totalLength == 0) return [rawPath.first];

  final result = <Offset>[rawPath.first];
  var segmentIndex = 1;
  var target = spacing;
  while (target < totalLength) {
    while (cumulative[segmentIndex] < target) {
      segmentIndex++;
    }
    final segmentStart = rawPath[segmentIndex - 1];
    final segmentEnd = rawPath[segmentIndex];
    final segmentStartDistance = cumulative[segmentIndex - 1];
    final segmentLength = cumulative[segmentIndex] - segmentStartDistance;
    final t = segmentLength == 0
        ? 0.0
        : (target - segmentStartDistance) / segmentLength;
    result.add(segmentStart + (segmentEnd - segmentStart) * t);
    target += spacing;
  }

  if (result.last != rawPath.last) {
    result.add(rawPath.last);
  }
  return result;
}
