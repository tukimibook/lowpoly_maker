import 'dart:math' as math;
import 'dart:ui';

import 'point_in_polygon.dart';
import 'vendor/poly2tri/poly2tri.dart';

/// Hard cap on accepted Steiner points (pathological tiny [maxEdge]).
const int kPoly2TriMaxSteinerPoints = 5000;

/// Half-width of the collinear-avoidance jitter applied only to edge-split
/// insert points (±world units). Kept invisible; never applied to original
/// contour vertices.
const double kEdgeSplitCollinearJitterHalf = 0.01;

/// Visual Steiner jitter amplitude as a fraction of [minEdge]
/// (`halfWidth = minEdge * this`).
const double kSteinerVisualJitterFactor = 0.4;

/// Constrained Delaunay mesh from an outer [boundary] and optional [holes],
/// with edge-splitting and optional Steiner points for mesh density.
///
/// Pipeline:
/// 1. Split long constrained edges (micro-jitter on inserts only)
/// 2. Build poly2tri [CDT] from the split rings
/// 3. Place jittered Steiner grid points, keep only safe candidates
/// 4. [CDT.triangulate]
///
/// Returned [points] follow contract order:
/// original [boundary] → flattened original [holes] → edge-split inserts →
/// interior Steiners. Triangle indices prefer the first slot that mapped to
/// each [P2tPoint] (identity map via coordinate merge within [kP2tEpsilon]).
({List<Offset> points, List<(int, int, int)> triangleIndices}) runPoly2TriCdt({
  required List<Offset> boundary,
  List<List<Offset>> holes = const [],
  double maxEdge = double.infinity,
  double minEdge = 0,
  math.Random? random,
}) {
  if (boundary.length < 3) {
    throw ArgumentError.value(
      boundary.length,
      'boundary',
      'needs at least 3 vertices',
    );
  }

  final rng = random ?? math.Random();

  final splitBoundary = splitRingEdges(
    boundary,
    maxEdge: maxEdge,
    random: rng,
  );
  final splitHoles = <List<Offset>>[
    for (final hole in holes)
      if (hole.length >= 3)
        splitRingEdges(hole, maxEdge: maxEdge, random: rng),
  ];

  final edgeSplitInsertsOrdered = <Offset>[
    ...collectEdgeSplitInserts(
      originalRing: boundary,
      splitRing: splitBoundary,
    ),
    for (var hi = 0, si = 0; hi < holes.length; hi++)
      if (holes[hi].length >= 3) ...[
        ...collectEdgeSplitInserts(
          originalRing: holes[hi],
          splitRing: splitHoles[si++],
        ),
      ],
  ];

  final cache = _P2tPointCache();
  final contour = <P2tPoint>[
    for (final o in splitBoundary) cache.getOrCreate(o),
  ];

  final cdt = CDT(contour);
  for (final hole in splitHoles) {
    cdt.addHole([for (final o in hole) cache.getOrCreate(o)]);
  }

  final originalVerts = <Offset>[
    ...boundary,
    for (final hole in holes) ...hole,
  ];
  final constraintEdges = <(Offset, Offset)>[
    ..._ringEdges(splitBoundary),
    for (final hole in splitHoles) ..._ringEdges(hole),
  ];

  final steinerExisting = <Offset>[
    ...originalVerts,
    ...edgeSplitInsertsOrdered,
  ];

  final steiners = generateJitteredSteinerPoints(
    boundary: splitBoundary,
    holes: splitHoles,
    existingVertices: steinerExisting,
    constraintEdges: constraintEdges,
    maxEdge: maxEdge,
    minEdge: minEdge,
    random: rng,
  );

  for (final s in steiners) {
    cdt.addPoint(cache.getOrCreate(s));
  }

  cdt.triangulate();

  final points = <Offset>[
    ...originalVerts,
    ...edgeSplitInsertsOrdered,
    ...steiners,
  ];

  final firstIndex = <P2tPoint, int>{};
  var slot = 0;
  for (final o in points) {
    firstIndex.putIfAbsent(cache.getOrCreate(o), () => slot);
    slot++;
  }

  final triangleIndices = <(int, int, int)>[
    for (final t in cdt.getTriangles())
      (
        firstIndex[t.getPoint(0)]!,
        firstIndex[t.getPoint(1)]!,
        firstIndex[t.getPoint(2)]!,
      ),
  ];

  return (points: points, triangleIndices: triangleIndices);
}

/// Splits each edge of a closed [ring] into segments of length ≤ [maxEdge].
///
/// Original vertices are returned unchanged (same [Offset] instances).
/// Inserted points receive only [kEdgeSplitCollinearJitterHalf] jitter.
List<Offset> splitRingEdges(
  List<Offset> ring, {
  required double maxEdge,
  required math.Random random,
  double collinearJitterHalf = kEdgeSplitCollinearJitterHalf,
}) {
  if (ring.length < 2 || !(maxEdge > 0) || !maxEdge.isFinite) {
    return List<Offset>.of(ring);
  }

  final out = <Offset>[];
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    out.add(a);

    final length = (b - a).distance;
    if (length <= maxEdge) continue;

    final segments = (length / maxEdge).ceil();
    for (var s = 1; s < segments; s++) {
      final t = s / segments;
      final mid = Offset(
        a.dx + (b.dx - a.dx) * t,
        a.dy + (b.dy - a.dy) * t,
      );
      out.add(applyAxisJitter(mid, random, collinearJitterHalf));
    }
  }
  return out;
}

/// Points in [splitRing] that were not original vertices of [originalRing]
/// (by reference identity).
List<Offset> collectEdgeSplitInserts({
  required List<Offset> originalRing,
  required List<Offset> splitRing,
}) {
  return [
    for (final p in splitRing)
      if (!_isOriginalVertex(p, originalRing)) p,
  ];
}

