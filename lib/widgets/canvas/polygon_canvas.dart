import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/canvas_mode.dart';
import '../../providers/canvas_background_provider.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/detach_cycle_provider.dart';
import '../../providers/drag_preview_provider.dart';
import '../../providers/polygon_drag_preview_provider.dart';
import '../../providers/polygon_edit_target_provider.dart';
import '../../providers/selected_vertex_provider.dart';
import '../../providers/vertex_drag_preview_provider.dart';
import '../../providers/viewport_provider.dart';
import 'polygon_painter.dart';
import 'underlay_layer.dart';

/// The drawable surface: renders confirmed polygons and the in-progress
/// draft, and interprets touches according to the current [CanvasMode]:
/// - [CanvasMode.draw]: place/extend/close polygons.
/// - [CanvasMode.eraser]: delete a single touched vertex.
/// - [CanvasMode.edit]: tap to select a vertex; long-press drag to move it.
class PolygonCanvas extends ConsumerWidget {
  const PolygonCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = ref.watch(canvasProvider);
    final mode = ref.watch(canvasModeProvider);
    final selectedVertexId = ref.watch(selectedVertexProvider);
    final notifier = ref.read(canvasProvider.notifier);
    final viewport = ref.watch(viewportProvider);
    final dragPreview = ref.watch(dragPreviewProvider);
    final vertexDragPreview = ref.watch(vertexDragPreviewProvider);
    final polygonDragPreview = ref.watch(polygonDragPreviewProvider);
    final canvasBrightness = ref.watch(canvasBackgroundProvider);
    final detachCycleIndex = ref.watch(detachCycleIndexProvider);
    final polygonCycleIndex = ref.watch(polygonCycleIndexProvider);
    final edgeCycleIndex = ref.watch(edgeCycleIndexProvider);

    // Which polygon edit mode currently emphasizes, and — while no vertex
    // is selected — which of its edges, if any. Exactly one of these two
    // features is ever active at a time (selection state alone decides
    // which), so both resolve into the same `highlightedPolygonId` the
    // painter takes — see that field's doc for why. Computed once here,
    // rather than duplicated in the toolbar, so the canvas and toolbar
    // buttons can never disagree about the current target.
    String? highlightedPolygonId;
    PolygonEdge? targetEdge;
    if (mode == CanvasMode.edit) {
      if (selectedVertexId != null) {
        highlightedPolygonId = resolveDetachTarget(
          referencingPolygons: notifier.polygonsReferencing(selectedVertexId),
          draftReferences: notifier.draftReferencesVertex(selectedVertexId),
          rawCycleIndex: detachCycleIndex,
        )?.polygonId;
      } else {
        highlightedPolygonId = resolvePolygonTarget(
          polygons: artwork.polygons,
          rawCycleIndex: polygonCycleIndex,
        );
        final targetPolygon = artwork.polygons
            .where((p) => p.id == highlightedPolygonId)
            .firstOrNull;
        if (targetPolygon != null) {
          targetEdge = resolveEdgeTarget(
            polygon: targetPolygon,
            rawCycleIndex: edgeCycleIndex,
          );
        }
      }
    }
    final targetPolygonId = selectedVertexId == null ? highlightedPolygonId : null;

    double hitRadius() => kVertexHitRadius / viewport.value.scale;

    Offset worldPosition(Offset localPosition) {
      return viewport.value.screenToWorld(localPosition);
    }

    void updateDrawPreview(Offset localPosition) {
      final position = worldPosition(localPosition);
      final hit = notifier.findPolygonVertexNear(
        position,
        hitRadius: hitRadius(),
      );
      final previousSnap = dragPreview.value?.snappedVertexId;
      dragPreview.value = DragPreview(
        position: position,
        snappedVertexId: hit?.vertexId,
      );
      if (hit != null && hit.vertexId != previousSnap) {
        HapticFeedback.mediumImpact();
      }
    }

    void commitDrawDrag() {
      final preview = dragPreview.value;
      dragPreview.value = null;
      if (preview == null) return;

      final fillColor = ref.read(selectedFillColorProvider);
      final matchedColor = notifier.handleDrawTap(
        preview.position,
        fillColor: fillColor,
        hitRadius: hitRadius(),
      );
      if (matchedColor != null) {
        ref.read(selectedFillColorProvider.notifier).state = matchedColor;
      }
    }

