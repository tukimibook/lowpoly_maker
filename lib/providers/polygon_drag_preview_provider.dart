import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live finger position while the edit mode's whole-polygon drag (a plain
/// pan, active only while no vertex is selected and a target polygon has
/// been chosen — see `.cursor/plans/plan_phase_H_alpha.md`, 2026-07-16
/// 検討メモ) is in progress.
///
/// Mirrors `VertexDragPreview`'s "commit-on-release" shape exactly: only
/// [delta] (the drag's displacement from where the finger went down) is
/// tracked live, in a plain [ValueNotifier] `PolygonPainter` listens to
/// directly as a `repaint` source — never through Riverpod state — so
/// every `onPanUpdate` frame repaints just the canvas, without triggering a
/// widget rebuild. [CanvasNotifier.translatePolygon] is only ever called
/// once, when the finger lifts, so exactly one [Artwork] snapshot (and one
/// undo entry) is produced per drag, no matter how many frames it spanned.
///
/// [affectedVertexIds] is the target polygon's own `vertexIds`, snapshotted
/// as a [Set] once when the drag starts, so [PolygonPainter._positionFor]
/// can offset *every* vertex it renders that belongs to this polygon by
/// [delta] — including corners welded to a neighboring polygon, which
/// therefore preview the drag too, consistent with how a single welded
/// vertex already drags every polygon that shares it (`moveVertex`).
@immutable
class PolygonDragPreview {
  const PolygonDragPreview({required this.affectedVertexIds, required this.delta});

  final Set<String> affectedVertexIds;
  final Offset delta;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PolygonDragPreview &&
            other.delta == delta &&
            _setEquals(other.affectedVertexIds, affectedVertexIds));
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.every(b.contains);
  }

  @override
  int get hashCode => Object.hash(delta, affectedVertexIds.length);
}

class PolygonDragPreviewController extends ValueNotifier<PolygonDragPreview?> {
  PolygonDragPreviewController() : super(null);
}

final polygonDragPreviewProvider = Provider<PolygonDragPreviewController>((ref) {
  final controller = PolygonDragPreviewController();
  ref.onDispose(controller.dispose);
  return controller;
});
