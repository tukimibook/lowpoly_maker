import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/underlay_image_provider.dart';
import '../../providers/underlay_layout_provider.dart';
import '../../providers/viewport_provider.dart';
import 'underlay_painter.dart';

/// The underlay's own paint layer, stacked *behind* [PolygonCanvas]'s
/// painter (see `polygon_canvas.dart`).
///
/// Wrapped in its own [RepaintBoundary] so that panning/zooming the
/// underlay (once that gesture exists) — or just an opacity/visibility
/// change — doesn't force Flutter to also repaint the polygon layer above
/// it, and vice versa: editing polygons never repaints this (potentially
/// large, decoded-bitmap) layer.
class UnderlayLayer extends ConsumerWidget {
  const UnderlayLayer({super.key, required this.size});

  final Size size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Registers the fit-to-canvas side effect exactly once for the
    // session (see `underlay_image_provider.dart`) — its own value is
    // never read.
    ref.watch(underlayFitCoordinatorProvider);

    final image = ref.watch(underlayImageProvider).valueOrNull;
    final layout = ref.watch(underlayLayoutProvider);
    final viewport = ref.watch(viewportProvider);

    return RepaintBoundary(
      child: CustomPaint(
        size: size,
        painter: UnderlayPainter(image: image, layout: layout, viewport: viewport),
      ),
    );
  }
}
