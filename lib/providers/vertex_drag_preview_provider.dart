import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live finger position while a vertex is being long-press-dragged in
/// [CanvasMode.edit]. [PolygonPainter] substitutes this for the committed
/// [Vertex.position] so every polygon and draft segment that references
/// [vertexId] follows the finger without mutating [Artwork] until release.
@immutable
class VertexDragPreview {
  const VertexDragPreview({required this.vertexId, required this.position});

  final String vertexId;
  final Offset position;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is VertexDragPreview &&
            other.vertexId == vertexId &&
            other.position == position);
  }

  @override
  int get hashCode => Object.hash(vertexId, position);
}

class VertexDragPreviewController extends ValueNotifier<VertexDragPreview?> {
  VertexDragPreviewController() : super(null);
}

final vertexDragPreviewProvider = Provider<VertexDragPreviewController>((ref) {
  final controller = VertexDragPreviewController();
  ref.onDispose(controller.dispose);
  return controller;
});
