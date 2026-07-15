import 'dart:math' as math;
import 'dart:ui';

import '../models/underlay_layout.dart';

/// Computes the [UnderlayLayout] that "contain"-fits [imageSize] (the
/// underlay photo's natural pixel dimensions) inside [canvasSize], centered
/// on both axes — v1's *only* way an underlay's [UnderlayLayout.offset]/
/// `.scale` are ever produced (see that class's doc for why there's no
/// pinch/pan UI yet).
///
/// A pure function, like the rest of `geometry/`, so the fit math is
/// unit-testable without touching image decoding, providers, or widgets.
/// Called once per import, and again whenever the canvas is resized (e.g.
/// device rotation) — see `underlay_image_provider.dart`.
///
/// [opacity]/[visible] are passed through unchanged (defaulting to fully
/// opaque/visible) so re-fitting after a resize doesn't reset whatever the
/// artist chose in the settings sheet.
///
/// Returns [UnderlayLayout.initial] (scaled/offset by nothing) if either
/// size is degenerate (zero or negative on any axis) — e.g. before the
/// canvas has reported its first layout, or a corrupt image reports a
/// zero-sized frame — rather than dividing by zero.
UnderlayLayout fitUnderlayToCanvas({
  required Size imageSize,
  required Size canvasSize,
  double opacity = 1.0,
  bool visible = true,
}) {
  if (imageSize.width <= 0 ||
      imageSize.height <= 0 ||
      canvasSize.width <= 0 ||
      canvasSize.height <= 0) {
    return UnderlayLayout(offset: Offset.zero, scale: 1.0, opacity: opacity, visible: visible);
  }

  final scale = math.min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height);
  final fittedSize = imageSize * scale;
  final offset = Offset(
    (canvasSize.width - fittedSize.width) / 2,
    (canvasSize.height - fittedSize.height) / 2,
  );

  return UnderlayLayout(offset: offset, scale: scale, opacity: opacity, visible: visible);
}
