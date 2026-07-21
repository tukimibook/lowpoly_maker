import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:delaunay/delaunay.dart';

import '../geometry/point_in_polygon.dart';

/// Input to [triangulate], safe to pass across an `Isolate` boundary via
/// `compute()` — plain data only, no Flutter engine objects and no
/// closures. [boundary] must already be a validated, safe-to-triangulate
/// ring (see `geometry/tessellation_input.dart`'s `sanitizeTessellationBoundary`).
class TessellationRequest {
  const TessellationRequest({
    required this.boundary,
    required this.maxEdge,
    required this.minEdge,
  });

  /// Closed boundary ring in world coordinates, in order (last point
  /// implicitly connects back to the first).
  final List<Offset> boundary;

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

  /// Every point referenced by [triangleIndices]: [TessellationRequest.boundary]
  /// first, in the same order, followed by any interior/subdivision points
  /// introduced during meshing.
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
/// set (G-spike Tier B, `delaunay` package — which always fills the
/// convex hull, not a constrained polygon interior), then **discards any
/// triangle whose centroid falls outside [TessellationRequest.boundary]**
/// via [isPointInPolygon] (so concave rings do not keep the convex-hull
/// "gap" triangles), then iteratively subdivides every remaining triangle
/// edge longer than [TessellationRequest.maxEdge] by inserting a jittered
/// midpoint and re-triangulating, until either no edge exceeds
/// [TessellationRequest.maxEdge] or [kTessellationMaxIterations] is
/// reached. An edge is left un-subdivided once splitting it would leave
/// either half shorter than [TessellationRequest.minEdge], even if it is
/// still longer than [TessellationRequest.maxEdge] — this is what actually
/// stops the loop for small/oddly-shaped input instead of subdividing
/// forever.
///
/// The Point-in-Polygon filter runs *inside* this function (already
/// dispatched via `compute()`), never as a second Isolate hop and never
/// on the UI thread — see defect-fix #3.
TessellationResult triangulate(TessellationRequest request) {
  final random = Random();
  var points = List<Offset>.of(request.boundary);
  var triangleIndices = const <(int, int, int)>[];

  for (var iteration = 0; iteration < kTessellationMaxIterations; iteration++) {
    final delaunay = Delaunay(_toFloat32List(points))..update();
    // Filter *before* the edge-subdivision pass: exterior (convex-hull
    // gap) triangles must not fuel further midpoints, or the next
    // iteration just recreates more exterior triangles.
    triangleIndices = _filterInteriorTriangles(
      _groupTriangles(delaunay.triangles),
      points,
      request.boundary,
    );

    final midpointsToAdd = <Offset>[];
    final processedEdges = <(int, int)>{};
    for (final triangle in triangleIndices) {
      for (final (i, j) in _edgesOf(triangle)) {
        final edgeKey = i < j ? (i, j) : (j, i);
        if (!processedEdges.add(edgeKey)) continue; // shared with a neighboring triangle

        final a = points[i];
        final b = points[j];
        final length = (a - b).distance;
        if (length <= request.maxEdge) continue;
        if (length / 2 < request.minEdge) continue; // would over-shrink the halves

        midpointsToAdd.add(_jitteredMidpoint(a, b, random));
      }
    }

    if (midpointsToAdd.isEmpty) break;
    points = [...points, ...midpointsToAdd];
  }

  return TessellationResult(points: points, triangleIndices: triangleIndices);
}

/// Keeps only those [triangles] whose centroid lies inside [boundary]
/// (the artist's original ring). Dropped triangles are the unconstrained
/// Delaunay fill of the convex-hull gaps outside a concave polygon.
List<(int, int, int)> _filterInteriorTriangles(
  List<(int, int, int)> triangles,
  List<Offset> points,
  List<Offset> boundary,
) {
  return [
    for (final triangle in triangles)
      if (isPointInPolygon(_centroid(points, triangle), boundary)) triangle,
  ];
}

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
