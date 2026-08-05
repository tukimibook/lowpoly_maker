import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'detach_cycle_provider.dart';
import 'drag_preview_provider.dart';
import 'polygon_drag_preview_provider.dart';
import 'polygon_edit_target_provider.dart';
import 'selection_drag_provider.dart';
import 'shade_session_provider.dart';
import 'trace_gesture_provider.dart';
import 'trace_stroke_preview_provider.dart';
import 'vertex_drag_preview_provider.dart';

/// The vertex currently highlighted for editing in [CanvasMode.edit], or
/// `null` when nothing is selected. Cleared when leaving edit mode.
final selectedVertexProvider = StateProvider<String?>((ref) => null);

/// When `true`, the next tap on a *different* vertex in edit mode runs
/// [CanvasNotifier.weldVertices] (explicit weld arming via the toolbar).
/// Cleared after that attempt, on deselect, and on mode change — never
/// left armed across sessions.
final weldArmedProvider = StateProvider<bool>((ref) => false);

/// A [Ref.read] / [WidgetRef.read] / [ProviderContainer.read] tear-off.
///
/// Riverpod 2.6's [WidgetRef] is not a [Ref], so session-UI helpers take this
/// shared read surface instead of `Ref` directly — call as
/// `clearGesturePreviews(ref.read)` from widgets or tests.
typedef EditorSessionRead = T Function<T>(ProviderListenable<T> provider);

/// Clears every in-flight canvas gesture preview (draw snap, vertex drag,
/// whole-polygon drag, and trace stroke bookkeeping). Safe to call from
/// mode switches — none of these values belong in [Artwork] undo history.
void clearGesturePreviews(EditorSessionRead read) {
  read(dragPreviewProvider).value = null;
  read(vertexDragPreviewProvider).value = null;
  read(polygonDragPreviewProvider).value = null;
  read(traceGestureProvider).reset();
  read(traceStrokePreviewProvider).clear();
}

/// Clears edit-mode selection UI: the selected vertex, weld arming, and
/// (by default) the whole-shape / detach cycle counters.
///
/// Pass [resetWholeShapeCycles] `false` for the toolbar's "選択を解除"
/// button, which must leave the 図形/辺 cycle where it was so the artist
/// can return to whole-shape targeting without re-cycling from scratch.
void clearEditSelectionUi(
  EditorSessionRead read, {
  bool resetWholeShapeCycles = true,
}) {
  read(selectedVertexProvider.notifier).state = null;
  read(detachCycleIndexProvider.notifier).state = 0;
  read(weldArmedProvider.notifier).state = false;
  if (resetWholeShapeCycles) {
    read(editSelectionProvider.notifier).clearBoth();
  }
}

/// Clears shade-session UI: multi-selection ([SelectionDragController]) and
/// the Shade palette accordion anchor. Call from mode switches leaving shade
/// and from gallery open/new — Phase Select requires explicit writes at those
/// two call sites (not helper-only reliance).
void clearShadeSessionUi(EditorSessionRead read) {
  read(selectionDragProvider).clear();
  read(activeBaseColorProvider.notifier).state = null;
}
