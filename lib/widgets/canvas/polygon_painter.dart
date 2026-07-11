import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/artwork.dart';
import '../../models/canvas_mode.dart';
import '../../models/polygon_shape.dart';
import '../../providers/canvas_provider.dart' show kMinPolygonVertices;
import '../../providers/drag_preview_provider.dart';
import '../../providers/vertex_drag_preview_provider.dart';
import '../../services/coordinate_transform.dart';

/// Paints all confirmed polygons plus the in-progress draft (points and
/// connecting preview lines) for [artwork]. The vertex hint markers change
/// appearance depending on [mode] so it's clear whether tapping a vertex
/// will start a new shape (draw mode), delete it (eraser mode), or select
/// and move it (edit mode).
class PolygonPainter extends CustomPainter {
  PolygonPainter({
    required this.artwork,
    required this.mode,
    required this.viewport,
    required this.dragPreview,
    required this.vertexDragPreview,
    required this.selectedVertexId,
    required this.canvasBrightness,
  }) : super(
         repaint: Listenable.merge([viewport, dragPreview, vertexDragPreview]),
       );

  final Artwork artwork;
  final CanvasMode mode;
  final ValueListenable<ViewportTransform> viewport;
  final ValueListenable<DragPreview?> dragPreview;
  final ValueListenable<VertexDragPreview?> vertexDragPreview;
  final String? selectedVertexId;
  final Brightness canvasBrightness;

  static const double _vertexRadius = 5;
  static const double _continuationHandleRadius = 4;

  static const int _fillAlpha = 77;

  Color get _onCanvasColor =>
      canvasBrightness == Brightness.dark ? Colors.white : Colors.black;

  Color get _canvasContrastColor =>
      canvasBrightness == Brightness.dark ? Colors.black : Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final transform = viewport.value;
    canvas.save();
    canvas.translate(transform.offset.dx, transform.offset.dy);
    canvas.scale(transform.scale);

    for (final polygon in artwork.polygons) {
      _paintPolygon(canvas, polygon);
    }

    if (mode == CanvasMode.edit) {
      _paintEditVertexHandles(canvas);
    } else {
      _paintVertexHints(
        canvas,
        artwork.polygons,
        hasDraft: artwork.draftVertexIds.isNotEmpty,
      );
    }

    _paintDraft(canvas, artwork.draftVertexIds);

    if (mode == CanvasMode.draw) {
      _paintDragPreview(canvas, artwork.draftVertexIds);
    }

    if (mode == CanvasMode.edit && selectedVertexId != null) {
      _paintSelectionHandle(canvas, selectedVertexId!);
    }

