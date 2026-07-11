import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/canvas_mode.dart';
import '../../providers/canvas_background_provider.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/drag_preview_provider.dart';
import '../../providers/selected_vertex_provider.dart';
import '../../providers/vertex_drag_preview_provider.dart';
import '../../providers/viewport_provider.dart';
import 'polygon_painter.dart';

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
    final canvasBrightness = ref.watch(canvasBackgroundProvider);

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
      final vertexId = notifier.findVertexNear(
        worldPosition(localPosition),
        hitRadius: hitRadius(),
      );
      ref.read(selectedVertexProvider.notifier).state = vertexId;
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

        final painter = CustomPaint(
          size: size,
          painter: PolygonPainter(
            artwork: artwork,
            mode: mode,
            viewport: viewport,
            dragPreview: dragPreview,
            vertexDragPreview: vertexDragPreview,
            selectedVertexId: selectedVertexId,
            canvasBrightness: canvasBrightness,
          ),
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
            child: painter,
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
          child: painter,
        );
      },
    );
  }
}