bool _isOriginalVertex(Offset p, List<Offset> originalRing) {
  for (final o in originalRing) {
    if (identical(p, o)) return true;
  }
  return false;
}

/// Axis-aligned jitter: each axis independently uniform in `[-halfWidth, halfWidth]`.
Offset applyAxisJitter(Offset p, math.Random random, double halfWidth) {
  if (halfWidth <= 0) return p;
  double j() => (random.nextDouble() * 2 - 1) * halfWidth;
  return Offset(p.dx + j(), p.dy + j());
}

/// True when [p] is strictly inside [boundary], outside every hole, and at
/// least [minEdge] from all [existing] vertices and [constraintEdges].
bool isSafeSteinerCandidate(
  Offset p, {
  required List<Offset> boundary,
  required List<List<Offset>> holes,
  required List<Offset> existing,
  required List<(Offset, Offset)> constraintEdges,
  required double minEdge,
}) {
  if (!isPointInPolygon(p, boundary)) return false;
  if (_isInsideAnyHole(p, holes)) return false;

  final minDist = math.max(0.0, minEdge);
  if (minDist > 0) {
    final minDistSq = minDist * minDist;
    if (_tooCloseToAny(p, existing, minDistSq)) return false;
    if (_tooCloseToConstraints(p, constraintEdges, minDist)) return false;
  }
  return true;
}

/// Grid Steiner points with visual jitter; only [isSafeSteinerCandidate] pass.
List<Offset> generateJitteredSteinerPoints({
  required List<Offset> boundary,
  required List<List<Offset>> holes,
  required List<Offset> existingVertices,
  required List<(Offset, Offset)> constraintEdges,
  required double maxEdge,
  required double minEdge,
  required math.Random random,
  double visualJitterFactor = kSteinerVisualJitterFactor,
}) {
  if (!(maxEdge > 0) || !maxEdge.isFinite || boundary.isEmpty) {
    return const [];
  }

  var xmin = boundary[0].dx;
  var xmax = boundary[0].dx;
  var ymin = boundary[0].dy;
  var ymax = boundary[0].dy;
  for (final p in boundary) {
    if (p.dx < xmin) xmin = p.dx;
    if (p.dx > xmax) xmax = p.dx;
    if (p.dy < ymin) ymin = p.dy;
    if (p.dy > ymax) ymax = p.dy;
  }

  final step = maxEdge;
  final jitterHalf = math.max(0.0, minEdge) * visualJitterFactor;
  final accepted = <Offset>[];
  final acceptedAndExisting = List<Offset>.of(existingVertices);

  for (var x = xmin + step; x < xmax - kP2tEpsilon; x += step) {
    for (var y = ymin + step; y < ymax - kP2tEpsilon; y += step) {
      if (accepted.length >= kPoly2TriMaxSteinerPoints) {
        return accepted;
      }

      final jittered = applyAxisJitter(Offset(x, y), random, jitterHalf);
      if (!isSafeSteinerCandidate(
        jittered,
        boundary: boundary,
        holes: holes,
        existing: acceptedAndExisting,
        constraintEdges: constraintEdges,
        minEdge: minEdge,
      )) {
        continue;
      }

      accepted.add(jittered);
      acceptedAndExisting.add(jittered);
    }
  }

  return accepted;
}

List<(Offset, Offset)> _ringEdges(List<Offset> ring) {
  if (ring.length < 2) return const [];
  return [
    for (var i = 0; i < ring.length; i++)
      (ring[i], ring[(i + 1) % ring.length]),
  ];
}

bool _isInsideAnyHole(Offset point, List<List<Offset>> holes) {
  for (final hole in holes) {
    if (isPointInPolygon(point, hole)) return true;
  }
  return false;
}

bool _tooCloseToAny(Offset p, List<Offset> others, double minDistSq) {
  if (minDistSq <= 0) return false;
  for (final o in others) {
    final dx = p.dx - o.dx;
    final dy = p.dy - o.dy;
    if (dx * dx + dy * dy < minDistSq) return true;
  }
  return false;
}

bool _tooCloseToConstraints(
  Offset p,
  List<(Offset, Offset)> edges,
  double clearance,
) {
  if (clearance <= 0) return false;
  final clearanceSq = clearance * clearance;
  for (final (a, b) in edges) {
    if (_distanceToSegmentSquared(p, a, b) < clearanceSq) return true;
  }
  return false;
}

double _distanceToSegmentSquared(Offset p, Offset a, Offset b) {
  final abx = b.dx - a.dx;
  final aby = b.dy - a.dy;
  final len2 = abx * abx + aby * aby;
  if (len2 == 0) {
    final dx = p.dx - a.dx;
    final dy = p.dy - a.dy;
    return dx * dx + dy * dy;
  }
  var t = ((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / len2;
  if (t < 0) {
    t = 0;
  } else if (t > 1) {
    t = 1;
  }
  final projX = a.dx + t * abx;
  final projY = a.dy + t * aby;
  final dx = p.dx - projX;
  final dy = p.dy - projY;
  return dx * dx + dy * dy;
}

/// Merges near-equal [Offset]s onto a single [P2tPoint] (reference reuse).
class _P2tPointCache {
  final List<P2tPoint> _points = <P2tPoint>[];

  P2tPoint getOrCreate(Offset offset) {
    final x = offset.dx;
    final y = offset.dy;
    for (final p in _points) {
      if ((p.x - x).abs() <= kP2tEpsilon && (p.y - y).abs() <= kP2tEpsilon) {
        return p;
      }
    }
    final created = P2tPoint(x, y);
    _points.add(created);
    return created;
  }
}