    void handleEditTap(Offset localPosition) {
      final tappedId = notifier.findVertexNear(
        worldPosition(localPosition),
        hitRadius: hitRadius(),
      );
      final selected = ref.read(selectedVertexProvider);

      if (selected != null && tappedId != null && tappedId != selected) {
        if (notifier.weldVertices(selected, tappedId)) {
          ref.read(selectedVertexProvider.notifier).state = selected;
          HapticFeedback.mediumImpact();
          return;
        }
      }

      ref.read(selectedVertexProvider.notifier).state = tappedId;
      ref.read(detachCycleIndexProvider.notifier).state = 0;
      if (tappedId != null) {
        // A vertex just became selected — the whole-shape target UI (図形
        // 切替/辺切替/追加/削除) that only shows while nothing is selected
        // is about to disappear, so leave it starting fresh next time.
        ref.read(polygonCycleIndexProvider.notifier).state = -1;
        ref.read(edgeCycleIndexProvider.notifier).state = -1;
      }
    }

    void startPolygonDrag() {
      final polygonId = targetPolygonId;
      if (polygonId == null) return;
      final polygon = artwork.polygons.where((p) => p.id == polygonId).firstOrNull;
      if (polygon == null) return;
      polygonDragPreview.value = PolygonDragPreview(
        affectedVertexIds: polygon.vertexIds.toSet(),
        delta: Offset.zero,
      );
    }

    void updatePolygonDrag(Offset localDelta) {
      final preview = polygonDragPreview.value;
      if (preview == null) return;
      polygonDragPreview.value = PolygonDragPreview(
        affectedVertexIds: preview.affectedVertexIds,
        delta: preview.delta + localDelta / viewport.value.scale,
      );
    }

    void commitPolygonDrag() {
      final preview = polygonDragPreview.value;
      polygonDragPreview.value = null;
      final polygonId = targetPolygonId;
      if (preview == null || polygonId == null) return;
      notifier.translatePolygon(polygonId, preview.delta);
    }

    void startVertexDrag(Offset localPosition) {
      final position = worldPosition(localPosition);
      final vertexId = notifier.findVertexNear(
        position,
        hitRadius: hitRadius(),
      );
      if (vertexId == null) return;

      ref.read(selectedVertexProvider.notifier).state = vertexId;
      vertexDragPreview.value = VertexDragPreview(
        vertexId: vertexId,
        position: position,
      );
      HapticFeedback.mediumImpact();
    }

    void updateVertexDrag(Offset localPosition) {
      final preview = vertexDragPreview.value;
      if (preview == null) return;
      vertexDragPreview.value = VertexDragPreview(
        vertexId: preview.vertexId,
        position: worldPosition(localPosition),
      );
    }

    void commitVertexDrag() {
      final preview = vertexDragPreview.value;
      vertexDragPreview.value = null;
      if (preview == null) return;
      notifier.moveVertex(preview.vertexId, preview.position);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          notifier.setCanvasSize(size);
        });

        // The underlay paints behind the polygon layer; each gets its own
        // `RepaintBoundary` so redrawing one (e.g. an opacity change, or a
        // vertex drag) never forces the other to repaint too.
        final content = Stack(
          children: [
            UnderlayLayer(size: size),
            RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: PolygonPainter(
                  artwork: artwork,
                  mode: mode,
                  viewport: viewport,
                  dragPreview: dragPreview,
                  vertexDragPreview: vertexDragPreview,
                  polygonDragPreview: polygonDragPreview,
                  selectedVertexId: selectedVertexId,
                  highlightedPolygonId: highlightedPolygonId,
                  targetEdge: targetEdge,
                  canvasBrightness: canvasBrightness,
                ),
              ),
            ),
          ],
        );

        if (mode == CanvasMode.edit) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => handleEditTap(details.localPosition),
            onLongPressStart: (details) =>
                startVertexDrag(details.localPosition),
            onLongPressMoveUpdate: (details) =>
                updateVertexDrag(details.localPosition),
            onLongPressEnd: (details) => commitVertexDrag(),
            onLongPressCancel: () {
              vertexDragPreview.value = null;
            },
            // A plain (non-long-press) drag translates the whole "図形
            // 切替" target instead — active only while no vertex is
            // selected and a target has actually been chosen (see
            // `targetPolygonId`'s doc above); with neither, this is a
            // no-op, exactly like today's plain drag in edit mode.
            onPanStart: (details) => startPolygonDrag(),
            onPanUpdate: (details) => updatePolygonDrag(details.delta),
            onPanEnd: (details) => commitPolygonDrag(),
            onPanCancel: () {
              polygonDragPreview.value = null;
            },
            child: content,
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (details) {
            if (mode == CanvasMode.eraser) {
              notifier.handleEraseTap(
                worldPosition(details.localPosition),
                hitRadius: hitRadius(),
              );
              return;
            }
            updateDrawPreview(details.localPosition);
          },
          onPanUpdate: (details) {
            if (mode == CanvasMode.eraser) return;
            updateDrawPreview(details.localPosition);
          },
          onPanEnd: (details) {
            if (mode == CanvasMode.eraser) return;
            commitDrawDrag();
          },
          onPanCancel: () {
            if (mode == CanvasMode.eraser) return;
            dragPreview.value = null;
          },
          child: content,
        );
      },
    );
  }
}