    canvas.restore();
  }

  Offset _positionFor(String vertexId) {
    final drag = vertexDragPreview.value;
    if (drag != null && drag.vertexId == vertexId) {
      return drag.position;
    }
    return artwork.vertices[vertexId]!.position;
  }

  List<Offset> _resolvePositions(List<String> vertexIds) {
    return [for (final id in vertexIds) _positionFor(id)];
  }

  void _paintPolygon(Canvas canvas, PolygonShape polygon) {
    if (polygon.vertexIds.length < 3) return;
    final positions = _resolvePositions(polygon.vertexIds);

    final path = Path()..moveTo(positions.first.dx, positions.first.dy);
    for (final position in positions.skip(1)) {
      path.lineTo(position.dx, position.dy);
    }
    path.close();

    final fillPaint = Paint()
      ..color = polygon.fillColor.withAlpha(_fillAlpha)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = polygon.strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = polygon.strokeWidth
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);
  }

  void _paintVertexHints(
    Canvas canvas,
    List<PolygonShape> polygons, {
    required bool hasDraft,
  }) {
    final Color color;
    if (mode == CanvasMode.eraser) {
      color = Colors.redAccent;
    } else if (hasDraft) {
      color = Colors.teal;
    } else {
      color = _onCanvasColor;
    }
    final isEmphasized = mode == CanvasMode.eraser || hasDraft;

    final handlePaint = Paint()
      ..color = color.withAlpha(isEmphasized ? 210 : 140)
      ..style = PaintingStyle.fill;
    final radius =
        isEmphasized ? _continuationHandleRadius + 1 : _continuationHandleRadius;

    for (final polygon in polygons) {
      for (final vertexId in polygon.vertexIds) {
        canvas.drawCircle(_positionFor(vertexId), radius, handlePaint);
      }
    }
  }

  /// Edit-mode handles on every vertex the artist can select or drag —
  /// confirmed polygons and the in-progress draft alike.
  void _paintEditVertexHandles(Canvas canvas) {
    final referencedIds = <String>{...artwork.draftVertexIds};
    for (final polygon in artwork.polygons) {
      referencedIds.addAll(polygon.vertexIds);
    }

    final handlePaint = Paint()
      ..color = Colors.blueAccent.withAlpha(200)
      ..style = PaintingStyle.fill;

    for (final vertexId in referencedIds) {
      if (artwork.vertices[vertexId] == null) continue;
      canvas.drawCircle(
        _positionFor(vertexId),
        _continuationHandleRadius + 1,
        handlePaint,
      );
    }
  }

  void _paintSelectionHandle(Canvas canvas, String vertexId) {
    if (artwork.vertices[vertexId] == null) return;
    final position = _positionFor(vertexId);

    final ringPaint = Paint()
      ..color = Colors.orangeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(position, _vertexRadius + 8, ringPaint);

    final glowPaint = Paint()
      ..color = Colors.orangeAccent.withAlpha(60)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, _vertexRadius + 8, glowPaint);
  }

  void _paintDraft(Canvas canvas, List<String> draftVertexIds) {
    if (draftVertexIds.isEmpty) return;
    final positions = _resolvePositions(draftVertexIds);

    final linePaint = Paint()
      ..color = _onCanvasColor.withAlpha(221)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var i = 0; i < positions.length - 1; i++) {
      canvas.drawLine(positions[i], positions[i + 1], linePaint);
    }

    if (mode != CanvasMode.edit) {
      final dotPaint = Paint()
        ..color = _onCanvasColor
        ..style = PaintingStyle.fill;
      final dotBorderPaint = Paint()
        ..color = _canvasContrastColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      for (final position in positions) {
        canvas.drawCircle(position, _vertexRadius, dotPaint);
        canvas.drawCircle(position, _vertexRadius, dotBorderPaint);
      }

      if (positions.length >= kMinPolygonVertices) {
        final closeHintPaint = Paint()
          ..color = Colors.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(positions.first, _vertexRadius + 4, closeHintPaint);
      }
    }
  }

  void _paintDragPreview(Canvas canvas, List<String> draftVertexIds) {
    final preview = dragPreview.value;
    if (preview == null) return;

    if (draftVertexIds.isNotEmpty) {
      final lastPosition = _positionFor(draftVertexIds.last);
      final previewLinePaint = Paint()
        ..color = _onCanvasColor.withAlpha(120)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawLine(lastPosition, preview.position, previewLinePaint);
    }

    final snappedId = preview.snappedVertexId;
    if (snappedId == null) return;
    final snapPosition = _positionFor(snappedId);

    final magnetRingPaint = Paint()
      ..color = Colors.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(snapPosition, _vertexRadius + 7, magnetRingPaint);

    final magnetGlowPaint = Paint()
      ..color = Colors.teal.withAlpha(50)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(snapPosition, _vertexRadius + 7, magnetGlowPaint);
  }

  @override
  bool shouldRepaint(covariant PolygonPainter oldDelegate) {
    return oldDelegate.artwork != artwork ||
        oldDelegate.mode != mode ||
        oldDelegate.viewport != viewport ||
        oldDelegate.dragPreview != dragPreview ||
        oldDelegate.vertexDragPreview != vertexDragPreview ||
        oldDelegate.selectedVertexId != selectedVertexId ||
        oldDelegate.canvasBrightness != canvasBrightness;
  }
}
