import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/underlay_layout.dart';

/// The opacity steps [UnderlayLayoutController.cycleOpacity] loops through,
/// in order. Replaces the five-segment button the "下絵設定" bottom sheet
/// used to offer (removed 2026-07-16 — see `.cursor/plans/
/// plan_phase_H_alpha.md`) with a single icon-only toggle in the toolbar's
/// common row, so the control stays language-independent (a numeral + `%`
/// is a universal symbol, not a translated word).
const List<double> kUnderlayOpacitySteps = [0.0, 0.25, 0.5, 0.75, 1.0];

/// Tracks the current [UnderlayLayout] for the (single, v1) underlay photo.
///
/// A [ValueNotifier] — like `ViewportController`/`DragPreviewController` in
/// their respective provider files — so a `CustomPainter` can subscribe
/// directly via `repaint` and redraw without the surrounding widget tree
/// rebuilding. v1 only ever writes to this from [setLayout] (the
/// fit-to-canvas result, applied by `underlayFitCoordinatorProvider`) and
/// from the settings bottom sheet's [setVisible]/[setOpacity] — never from
/// a per-frame gesture — but using the same `ValueNotifier` pattern as the
/// rest of the canvas's session state avoids a special case, and leaves
/// room for a future pinch/pan gesture to write here too without changing
/// this file.
///
/// Deliberately outside `CanvasNotifier`/`Artwork`'s undo stack: underlay
/// placement is presentation, not artwork geometry (matches the
/// already-agreed "Undo は幾何のみ" rule — see 「コード品質・修正前提」#9 in
/// `.cursor/plans/plan_future_phases.md`).
class UnderlayLayoutController extends ValueNotifier<UnderlayLayout> {
  UnderlayLayoutController() : super(UnderlayLayout.initial);

  /// Replaces the whole layout — used by the fit-to-canvas result.
  void setLayout(UnderlayLayout layout) => value = layout;

  void setVisible(bool visible) => value = value.copyWith(visible: visible);

  void setOpacity(double opacity) => value = value.copyWith(opacity: opacity);

  /// Advances [UnderlayLayout.opacity] to the next step in
  /// [kUnderlayOpacitySteps], wrapping back to the first after the last —
  /// the toolbar's single "💧 NN%" toggle button, replacing the old
  /// five-segment picker with one tap that loops through every step.
  ///
  /// Snaps to the *nearest* step first (rather than requiring an exact
  /// match) before advancing, so a stray future writer or floating-point
  /// rounding can't leave this stuck between two steps.
  void cycleOpacity() {
    final steps = kUnderlayOpacitySteps;
    var nearestIndex = 0;
    for (var i = 1; i < steps.length; i++) {
      if ((steps[i] - value.opacity).abs() < (steps[nearestIndex] - value.opacity).abs()) {
        nearestIndex = i;
      }
    }
    setOpacity(steps[(nearestIndex + 1) % steps.length]);
  }
}

/// Provides the single, stable [UnderlayLayoutController] instance for the
/// current editing session. Like `viewportProvider`, the provider itself
/// never changes value, so widgets that `watch` it (only to obtain the
/// controller) are not rebuilt when the layout inside changes.
final underlayLayoutProvider = Provider<UnderlayLayoutController>((ref) {
  final controller = UnderlayLayoutController();
  ref.onDispose(controller.dispose);
  return controller;
});
