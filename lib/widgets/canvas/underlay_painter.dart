import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/underlay_layout.dart';
import '../../services/coordinate_transform.dart';

/// Paints the decoded underlay photo (if any) behind everything else on the
/// canvas, respecting [layout]'s placement/opacity/visibility and the
/// shared [viewport] (pan/zoom) transform — the same `translate`+`scale`
/// [PolygonPainter] applies for polygons, so the underlay pans/zooms in
/// lockstep with the artwork once Phase Hβ's gesture lands.
class UnderlayPainter extends CustomPainter {
  UnderlayPainter({
    required this.image,
    required this.layout,
    required this.viewport,
  }) : super(repaint: Listenable.merge([layout, viewport]));

  /// The decoded photo, or `null` before one has been picked/decoded — in
  /// which case nothing is painted regardless of [layout].
  final ui.Image? image;
  final ValueListenable<UnderlayLayout> layout;
  final ValueListenable<ViewportTransform> viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final currentImage = image;
    final currentLayout = layout.value;
    if (currentImage == null || !currentLayout.visible || currentLayout.opacity <= 0) {
      return;
    }

    final transform = viewport.value;
    canvas.save();
    canvas.translate(transform.offset.dx, transform.offset.dy);
    canvas.scale(transform.scale);
    canvas.translate(currentLayout.offset.dx, currentLayout.offset.dy);
    canvas.scale(currentLayout.scale);

    final paint = Paint()..color = Color.fromRGBO(255, 255, 255, currentLayout.opacity);
    canvas.drawImage(currentImage, Offset.zero, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant UnderlayPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.layout != layout ||
        oldDelegate.viewport != viewport;
  }
}
