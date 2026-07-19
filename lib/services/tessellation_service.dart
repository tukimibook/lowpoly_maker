import 'dart:ui';

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

  /// Lower bound companion to [maxEdge] (see plan #20).
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

/// Top-level function passed to `compute()` (Phase G, plan #17). Must not
/// capture any outer state — it runs in a separate `Isolate` and must not
/// (and cannot) touch `Artwork`/`CanvasNotifier`/any Flutter engine object
/// other than plain [Offset] values.
///
/// Algorithm (to be implemented): constrained Delaunay triangulation of
/// [TessellationRequest.boundary] (G-spike Tier B, `delaunay` package) plus
/// a maxEdge-subdivision pass (jittered-midpoint re-triangulation — see
/// `test/spike_tessellation_test.dart`'s PoC). Left unimplemented for now;
/// wired end-to-end (Isolate dispatch, loading state, error handling) ahead
/// of the algorithm itself.
TessellationResult triangulate(TessellationRequest request) {
  throw UnimplementedError();
}
