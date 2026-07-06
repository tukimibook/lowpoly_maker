import 'package:flutter/material.dart';

import '../../models/artwork.dart';
import '../../models/canvas_mode.dart';
import '../../models/polygon_shape.dart';
import '../../models/vertex.dart';
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
    _paintVertexHints(canvas, artwork.polygons, hasDraft: artwork.draftVertices.isNotEmpty);

    _paintDraft(canvas, artwork.draftVertices);
  }

  void _paintPolygon(Canvas canvas, PolygonShape polygon) {
    if (polygon.vertices.length < 3) return;

    final path = Path()
      ..moveTo(polygon.vertices.first.position.dx, polygon.vertices.first.position.dy);
    for (final vertex in polygon.vertices.skip(1)) {
      path.lineTo(vertex.position.dx, vertex.position.dy);
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
  /// - draw mode with a draft in progress: snap the in-progress line's end
  ///   onto that point and close the shape there (teal),
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
      for (final vertex in polygon.vertices) {
        canvas.drawCircle(vertex.position, radius, handlePaint);
      }
    }
  }

  void _paintDraft(Canvas canvas, List<Vertex> draft) {
    if (draft.isEmpty) return;

    final linePaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var i = 0; i < draft.length - 1; i++) {
      canvas.drawLine(draft[i].position, draft[i + 1].position, linePaint);
    }

    // Only hint at the "tap near start to close" shortcut when it's actually
    // active; it's disabled while the draft was started from an existing
    // vertex (it can only be closed by docking onto another existing vertex
    // instead — see the teal vertex hints).
    if (draft.length >= kMinPolygonVertices && !artwork.draftStartedFromExistingVertex) {
      final hintPaint = Paint()
        ..color = Colors.black.withAlpha(60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(draft.first.position, kClosePolygonThreshold, hintPaint);
    }

    final dotPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    final dotBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final vertex in draft) {
      canvas.drawCircle(vertex.position, _vertexRadius, dotPaint);
      canvas.drawCircle(vertex.position, _vertexRadius, dotBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PolygonPainter oldDelegate) {
    return oldDelegate.artwork != artwork || oldDelegate.mode != mode;
  }
}
