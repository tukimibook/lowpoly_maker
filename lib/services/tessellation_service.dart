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

  /// Target edge / grid spacing for edge-splitting and Steiner density.
  final double maxEdge;

  /// Minimum spacing for Steiner safety filters (ratio-linked to [maxEdge]
  /// when using [kTessellationDefaultMinEdge]).
  final double minEdge;
}

/// Output of [triangulate].
class TessellationResult {
  const TessellationResult({required this.points, required this.triangleIndices});

  /// Every point referenced by [triangleIndices], in this order:
  /// 1. [TessellationRequest.boundary] (unchanged, in order),
  /// 2. each hole ring from [TessellationRequest.holes] flattened in order,
  /// 3. edge-split insert points (new vertices on long constrained edges),
  /// 4. interior Steiner points (density control).
  ///
  /// Steps 3–4 are minted as fresh vertices by
  /// `CanvasNotifier.commitTessellationResult`.
  final List<Offset> points;

  /// Each triangle as a triple of indices into [points].
  final List<(int, int, int)> triangleIndices;
}

/// Safety valve retained for historical tuning / future iterative refine.
const int kTessellationMaxIterations = 10;

/// Primary density parameter (world units). Look-tuned default.
const double kTessellationDefaultMaxEdge = 120.0;

/// [kTessellationDefaultMaxEdge] に対する minEdge の比率（max : min = ratio : 1）。
const double kTessellationMinToMaxEdgeRatio = 8.0;

/// Secondary spacing parameter, ratio-linked to [kTessellationDefaultMaxEdge]
/// as `maxEdge / [kTessellationMinToMaxEdgeRatio]` (1:8). Changing the primary
/// default scales this automatically for UX tuning.
const double kTessellationDefaultMinEdge =
    kTessellationDefaultMaxEdge / kTessellationMinToMaxEdgeRatio;

/// Top-level function passed to `compute()` (Phase G, plan #17). Must not
/// capture any outer state — it runs in a separate `Isolate` and must not
/// (and cannot) touch `Artwork`/`CanvasNotifier`/any Flutter engine object
/// other than plain [Offset] values.
///
/// Algorithm: poly2tri CDT with contour edge-splitting, then jittered
/// Steiner points filtered by [TessellationRequest.minEdge]
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
