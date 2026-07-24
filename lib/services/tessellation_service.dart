import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:delaunay/delaunay.dart';

import '../geometry/point_in_polygon.dart';
import '../geometry/self_intersection.dart';

/// Input to [triangulate], safe to pass across an `Isolate` boundary via
/// `compute()` — plain data only, no Flutter engine objects and no
/// closures. [boundary] must already be a validated, safe-to-triangulate
/// ring (see `geometry/tessellation_input.dart`'s `sanitizeTessellationBoundary`).
///
/// Optional [holes] are closed rings of polygons fully contained in
/// [boundary]; their interiors must not receive mesh triangles (Phase-1
/// hole MVP — unconstrained Delaunay plus exclusion filters, not a true
/// CDT library).
class TessellationRequest {
  const TessellationRequest({
    required this.boundary,
    required this.maxEdge,
    required this.minEdge,
    this.holes = const [],
  });

  /// Closed boundary ring in world coordinates, in order (last point
  /// implicitly connects back to the first).
  final List<Offset> boundary;

  /// Closed hole rings fully inside [boundary]. Empty when there are no
  /// contained shapes. Each ring is world-coordinate offsets in order.
  final List<List<Offset>> holes;

  /// Triangle edges longer than this are subdivided further.
  final double maxEdge;

  /// Lower bound companion to [maxEdge] (see plan #20). A subdivision that
  /// would leave either resulting half-edge shorter than this is skipped —
  /// see [triangulate]'s per-edge loop.
  final double minEdge;
}

/// Output of [triangulate].
class TessellationResult {
  const TessellationResult({required this.points, required this.triangleIndices});

  /// Every point referenced by [triangleIndices], in this order:
  /// 1. [TessellationRequest.boundary] (unchanged, in order),
  /// 2. each hole ring from [TessellationRequest.holes] flattened in order,
  /// 3. any Steiner / subdivision points introduced during meshing.
  final List<Offset> points;

  /// Each triangle as a triple of indices into [points].
  final List<(int, int, int)> triangleIndices;
}

/// Safety valve against runaway subdivision (e.g. a pathologically tiny
/// [TessellationRequest.maxEdge] relative to the boundary's own size):
/// [triangulate] re-triangulates at most this many times regardless of
/// whether every edge is within [TessellationRequest.maxEdge] yet. G-spike's
/// PoC (`test/spike_tessellation_test.dart`) converged well under this for
/// representative shapes.
const int kTessellationMaxIterations = 10;

/// Half-width of the random offset ([-kTessellationJitter, kTessellationJitter]
/// on each axis) added to a subdivision midpoint, so three exactly-collinear
/// points (the two original edge endpoints + their exact midpoint) never
/// hand the `delaunay` package a degenerate (zero-area) triangle that would
/// otherwise leave the very edge being subdivided intact — see G-spike's
/// "#20" finding, `test/spike_tessellation_test.dart`.
const double kTessellationJitter = 1.0;

/// Tuned world-space defaults from the Phase G on-device visual tuning pass
/// (`test/geometry/tessellation_tuning_spike.dart`, iPhone14相当 390x844;
/// spike script and its outputs removed after tuning — see plan #20). An
/// angle-based sliver-triangle filter was considered and rejected (risk of
/// unfixable slivers at inherently sharp input corners, and of infinite
/// retry loops) in favor of this simpler `minEdge` compromise.
const double kTessellationDefaultMaxEdge = 150.0;
const double kTessellationDefaultMinEdge = 25.0;

/// Top-level function passed to `compute()` (Phase G, plan #17). Must not
/// capture any outer state — it runs in a separate `Isolate` and must not
/// (and cannot) touch `Artwork`/`CanvasNotifier`/any Flutter engine object
/// other than plain [Offset] values.
///
/// Algorithm: unconstrained Delaunay triangulation of the current point
/// set (outer boundary + hole ring vertices + Steiner points), then keeps
/// only triangles whose centroid lies inside [TessellationRequest.boundary]
/// **and** outside every hole, and whose edges do not properly cross any
/// hole ring — then iteratively subdivides long edges (skipping midpoints
/// that fall inside a hole) until [maxEdge] / [minEdge] /
/// [kTessellationMaxIterations] stop the loop.
TessellationResult triangulate(TessellationRequest request) {
  final random = Random();
  final holes = request.holes;
  var points = <Offset>[
    ...request.boundary,
    for (final hole in holes) ...hole,
  ];
  var triangleIndices = const <(int, int, int)>[];

  for (var iteration = 0; iteration < kTessellationMaxIterations; iteration++) {
    final delaunay = Delaunay(_toFloat32List(points))..update();
    // Filter *before* the edge-subdivision pass: exterior / hole-filling
    // triangles must not fuel further midpoints.
    triangleIndices = _filterKeepTriangles(
      _groupTriangles(delaunay.triangles),
      points,
      request.boundary,
      holes,
    );

    final midpointsToAdd = <Offset>[];
    final processedEdges = <(int, int)>{};
    for (final triangle in triangleIndices) {
      for (final (i, j) in _edgesOf(triangle)) {
        final edgeKey = i < j ? (i, j) : (j, i);
        if (!processedEdges.add(edgeKey)) continue;

        final a = points[i];
        final b = points[j];
        final length = (a - b).distance;
        if (length <= request.maxEdge) continue;
        if (length / 2 < request.minEdge) continue;

        final midpoint = _jitteredMidpoint(a, b, random);
        // Hole interior is off-limits for Steiner points.
        if (_isInsideAnyHole(midpoint, holes)) continue;
        midpointsToAdd.add(midpoint);
      }
    }

    if (midpointsToAdd.isEmpty) break;
    points = [...points, ...midpointsToAdd];
  }

  return TessellationResult(points: points, triangleIndices: triangleIndices);
}

