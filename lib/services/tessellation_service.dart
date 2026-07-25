import 'dart:ui';

import '../geometry/poly2tri_adapter.dart';

/// Input to [triangulate], safe to pass across an `Isolate` boundary via
/// `compute()` — plain data only, no Flutter engine objects and no
/// closures. [boundary] must already be a validated, safe-to-triangulate
/// ring (see `geometry/tessellation_input.dart`'s `sanitizeTessellationBoundary`).
///
/// Optional [holes] are closed rings of polygons fully contained in
/// [boundary]; their interiors must not receive mesh triangles (true CDT
/// via vendored poly2tri).
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

  /// Target grid spacing for Steiner points (mesh density).
  final double maxEdge;

  /// Minimum spacing between Steiner points and existing vertices / other
  /// Steiners (also drives constraint-edge clearance).
  final double minEdge;
}

/// Output of [triangulate].
class TessellationResult {
  const TessellationResult({required this.points, required this.triangleIndices});

  /// Every point referenced by [triangleIndices], in this order:
  /// 1. [TessellationRequest.boundary] (unchanged, in order),
  /// 2. each hole ring from [TessellationRequest.holes] flattened in order,
  /// 3. any Steiner points introduced for density control.
  final List<Offset> points;

  /// Each triangle as a triple of indices into [points].
  final List<(int, int, int)> triangleIndices;
}

/// Safety valve retained for historical tuning / future iterative refine.
const int kTessellationMaxIterations = 10;

/// Historical jitter half-width from the old Delaunay midpoint refine path
/// (unused by the poly2tri Steiner-grid path).
const double kTessellationJitter = 1.0;

/// Tuned world-space defaults from the Phase G on-device visual tuning pass
/// (`test/geometry/tessellation_tuning_spike.dart`, iPhone14相当 390x844;
/// spike script and its outputs removed after tuning — see plan #20).
const double kTessellationDefaultMaxEdge = 150.0;
const double kTessellationDefaultMinEdge = 25.0;

/// Top-level function passed to `compute()` (Phase G, plan #17). Must not
/// capture any outer state — it runs in a separate `Isolate` and must not
/// (and cannot) touch `Artwork`/`CanvasNotifier`/any Flutter engine object
/// other than plain [Offset] values.
///
/// Algorithm: constrained Delaunay triangulation via vendored poly2tri,
/// with Steiner points on a [TessellationRequest.maxEdge]-spaced grid
/// filtered by [TessellationRequest.minEdge] and constraint clearance
/// ([runPoly2TriCdt]).
TessellationResult triangulate(TessellationRequest request) {
  final mesh = runPoly2TriCdt(
    boundary: request.boundary,
    holes: request.holes,
    maxEdge: request.maxEdge,
    minEdge: request.minEdge,
  );
  return TessellationResult(
    points: mesh.points,
    triangleIndices: mesh.triangleIndices,
  );
}
