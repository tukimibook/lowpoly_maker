import 'package:flutter/material.dart';

import '../../models/artwork.dart';
import '../../models/canvas_mode.dart';
import '../../models/polygon_shape.dart';
import '../../providers/canvas_provider.dart';

/// Paints all confirmed polygons plus the in-progress draft (points and
/// connecting preview lines) for [artwork]. The vertex hint markers change
/// appearance depending on [mode] so it's clear whether tapping a vertex
/// will start a new shape (draw mode) or delete it (eraser mode).
class PolygonPainter extends CustomPainter {
  const PolygonPainter({required this.artwork, required this.mode});

  final Artwork artwork;
  final CanvasMode mode;

  static const double _vertexRadius = 5;
  static const double _continuationHandleRadius = 4;

  /// Fill opacity applied to every polygon (~30%), independent of the
  /// selected palette color. A per-polygon opacity control is planned for
  /// a later phase.
  static const int _fillAlpha = 77;

  @override
  void paint(Canvas canvas, Size size) {
    for (final polygon in artwork.polygons) {
      _paintPolygon(canvas, polygon);
    }

    // Vertex hints stay visible even while a draft is in progress, so users
    // can see exactly where the in-progress line can snap onto and close.
    _paintVertexHints(canvas, artwork.polygons, hasDraft: artwork.draftVertexIds.isNotEmpty);

    _paintDraft(canvas, artwork.draftVertexIds);
  }

  /// Resolves a polygon's or the draft's vertex IDs into actual on-screen
  /// positions via the shared vertex pool ([Artwork.vertices]).
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

  /// Small markers hinting what tapping a confirmed polygon's vertex will
  /// do:
  /// - eraser mode: delete just that point (red),
  /// - draw mode with a draft in progress: snap the in-progress line's next
  ///   point onto that exact vertex, sharing the corner with no gap — this
  ///   never closes the shape by itself (teal),
  /// - draw mode with no draft: start a brand new polygon from that point
  ///   (black).
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
      color = Colors.black;
    }
    final isEmphasized = mode == CanvasMode.eraser || hasDraft;

    final handlePaint = Paint()
      ..color = color.withAlpha(isEmphasized ? 210 : 140)
      ..style = PaintingStyle.fill;
    final radius = isEmphasized ? _continuationHandleRadius + 1 : _continuationHandleRadius;

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
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var i = 0; i < positions.length - 1; i++) {
      canvas.drawLine(positions[i], positions[i + 1], linePaint);
    }

    // Only hint at the "tap near start to close" shortcut when it's actually
    // active; it's disabled while the draft was started from an existing
    // vertex, since that start point is a real, shared vertex that may need
    // to be walked past on the way to wherever this shape actually finishes
    // (it must be closed explicitly via the toolbar's close button instead).
    if (positions.length >= kMinPolygonVertices && !artwork.draftStartedFromExistingVertex) {
      final hintPaint = Paint()
        ..color = Colors.black.withAlpha(60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(positions.first, kClosePolygonThreshold, hintPaint);
    }

    final dotPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    final dotBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final position in positions) {
      canvas.drawCircle(position, _vertexRadius, dotPaint);
      canvas.drawCircle(position, _vertexRadius, dotBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PolygonPainter oldDelegate) {
    return oldDelegate.artwork != artwork || oldDelegate.mode != mode;
  }
}
