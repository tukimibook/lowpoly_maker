import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show GlobalKey;

/// Pixel ratio gallery thumbnails are captured at — deliberately much
/// lower than the device's own `devicePixelRatio`: a gallery grid tile
/// only ever displays this at a few hundred logical px, so capturing at
/// full canvas resolution would just waste disk space and encode time for
/// no visible benefit.
const double kThumbnailPixelRatio = 0.3;

/// Captures whatever is currently painted inside the [RepaintBoundary]
/// identified by a `GlobalKey` as PNG bytes — used to generate each
/// artwork's gallery thumbnail (Phase Hγ) from the live `PolygonCanvas`
/// (underlay + polygons together, exactly as currently displayed; see
/// `providers/canvas_capture_provider.dart` for the key that widget
/// attaches to its outer `RepaintBoundary`).
///
/// A thin, stateless wrapper around Flutter's own
/// [RenderRepaintBoundary.toImage] rather than a static function, so a
/// test (or `AutoSaveService`'s injected callback) can hold a reference to
/// it without needing a `BuildContext` in scope.
class ThumbnailCaptureService {
  /// Returns `null` if [key] isn't currently attached to a mounted
  /// [RepaintBoundary] (e.g. captured too early, or the editor was already
  /// disposed) — callers must treat that as "no thumbnail this time", not
  /// a crash (Phase Hγ #19 spirit: a capture failure must never break a
  /// save; see `AutoSaveService._safeCaptureThumbnail`).
  Future<Uint8List?> capture(
    GlobalKey key, {
    double pixelRatio = kThumbnailPixelRatio,
  }) async {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;

    final image = await renderObject.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
