import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/artwork.dart';
import '../../models/canvas_mode.dart';
import '../../models/polygon_shape.dart';
import '../../providers/canvas_provider.dart' show kMinPolygonVertices;
import '../../providers/drag_preview_provider.dart';
import '../../providers/polygon_drag_preview_provider.dart';
import '../../providers/polygon_edit_target_provider.dart' show PolygonEdge;
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
    required this.polygonDragPreview,
    required this.selectedVertexId,
    required this.highlightedPolygonId,
    required this.targetEdge,
    required this.canvasBrightness,
  }) : super(
         repaint: Listenable.merge([
           viewport,
           dragPreview,
           vertexDragPreview,
           polygonDragPreview,
         ]),
       );

  final Artwork artwork;
  final CanvasMode mode;
  final ValueListenable<ViewportTransform> viewport;
  final ValueListenable<DragPreview?> dragPreview;
  final ValueListenable<VertexDragPreview?> vertexDragPreview;

  /// Live displacement while the edit mode's whole-polygon drag (see
  /// `PolygonDragPreview`'s doc) is in progress, or `null` between drags.
  final ValueListenable<PolygonDragPreview?> polygonDragPreview;
  final String? selectedVertexId;

  /// The one polygon currently emphasized in edit mode — either the
  /// shared-vertex "切り離し" cycle/execute target (see `resolveDetachTarget`
  /// in `providers/detach_cycle_provider.dart`, when a vertex is selected),
  /// or the whole-shape "図形切替"/"辺切替"/"ここに追加"/"削除" target (see
  /// `resolvePolygonTarget` in `providers/polygon_edit_target_provider.dart`,
  /// when no vertex is selected). These two never apply at once — vertex
  /// selection state alone decides which — so both features share this one
  /// field rather than duplicating the highlight rendering. Painted at
  /// [_highlightedFillAlpha] instead of [_fillAlpha] either way, so the
  /// artist can see, at a glance, which shape a toolbar action would
  /// currently affect — this is the *only* signal for that; the toolbar
  /// buttons themselves carry no per-target label.
  final String? highlightedPolygonId;

  /// The one edge of [highlightedPolygonId] currently targeted by the edit
  /// mode's "辺を切り替え"/"ここに追加" buttons, or `null` when no vertex is
  /// selected but no edge has been cycled to yet (or a vertex *is*
  /// selected, in which case this feature isn't active at all). Painted as
  /// a plain accent-colored overwrite of that one segment — see
  /// [_paintTargetEdge] — rather than a dashed outline, to keep the
  /// drawing logic trivial.
  final PolygonEdge? targetEdge;
  final Brightness canvasBrightness;

  static const double _vertexRadius = 5;
  static const double _continuationHandleRadius = 4;

  static const int _fillAlpha = 77; // ~30%
  static const int _highlightedFillAlpha = 153; // ~60%

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
    _paintTargetEdge(canvas);

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
    final polygonDrag = polygonDragPreview.value;
    if (polygonDrag != null && polygonDrag.affectedVertexIds.contains(vertexId)) {
      return artwork.vertices[vertexId]!.position + polygonDrag.delta;
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

    final alpha = polygon.id == highlightedPolygonId ? _highlightedFillAlpha : _fillAlpha;
    final fillPaint = Paint()
      ..color = polygon.fillColor.withAlpha(alpha)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = polygon.strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = polygon.strokeWidth
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);
  }

  /// Overwrites [targetEdge] with a thicker, accent-colored stroke, on top
  /// of the plain polygon outline already drawn by [_paintPolygon] — the
  /// "辺を切り替え" button's sole visual feedback. Deliberately a single
  /// [Canvas.drawLine] rather than a dashed outline (avoids the extra
  /// geometry a dash pattern would need for no real gain here). Uses the
  /// same [Colors.blueAccent] as [_paintEditVertexHandles]'s handles for a
  /// consistent "edit mode = blue" color language.
  void _paintTargetEdge(Canvas canvas) {
    final edge = targetEdge;
    if (edge == null) return;
    if (artwork.vertices[edge.startVertexId] == null ||
        artwork.vertices[edge.endVertexId] == null) {
      return;
    }

    final accentPaint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      _positionFor(edge.startVertexId),
      _positionFor(edge.endVertexId),
      accentPaint,
    );
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
        oldDelegate.polygonDragPreview != polygonDragPreview ||
        oldDelegate.selectedVertexId != selectedVertexId ||
        oldDelegate.highlightedPolygonId != highlightedPolygonId ||
        oldDelegate.targetEdge != targetEdge ||
        oldDelegate.canvasBrightness != canvasBrightness;
  }
}
