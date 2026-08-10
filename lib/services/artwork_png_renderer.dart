import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/artwork.dart';
import '../models/polygon_shape.dart';

/// Plain white — the default finished-artwork export background. The editing
/// aid `canvasBackgroundProvider` (Phase B3) has no bearing on export.
const Color kExportBackgroundColor = Color(0xFFFFFFFF);

/// Fully transparent export background — used when the artist picks
/// "Transparent" in the export dialog (Phase Hδ). Same alpha-zero sentinel
/// as `kClearFillColor`; with this background, clear-filled polygons read
/// as true holes in the PNG.
const Color kExportTransparentBackgroundColor = Color(0x00000000);

/// Long-edge cap (px) for [ArtworkPngRenderer] output — Phase Hδ OOM guard.
/// v1 "標準PNG"; higher ceilings belong to a future hi-res entitlement.
const int kExportMaxLongEdgePx = 2048;

/// Uniform output size for [canvasSize] under [maxLongEdge].
///
/// Derives **one** scale from the long edge, then applies that same scale to
/// both axes before rounding — never clamps width/height independently
/// (which would distort aspect ratio).
@visibleForTesting
({double scale, int width, int height}) exportOutputSizeFor(
  Size canvasSize, {
  int maxLongEdge = kExportMaxLongEdgePx,
}) {
  final longEdge = math.max(canvasSize.width, canvasSize.height);
  final scale = longEdge > maxLongEdge ? maxLongEdge / longEdge : 1.0;
  return (
    scale: scale,
    width: (canvasSize.width * scale).round(),
    height: (canvasSize.height * scale).round(),
  );
}

/// Renders [Artwork]'s confirmed geometry into a standalone PNG — the
/// Phase Hδ "標準PNG" export.
///
/// Deliberately **not** built on `ThumbnailCaptureService`
/// (`RepaintBoundary`/`GlobalKey`, Phase Hγ): that path always captures
/// exactly what's on screen right now, underlay and all, at editing-time
/// styling (translucent fill so the sketch/underlay show through, plus
/// selection/handle/highlight chrome). An export needs none of that —
/// just the plain, fully opaque polygons — and needs to work with no
/// mounted widget at all (e.g. from a background export queue later). So
/// this instead draws directly with a fresh [ui.PictureRecorder], mirroring
/// `PolygonPainter._paintPolygon`'s fill+stroke but skipping every other
/// editing-only layer (draft, vertex hints, drag previews, highlights) —
/// see [PolygonPainter] for why those exist at all.
///
/// [draftVertexIds]/in-progress shapes are intentionally never painted:
/// an unclosed shape isn't a real polygon yet ([PolygonShape] requires >=3
/// vertex IDs), so there is nothing well-defined to fill/stroke for it.
///
/// Large canvases are uniformly scaled down so the long edge never exceeds
/// [kExportMaxLongEdgePx] before `toImage` (OOM guard). Geometry is still
/// issued in world coordinates after `canvas.scale` — never by shrinking
/// only the `toImage` arguments (that would crop, not scale).
class ArtworkPngRenderer {
  /// Renders [artwork] at [canvasSize] (the artwork's own world-coordinate
  /// canvas size — see `CanvasSizeController`'s doc for why this is tracked
  /// outside `Artwork` itself) and returns PNG-encoded bytes, or `null` if
  /// [canvasSize] is empty (nothing sensible to render — e.g. called before
  /// the canvas has ever laid out).
  ///
  /// [backgroundColor] is a one-shot export choice (White / Transparent) —
  /// never read from or written to the artwork document.
  Future<Uint8List?> render(
    Artwork artwork,
    Size canvasSize, {
    Color backgroundColor = kExportBackgroundColor,
  }) async {
    if (canvasSize.isEmpty) return null;

    final output = exportOutputSizeFor(canvasSize);
    // Cull hint matches the final pixel grid; world geometry is drawn after
    // [scale] so `toImage(width, height)` rasterizes the full frame (not a
    // top-left crop).
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, output.width.toDouble(), output.height.toDouble()),
    );
    if (output.scale != 1.0) {
      canvas.scale(output.scale);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
      Paint()..color = backgroundColor,
    );
    for (final polygon in artwork.polygons) {
      _paintPolygon(canvas, artwork, polygon);
    }
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(output.width, output.height);
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  void _paintPolygon(Canvas canvas, Artwork artwork, PolygonShape polygon) {
    if (polygon.vertexIds.length < 3) return;
    final positions = [
      for (final id in polygon.vertexIds)
        if (artwork.vertices[id] != null) artwork.vertices[id]!.position,
    ];
    if (positions.length < 3) return;

    final path = Path()..moveTo(positions.first.dx, positions.first.dy);
    for (final position in positions.skip(1)) {
      path.lineTo(position.dx, position.dy);
    }
    path.close();

    canvas.drawPath(path, Paint()..color = polygon.fillColor..style = PaintingStyle.fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = polygon.strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = polygon.strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }
}
