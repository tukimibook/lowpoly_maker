import 'dart:ui';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../geometry/polygon_containment.dart';
import '../geometry/tessellation_input.dart';
import '../services/tessellation_service.dart';
import 'canvas_provider.dart';

/// Whether a tessellation `compute()` call is currently in flight. UI reads
/// this to show a loading overlay and block further input (plan #17,
/// `_TessellationBlockingOverlay` in `screens/editor_screen.dart`).
///
/// Deliberately not part of `Artwork` — this is transient session state,
/// never undone/redone/persisted, exactly like `canvasModeProvider`/
/// `drawModeProvider` (`providers/canvas_provider.dart`).
final isTessellatingProvider = StateProvider<bool>((ref) => false);

/// Orchestrates one polygon's tessellation end-to-end: sanitize its
/// boundary ring, collect fully-contained hole rings from other polygons,
/// dispatch the heavy triangulation to a background `Isolate` via
/// `compute()`, and — on success — commit the result to [canvasProvider]
/// as a single undo entry. Kept separate from [CanvasNotifier] itself,
/// which stays `Ref`-free and limited to plain `Artwork` mutation.
class TessellationController {
  TessellationController(this._ref);

  final Ref _ref;

  /// Runs the full pipeline for [polygonId]. Returns `null` on success, or
  /// the [TessellationRejectReason] the caller should surface to the user
  /// otherwise. `Artwork` is left completely unchanged on any rejection —
  /// including [TessellationRejectReason.computeFailed], where the
  /// `Isolate` call threw.
  ///
  /// A call made while another is already in flight ([isTessellatingProvider]
  /// already `true`) is an immediate no-op (`null`), guarding against a
  /// double dispatch / double commit; the UI-level [AbsorbPointer] overlay
  /// is the primary defense, this is the last line of it.
  Future<TessellationRejectReason?> tessellate(
    String polygonId, {
    double maxEdge = kTessellationDefaultMaxEdge,
    double minEdge = kTessellationDefaultMinEdge,
  }) async {
    if (_ref.read(isTessellatingProvider)) return null;

    final artwork = _ref.read(canvasProvider);
    final polygon = artwork.polygons.where((p) => p.id == polygonId).firstOrNull;
    if (polygon == null) {
      return TessellationRejectReason.tooFewVertices;
    }

    final sanitized = sanitizeTessellationBoundary(
      polygon.vertexIds,
      vertices: artwork.vertices,
    );
    if (sanitized is TessellationBoundaryRejected) {
      return sanitized.reason;
    }
    final ring = (sanitized as TessellationBoundaryOk).vertexIds;
    final boundary = [for (final id in ring) artwork.vertices[id]!.position];

    // Fully-contained other polygons become holes. Partial overlaps are
    // skipped (fail-safe) — see [isRingFullyContained].
    final holeRings = <List<String>>[];
    final holeOffsets = <List<Offset>>[];
    for (final other in artwork.polygons) {
      if (other.id == polygonId) continue;
      final otherSanitized = sanitizeTessellationBoundary(
        other.vertexIds,
        vertices: artwork.vertices,
      );
      if (otherSanitized is! TessellationBoundaryOk) continue;
      final otherRing = otherSanitized.vertexIds;
      final otherBoundary = [
        for (final id in otherRing) artwork.vertices[id]!.position,
      ];
      if (!isRingFullyContained(outer: boundary, inner: otherBoundary)) {
        continue;
      }
      holeRings.add(otherRing);
      holeOffsets.add(otherBoundary);
    }

    _ref.read(isTessellatingProvider.notifier).state = true;
    try {
      final result = await compute(
        triangulate,
        TessellationRequest(
          boundary: boundary,
          holes: holeOffsets,
          maxEdge: maxEdge,
          minEdge: minEdge,
        ),
      );
      _ref
          .read(canvasProvider.notifier)
          .commitTessellationResult(
            polygonId: polygonId,
            boundaryRing: ring,
            holeRings: holeRings,
            result: result,
          );
      return null;
    } catch (_) {
      return TessellationRejectReason.computeFailed;
    } finally {
      _ref.read(isTessellatingProvider.notifier).state = false;
    }
  }
}

final tessellationControllerProvider = Provider<TessellationController>((ref) {
  return TessellationController(ref);
});
