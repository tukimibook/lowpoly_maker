import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live shade multi-selection: polygon ids touched by the select brush.
///
/// A [ValueNotifier] (like `DragPreviewController`) rather than Riverpod
/// [StateProvider], so [PolygonCanvas] can call [add] / [remove] on every
/// `onScaleUpdate` (~60/sec) without rebuilding the widget tree, and only
/// [PolygonPainter] — which listens to this as a `repaint` source —
/// repaints when membership changes.
///
/// Stroke polarity (Phase Select / Wave 3.2.1): the canvas locks Add vs
/// Remove for the whole stroke from the **first hit**; blank starts stay
/// undecided until a polygon is hit. [clear] empties the set (toolbar
/// deselect-all / mode / artwork session reset).
class SelectionDragController extends ValueNotifier<Set<String>> {
  SelectionDragController() : super(const {});

  /// Adds [polygonId] if absent. Returns `true` when membership changed
  /// (and listeners were notified).
  bool add(String polygonId) {
    if (value.contains(polygonId)) return false;
    value = {...value, polygonId};
    return true;
  }

  /// Removes [polygonId] if present. Returns `true` when membership
  /// changed (and listeners were notified). No Set copy / notify when
  /// the id was not selected (Wave 3.2.1 / 死角 C).
  bool remove(String polygonId) {
    if (!value.contains(polygonId)) return false;
    final next = {...value}..remove(polygonId);
    value = next;
    return true;
  }

  /// Empties the selection. No-op when already empty.
  void clear() {
    if (value.isEmpty) return;
    value = const {};
  }
}

/// Provides the single, stable [SelectionDragController] for the editing
/// session. Watching this provider only obtains the controller; mutating
/// `.value` does not rebuild dependents.
final selectionDragProvider = Provider<SelectionDragController>((ref) {
  final controller = SelectionDragController();
  ref.onDispose(controller.dispose);
  return controller;
});
