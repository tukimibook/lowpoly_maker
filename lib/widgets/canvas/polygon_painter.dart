import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/artwork.dart';
import '../../models/canvas_mode.dart';
import '../../models/polygon_highlight_style.dart';
import '../../models/polygon_shape.dart';
import '../../providers/canvas_provider.dart' show kMinPolygonVertices;
import '../../providers/drag_preview_provider.dart';
import '../../providers/polygon_drag_preview_provider.dart';
import '../../providers/polygon_edit_target_provider.dart' show PolygonEdge;
import '../../providers/trace_stroke_preview_provider.dart';
import '../../providers/vertex_drag_preview_provider.dart';
import '../../services/coordinate_transform.dart';

/// Multiplies a fill's own alpha by a chrome/UI alpha (preview, X-Ray,
/// Draw/Edit underlay), rounding half-up. Used by [PolygonPainter] so a
/// future translucent palette color is never clobbered by absolute
/// [Color.withAlpha] overwrite.
///
/// Identity: when either operand is 255 the other value is returned
/// unchanged (existing opaque artwork is bit-identical to the old path).
int blendFillChromeAlpha(int fillAlpha, int chromeAlpha) {
  return (fillAlpha * chromeAlpha + 127) ~/ 255;
}

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
    required this.tracePreview,
    required this.selectionDrag,
    this.highlightStyle = PolygonHighlightStyle.neutral,
    this.isPreviewMode = false,
    this.isShadeXRay = false,
  }) : super(
         repaint: Listenable.merge([
           viewport,
           dragPreview,
           vertexDragPreview,
           polygonDragPreview,
           tracePreview,
           selectionDrag,
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
  /// [_editHighlightedFillAlpha] instead of [PolygonHighlightStyle.fillAlpha]
  /// either way, so the artist can see, at a glance, which shape a toolbar
  /// action would currently affect — this is the *only* signal for that;
  /// the toolbar buttons themselves carry no per-target label.
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

  /// Live なぞりモード ("trace mode") stroke in progress, or a controller
  /// whose [TraceStrokePreviewController.path] is `null` between strokes
  /// (Phase F, `.cursor/plans/plan_phase_F.md`).
  final TraceStrokePreviewController tracePreview;

  /// Shade multi-selection (Phase Select). Listened as a [repaint] source so
  /// brush adds never rebuild [PolygonCanvas] — only this painter.
  final ValueListenable<Set<String>> selectionDrag;

  /// Draw/Edit underlay fill alpha; also used when [isShadeXRay] is true.
  final PolygonHighlightStyle highlightStyle;

  /// When true, only polygon fills are painted (no strokes or edit chrome).
  final bool isPreviewMode;

  /// Shade Select tool: translucent fills so the underlay stays readable.
  /// Resolved in [PolygonCanvas] (`mode == shade && tool == select`); this
  /// painter never sees [ShadeTool] directly.
  final bool isShadeXRay;

  // Visual marker sizes only (Phase Select / 死角3). Hit testing stays on
  // `kVertexHitRadius` in canvas_provider — do not shrink that with these.
  static const double _vertexRadius = 4;
  static const double _continuationHandleRadius = 3;

  /// Edit-mode single-target emphasis (legacy path for 図形切替).
  static const int _editHighlightedFillAlpha = 153;

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

    // Reused by shade selection outlines (pass 2) so Path geometry is built once.
    final pathCache = <String, Path>{};

    for (final polygon in artwork.polygons) {
      _paintPolygon(canvas, polygon, pathCache);
    }

    if (isPreviewMode) {
      canvas.restore();
      return;
    }

    if (mode == CanvasMode.shade) {
      _paintShadeSelectionOutlines(canvas, pathCache);
    }

    _paintTargetEdge(canvas);

    if (mode == CanvasMode.edit) {
      _paintEditVertexHandles(canvas);
    } else if (mode != CanvasMode.shade) {
      _paintVertexHints(
        canvas,
        artwork.polygons,
        hasDraft: artwork.draftVertexIds.isNotEmpty,
      );
    }

    _paintDraft(canvas, artwork.draftVertexIds);

    if (mode == CanvasMode.draw) {
      _paintDragPreview(canvas, artwork.draftVertexIds);
      _paintTracePreview(canvas);
    }

    if (mode == CanvasMode.edit && selectedVertexId != null) {
      _paintSelectionHandle(canvas, selectedVertexId!);
    }

    canvas.restore();
  }

  /// Fill opacity for Draw/Edit underlays, and for Shade X-Ray (Select tool).
  ///
  /// Draw/Edit and Shade X-Ray intentionally share [PolygonHighlightStyle.fillAlpha]
  /// so underlay readability uses one visual language. Preview and Shade
  /// Solid/Light never call this (they force opaque 255 in [_paintPolygon]).
  int _fillAlphaFor(String polygonId) {
    if (polygonId == highlightedPolygonId) {
      return _editHighlightedFillAlpha;
    }
    return highlightStyle.fillAlpha;
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

  void _paintPolygon(
    Canvas canvas,
    PolygonShape polygon,
    Map<String, Path> pathCache,
  ) {
    if (polygon.vertexIds.length < 3) return;
    final positions = _resolvePositions(polygon.vertexIds);

    final path = Path()..moveTo(positions.first.dx, positions.first.dy);
    for (final position in positions.skip(1)) {
      path.lineTo(position.dx, position.dy);
    }
    path.close();
    pathCache[polygon.id] = path;

    // Chrome alpha: Preview and Shade Solid/Light leave the fill's own
    // opacity untouched (chrome = 255). Shade X-Ray and Draw/Edit apply
    // underlay darkening via [_fillAlphaFor]. The fill's intrinsic alpha
    // is then multiplied in — never absolute-overwritten — so clear /
    // translucent palette colors stay correct.
    final int chromeAlpha;
    if (isPreviewMode) {
      chromeAlpha = 255;
    } else if (mode == CanvasMode.shade) {
      chromeAlpha = isShadeXRay ? _fillAlphaFor(polygon.id) : 255;
    } else {
      chromeAlpha = _fillAlphaFor(polygon.id);
    }
    final blendedAlpha = blendFillChromeAlpha(
      (polygon.fillColor.a * 255.0).round().clamp(0, 255),
      chromeAlpha,
    );
    if (blendedAlpha != 0) {
      final fillPaint = Paint()
        ..color = polygon.fillColor.withAlpha(blendedAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    }

    if (isPreviewMode) return;

    final strokePaint = Paint()
      ..color = polygon.strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = polygon.strokeWidth
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);
  }

  /// Shade-mode selection chrome: accent stroke on top of all polygon fills
  /// (pass 2), so overlapping shapes never hide the outline. Reuses [pathCache]
  /// from pass 1 — no second [_resolvePositions]. Same [Colors.blueAccent] /
  /// 3.0 width language as [_paintTargetEdge].
  void _paintShadeSelectionOutlines(
    Canvas canvas,
    Map<String, Path> pathCache,
  ) {
    final selected = selectionDrag.value;
    if (selected.isEmpty) return;

    final accentPaint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeJoin = StrokeJoin.round;

    for (final id in selected) {
      final path = pathCache[id];
      if (path == null) continue;
      canvas.drawPath(path, accentPaint);
    }
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

  /// Draws the live なぞりモード stroke, if any, as a plain accent-colored
  /// line — deliberately the simplest possible rendering (no per-point
  /// dots, no snap highlighting) so every `onPointerMove`/`onScaleUpdate`
  /// only ever costs an `O(1)` `Path.lineTo` plus this one `drawPath`, not
  /// an `O(n)` walk of every point traced so far.
  void _paintTracePreview(Canvas canvas) {
    final path = tracePreview.path;
    if (path == null) return;
    final strokePaint = Paint()
      ..color = Colors.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);
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
        oldDelegate.canvasBrightness != canvasBrightness ||
        oldDelegate.tracePreview != tracePreview ||
        oldDelegate.selectionDrag != selectionDrag ||
        oldDelegate.highlightStyle != highlightStyle ||
        oldDelegate.isPreviewMode != isPreviewMode ||
        oldDelegate.isShadeXRay != isShadeXRay;
  }
}
