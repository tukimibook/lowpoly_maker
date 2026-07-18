import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live single-finger なぞりモード ("trace mode") stroke preview (Phase F,
/// `.cursor/plans/plan_phase_F.md`) — the polyline traced out live between
/// touch-down and release, in *world* coordinates.
///
/// A plain [ChangeNotifier] wrapping a mutable [Path] rather than a
/// [ValueNotifier] holding an immutable value (unlike `DragPreview`/
/// `VertexDragPreview`/`PolygonDragPreview`): a trace stroke can accumulate
/// hundreds of points across a single gesture, and rebuilding an immutable
/// value (re-walking every prior point into a brand new [Path]) on every
/// single `onPointerMove` would be exactly the O(n)-per-frame repaint cost
/// the F-core design set out to avoid — appending one segment to the
/// existing [Path] with [Path.lineTo] is O(1) instead.
///
/// [rawPoints] mirrors the same points as plain [Offset]s (not derivable
/// from [path] itself, which offers no public way to read back the points
/// it holds) so the gesture handler can hand the raw trace to
/// `generateTracePoints`/`CanvasNotifier.commitTraceStroke` once the stroke
/// ends — see `.cursor/plans/plan_phase_F.md`'s F-core design.
class TraceStrokePreviewController extends ChangeNotifier {
  Path? _path;
  final List<Offset> _rawPoints = [];

  /// The live path, in world coordinates, for [PolygonPainter] to draw
  /// directly (translated/scaled exactly like every other canvas layer) —
  /// `null` between strokes.
  Path? get path => _path;

  /// A defensive copy of the points [path] traces so far, oldest first —
  /// `null` between strokes. Copied (rather than exposing the live list)
  /// since it's read exactly once, when a stroke ends, right before
  /// [clear] — the one-off `O(n)` copy costs nothing there, unlike doing
  /// it on every [lineTo].
  List<Offset>? get rawPoints => _path == null ? null : List.of(_rawPoints);

  /// Starts a brand new stroke at [point] (world coordinates), discarding
  /// any previous one.
  void start(Offset point) {
    _path = Path()..moveTo(point.dx, point.dy);
    _rawPoints
      ..clear()
      ..add(point);
    notifyListeners();
  }

  /// Extends the in-progress stroke to [point] (world coordinates). No-op
  /// if [start] hasn't been called since the last [clear].
  void lineTo(Offset point) {
    final path = _path;
    if (path == null) return;
    path.lineTo(point.dx, point.dy);
    _rawPoints.add(point);
    notifyListeners();
  }

  /// Discards the in-progress stroke (if any) without committing it.
  void clear() {
    if (_path == null) return;
    _path = null;
    _rawPoints.clear();
    notifyListeners();
  }
}

/// Provides the single, stable [TraceStrokePreviewController] instance for
/// the current editing session. Like `viewportProvider`, the provider
/// itself never changes value, so widgets that `watch` it (only to obtain
/// the controller) are not rebuilt when the stroke inside changes.
final traceStrokePreviewProvider = Provider<TraceStrokePreviewController>((ref) {
  final controller = TraceStrokePreviewController();
  ref.onDispose(controller.dispose);
  return controller;
});
