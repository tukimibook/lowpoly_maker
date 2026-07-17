import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/coordinate_transform.dart';

/// Snapshot taken at the start of every gesture *sub-cycle* on
/// `PolygonCanvas` — every time `onScaleStart` fires, including the extra
/// `onEnd`+`onStart` pair Flutter's own `ScaleGestureRecognizer`
/// synthesizes whenever the number of fingers down changes mid-gesture
/// (see that class's `_reconfigure`: it always re-baselines its `scale`/
/// `focalPoint` to the fresh pointer count, then — if a gesture had
/// already started — closes it with `onEnd` and reopens a fresh `onStart`
/// right after, both perfectly back-to-back with no other event in
/// between). Phase Hβ (`.cursor/plans/plan_phase_H_beta.md`).
///
/// This is what lets `PolygonCanvas` answer, with no manual jump-avoidance
/// math of its own:
/// - *(inside `onScaleUpdate`)* "what did the viewport look like, and
///   where were the fingers, right when the currently-active sub-cycle
///   began?" — [transform]/[focalPoint], fed into
///   `applyPinchPan` (`geometry/viewport_pinch.dart`).
/// - *(inside `onScaleEnd`)* "was the sub-cycle that just ended, and every
///   one before it in this same physical gesture, always a single finger —
///   so the mode's own draw/erase/drag action should commit — or did a
///   second finger ever join (even one that has since lifted again),
///   meaning only the viewport ever moved, not the artwork, and the
///   mode's own in-flight preview must be discarded rather than
///   committed?" — [pointerCount]/[hadMultiFinger].
///
/// [hadMultiFinger] is deliberately sticky across an entire physical
/// gesture (reset only once every finger has actually lifted, not at
/// every intermediate `onEnd`/`onStart` re-pairing): once a pinch has
/// started, releasing one finger before the other must not suddenly
/// resume single-finger drawing/dragging with whichever finger is still
/// down — the artist is still in the middle of finishing that pinch, not
/// starting a new, unrelated single-finger action.
@immutable
class ViewportGestureBaseline {
  const ViewportGestureBaseline({
    required this.pointerCount,
    required this.transform,
    required this.focalPoint,
    required this.hadMultiFinger,
  });

  final int pointerCount;
  final ViewportTransform transform;
  final Offset focalPoint;
  final bool hadMultiFinger;
}

/// Tracks the current [ViewportGestureBaseline] while any gesture is active
/// on `PolygonCanvas` (in any of the three modes), or `null` between
/// gestures. A [ValueNotifier] rather than Riverpod state, matching
/// `DragPreviewController`/`VertexDragPreviewController`/
/// `PolygonDragPreviewController` — this is transient per-gesture
/// bookkeeping, not artwork or even viewport data, so nothing should ever
/// rebuild off it.
class ViewportGestureController extends ValueNotifier<ViewportGestureBaseline?> {
  ViewportGestureController() : super(null);
}

/// Provides the single, stable [ViewportGestureController] instance for the
/// current editing session. Like `viewportProvider`, the provider itself
/// never changes value, so widgets that `watch` it (only to obtain the
/// controller) are not rebuilt when the baseline inside changes.
final viewportGestureProvider = Provider<ViewportGestureController>((ref) {
  final controller = ViewportGestureController();
  ref.onDispose(controller.dispose);
  return controller;
});