/// Keeps triangles in the annulus: inside [boundary], outside every hole,
/// and not straddling a hole via a proper edge/ring crossing.
List<(int, int, int)> _filterKeepTriangles(
  List<(int, int, int)> triangles,
  List<Offset> points,
  List<Offset> boundary,
  List<List<Offset>> holes,
) {
  return [
    for (final triangle in triangles)
      if (_shouldKeepTriangle(triangle, points, boundary, holes)) triangle,
  ];
}

bool _shouldKeepTriangle(
  (int, int, int) triangle,
  List<Offset> points,
  List<Offset> boundary,
  List<List<Offset>> holes,
) {
  final centroid = _centroid(points, triangle);
  if (!isPointInPolygon(centroid, boundary)) return false;
  if (_isInsideAnyHole(centroid, holes)) return false;
  if (_triangleEdgesProperlyCrossAnyHole(points, triangle, holes)) {
    return false;
  }
  return true;
}

bool _isInsideAnyHole(Offset point, List<List<Offset>> holes) {
  for (final hole in holes) {
    if (isPointInPolygon(point, hole)) return true;
  }
  return false;
}

bool _triangleEdgesProperlyCrossAnyHole(
  List<Offset> points,
  (int, int, int) triangle,
  List<List<Offset>> holes,
) {
  if (holes.isEmpty) return false;
  for (final (i, j) in _edgesOf(triangle)) {
    final a = points[i];
    final b = points[j];
    for (final hole in holes) {
      if (_segmentProperlyCrossesRing(a, b, hole)) return true;
    }
  }
  return false;
}

/// True when segment `a`-`b` properly crosses a ring edge (shared endpoints
/// with hole vertices are ignored so mesh edges that lie on the hole
/// boundary are allowed).
bool _segmentProperlyCrossesRing(Offset a, Offset b, List<Offset> ring) {
  for (var i = 0; i < ring.length; i++) {
    final c = ring[i];
    final d = ring[(i + 1) % ring.length];
    if (_samePoint(a, c) ||
        _samePoint(a, d) ||
        _samePoint(b, c) ||
        _samePoint(b, d)) {
      continue;
    }
    if (segmentsIntersect(a, b, c, d)) return true;
  }
  return false;
}

bool _samePoint(Offset p, Offset q) => p.dx == q.dx && p.dy == q.dy;

Offset _centroid(List<Offset> points, (int, int, int) triangle) {
  final (i, j, k) = triangle;
  final a = points[i];
  final b = points[j];
  final c = points[k];
  return Offset((a.dx + b.dx + c.dx) / 3, (a.dy + b.dy + c.dy) / 3);
}

/// Converts [points] into the flat `[x0, y0, x1, y1, ...]` layout the
/// `delaunay` package requires.
Float32List _toFloat32List(List<Offset> points) {
  final coords = Float32List(points.length * 2);
  for (var i = 0; i < points.length; i++) {
    coords[i * 2] = points[i].dx;
    coords[i * 2 + 1] = points[i].dy;
  }
  return coords;
}

/// Reads `delaunay.triangles`' flat vertex-index triples into groups of 3.
List<(int, int, int)> _groupTriangles(List<int> triangles) {
  assert(triangles.length % 3 == 0);
  return [
    for (var i = 0; i < triangles.length; i += 3)
      (triangles[i], triangles[i + 1], triangles[i + 2]),
  ];
}

/// The three (directed) edges of [triangle].
Iterable<(int, int)> _edgesOf((int, int, int) triangle) {
  final (a, b, c) = triangle;
  return [(a, b), (b, c), (c, a)];
}

/// [a] and [b]'s midpoint, offset by a small random jitter
/// ([-kTessellationJitter, kTessellationJitter] independently on each
/// axis) so it is never exactly collinear with [a] and [b] — see
/// [kTessellationJitter].
Offset _jitteredMidpoint(Offset a, Offset b, Random random) {
  double jitter() => (random.nextDouble() * 2 - 1) * kTessellationJitter;
  return Offset((a.dx + b.dx) / 2 + jitter(), (a.dy + b.dy) / 2 + jitter());
}
