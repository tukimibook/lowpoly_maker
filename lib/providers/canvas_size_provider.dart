import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks the current rendered size of the canvas widget, in world
/// coordinates (i.e. before `ViewportTransform`/pinch-zoom is applied to the
/// pixels an artist's finger actually touches).
///
/// Split out of `Artwork` (Phase Hγ, #9 — see `.cursor/plans/
/// plan_phase_H_gamma.md`): the rendered size is a device/layout fact, not
/// artwork geometry, so — like `UnderlayLayoutController` — it lives in its
/// own [ValueNotifier], entirely outside `CanvasNotifier`'s undo stack.
/// Keeping it there means an `undo()` call can never overwrite the screen's
/// *current* size with whatever stale size happened to be in effect when an
/// earlier edit was recorded (e.g. a device rotation, or a bottom-bar height
/// change between two edits).
class CanvasSizeController extends ValueNotifier<Size> {
  CanvasSizeController() : super(Size.zero);

  /// No-op if [size] already matches the current value — matches the
  /// previous `CanvasNotifier.setCanvasSize`'s guard, avoiding a needless
  /// notification (and dependent repaint/refit) every frame while the
  /// canvas's constraints are unchanged.
  void setSize(Size size) {
    if (value == size) return;
    value = size;
  }
}

/// Provides the single, stable [CanvasSizeController] instance for the
/// current editing session. Like `underlayLayoutProvider`/`viewportProvider`,
/// the provider itself never changes value, so widgets that `watch` it only
/// to obtain the controller are not rebuilt when the size inside changes.
final canvasSizeProvider = Provider<CanvasSizeController>((ref) {
  final controller = CanvasSizeController();
  ref.onDispose(controller.dispose);
  return controller;
});
