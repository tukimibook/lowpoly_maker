import 'dart:math' as math;
import 'dart:ui';

import 'point_in_polygon.dart';
import 'vendor/poly2tri/poly2tri.dart';

/// Hard cap on accepted Steiner points (pathological tiny [maxEdge]).
const int kPoly2TriMaxSteinerPoints = 5000;

/// Constrained Delaunay mesh from an outer [boundary] and optional [holes],
/// with optional Steiner points for mesh density control.
///
/// Used by `tessellation_service.triangulate` to bridge
/// `TessellationRequest` ↔ vendored poly2tri [CDT].
///
/// Steiner candidates are placed on a [maxEdge]-spaced axis-aligned grid
/// over the boundary AABB, then filtered for:
/// - strict interior of [boundary] and exterior of every hole
/// - clearance ≥ [minEdge] from existing vertices and other Steiners
/// - clearance from constrained segments (see [_constraintClearance])
///
/// Duplicate / near-duplicate coordinates (within [kP2tEpsilon]) share one
/// [P2tPoint]. Returned [points] follow contract order: [boundary], flattened
/// [holes], then accepted Steiner [Offset]s. Triangle indices prefer the
/// first slot that mapped to each [P2tPoint].
({List<Offset> points, List<(int, int, int)> triangleIndices}) runPoly2TriCdt({
  required List<Offset> boundary,
  List<List<Offset>> holes = const [],
  double maxEdge = double.infinity,
  double minEdge = 0,
}) {
  if (boundary.length < 3) {
    throw ArgumentError.value(
      boundary.length,
      'boundary',
      'needs at least 3 vertices',
    );
  }

  final cache = _P2tPointCache();
  final contour = <P2tPoint>[
    for (final o in boundary) cache.getOrCreate(o),
  ];

  final cdt = CDT(contour);
  for (final hole in holes) {
    if (hole.length < 3) continue;
    cdt.addHole([for (final o in hole) cache.getOrCreate(o)]);
  }

  final existing = <Offset>[
    ...boundary,
    for (final hole in holes) ...hole,
  ];
  final constraintEdges = <(Offset, Offset)>[
    ..._ringEdges(boundary),
    for (final hole in holes) ..._ringEdges(hole),
  ];

  final steiners = _generateSteinerPoints(
    boundary: boundary,
    holes: holes,
    existing: existing,
    constraintEdges: constraintEdges,
    maxEdge: maxEdge,
    minEdge: minEdge,
  );

  for (final s in steiners) {
    cdt.addPoint(cache.getOrCreate(s));
  }

  cdt.triangulate();

  final points = <Offset>[...existing, ...steiners];

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

List<(Offset, Offset)> _ringEdges(List<Offset> ring) {
  if (ring.length < 2) return const [];
  return [
    for (var i = 0; i < ring.length; i++)
      (ring[i], ring[(i + 1) % ring.length]),
  ];
}

/// Clearance from constrained segments. Floored by [kP2tEpsilon]; scaled
/// with [minEdge] so near-edge Steiners that destabilize poly2tri are dropped.
double _constraintClearance(double minEdge) =>
    math.max(kP2tEpsilon, minEdge * 0.25);

List<Offset> _generateSteinerPoints({
  required List<Offset> boundary,
  required List<List<Offset>> holes,
  required List<Offset> existing,
  required List<(Offset, Offset)> constraintEdges,
  required double maxEdge,
  required double minEdge,
}) {
  if (!(maxEdge > 0) || !maxEdge.isFinite) return const [];

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
  final edgeClearance = _constraintClearance(minEdge);
  final minDist = math.max(0.0, minEdge);
  final minDistSq = minDist * minDist;

  final accepted = <Offset>[];
  final acceptedAndExisting = List<Offset>.of(existing);

  // Grid strictly inside the AABB (never on the bbox corners / rim).
  for (var x = xmin + step; x < xmax - kP2tEpsilon; x += step) {
    for (var y = ymin + step; y < ymax - kP2tEpsilon; y += step) {
      if (accepted.length >= kPoly2TriMaxSteinerPoints) {
        return accepted;
      }

      final candidate = Offset(x, y);

      if (!isPointInPolygon(candidate, boundary)) continue;
      if (_isInsideAnyHole(candidate, holes)) continue;

      if (_tooCloseToAny(candidate, acceptedAndExisting, minDistSq)) {
        continue;
      }

      if (_tooCloseToConstraints(candidate, constraintEdges, edgeClearance)) {
        continue;
      }

      accepted.add(candidate);
      acceptedAndExisting.add(candidate);
    }
  }

  return accepted;
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
