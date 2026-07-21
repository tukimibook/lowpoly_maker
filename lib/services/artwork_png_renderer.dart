import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/artwork.dart';
import '../models/polygon_shape.dart';

/// Plain white — the finished-artwork export always renders on a solid
/// canvas regardless of `canvasBackgroundProvider`'s light/dark toggle,
/// which only exists as an editing aid (Phase B3) and has no bearing on
/// what the artist actually drew.
const Color kExportBackgroundColor = Color(0xFFFFFFFF);

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
class ArtworkPngRenderer {
  /// Renders [artwork] at [canvasSize] (the artwork's own world-coordinate
  /// canvas size — see `CanvasSizeController`'s doc for why this is tracked
  /// outside `Artwork` itself) and returns PNG-encoded bytes, or `null` if
  /// [canvasSize] is empty (nothing sensible to render — e.g. called before
  /// the canvas has ever laid out).
  Future<Uint8List?> render(
    Artwork artwork,
    Size canvasSize, {
    Color backgroundColor = kExportBackgroundColor,
  }) async {
    if (canvasSize.isEmpty) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
      Paint()..color = backgroundColor,
    );
    for (final polygon in artwork.polygons) {
      _paintPolygon(canvas, artwork, polygon);
    }
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(
        canvasSize.width.round(),
        canvasSize.height.round(),
      );
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
