import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/artwork.dart';
import '../../models/canvas_mode.dart';
import '../../models/polygon_shape.dart';
import '../../providers/canvas_provider.dart' show kMinPolygonVertices;
import '../../providers/drag_preview_provider.dart';
import '../../services/coordinate_transform.dart';

/// Paints all confirmed polygons plus the in-progress draft (points and
/// connecting preview lines) for [artwork]. The vertex hint markers change
/// appearance depending on [mode] so it's clear whether tapping a vertex
/// will start a new shape (draw mode) or delete it (eraser mode).
class PolygonPainter extends CustomPainter {
  PolygonPainter({
    required this.artwork,
    required this.mode,
    required this.viewport,
    required this.dragPreview,
    required this.canvasBrightness,
  }) : super(repaint: Listenable.merge([viewport, dragPreview]));

  final Artwork artwork;
  final CanvasMode mode;
  final ValueListenable<ViewportTransform> viewport;
  final ValueListenable<DragPreview?> dragPreview;
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

    _paintVertexHints(
      canvas,
      artwork.polygons,
      hasDraft: artwork.draftVertexIds.isNotEmpty,
    );

    _paintDraft(canvas, artwork.draftVertexIds);

    if (mode == CanvasMode.draw) {
      _paintDragPreview(canvas, artwork.draftVertexIds);
    }

    canvas.restore();
  }

  List<Offset> _resolvePositions(List<String> vertexIds) {
    return [for (final id in vertexIds) artwork.vertices[id]!.position];
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
      for (final position in _resolvePositions(polygon.vertexIds)) {
        canvas.drawCircle(position, radius, handlePaint);
      }
    }
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

  void _paintDragPreview(Canvas canvas, List<String> draftVertexIds) {
    final preview = dragPreview.value;
    if (preview == null) return;

    if (draftVertexIds.isNotEmpty) {
      final lastPosition = artwork.vertices[draftVertexIds.last]!.position;
      final previewLinePaint = Paint()
        ..color = _onCanvasColor.withAlpha(120)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawLine(lastPosition, preview.position, previewLinePaint);
    }

    final snappedId = preview.snappedVertexId;
    if (snappedId == null) return;
    final snapPosition = artwork.vertices[snappedId]!.position;

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
        oldDelegate.canvasBrightness != canvasBrightness;
  }
}
