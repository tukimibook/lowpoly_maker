import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the finger currently is during an in-progress draw-mode drag, and
/// which existing vertex (if any) it's close enough to weld onto if
/// released right now.
///
/// [position] is always the raw finger position in *world* coordinates —
/// never pre-snapped — so [PolygonPainter] can pull the rubber-band
/// preview's tip exactly onto [snappedVertexId]'s own position for the
/// "snaps into place" visual, while [CanvasNotifier.handleDrawTap] (called
/// once, when the drag ends) still does its own authoritative nearest-
/// vertex resolution on the raw position, exactly as it always has for a
/// plain tap. There is exactly one place the "nearest vertex within
/// hitRadius" rule is expressed (`findPolygonVertexNear`); this is only
/// evaluated a second time, read-only, so the preview can show what that
/// resolution *would* produce before the artist commits to it.
@immutable
class DragPreview {
  const DragPreview({required this.position, this.snappedVertexId});

  final Offset position;
  final String? snappedVertexId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DragPreview &&
            other.position == position &&
            other.snappedVertexId == snappedVertexId);
  }

  @override
  int get hashCode => Object.hash(position, snappedVertexId);
}

/// Tracks the current [DragPreview] while a draw-mode drag is in progress,
/// or `null` between drags/while erasing.
///
/// A [ValueNotifier] (like `ViewportController`) rather than Riverpod state,
/// so [PolygonCanvas] can mutate `.value` directly on every `onPanUpdate`
/// (up to 60/sec) without going through a rebuild, and only
/// [PolygonPainter] — which listens to this directly as a `repaint` source
/// — repaints when it changes.
class DragPreviewController extends ValueNotifier<DragPreview?> {
  DragPreviewController() : super(null);
}

/// Provides the single, stable [DragPreviewController] instance for the
/// current editing session. Like `viewportProvider`, the provider itself
/// never changes value, so widgets that `watch` it (only to obtain the
/// controller) are not rebuilt when the preview inside changes.
final dragPreviewProvider = Provider<DragPreviewController>((ref) {
  final controller = DragPreviewController();
  ref.onDispose(controller.dispose);
  return controller;
});
