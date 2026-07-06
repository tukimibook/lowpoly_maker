import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/canvas_mode.dart';
import '../../providers/canvas_provider.dart';
import 'polygon_painter.dart';

/// The drawable surface: renders confirmed polygons and the in-progress
/// draft, and interprets taps according to the current [CanvasMode]:
/// - [CanvasMode.draw]: place/extend/close polygons.
/// - [CanvasMode.eraser]: delete a single tapped vertex.
///
/// Coordinates handled here are treated as world coordinates directly;
/// viewport zoom/pan is layered on top in a later phase.
class PolygonCanvas extends ConsumerWidget {
  const PolygonCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = ref.watch(canvasProvider);
    final mode = ref.watch(canvasModeProvider);
    final notifier = ref.read(canvasProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          notifier.setCanvasSize(size);
        });

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            if (mode == CanvasMode.eraser) {
              notifier.handleEraseTap(details.localPosition);
              return;
            }

            final fillColor = ref.read(selectedFillColorProvider);
            final matchedColor = notifier.handleDrawTap(
              details.localPosition,
              fillColor: fillColor,
            );
            if (matchedColor != null) {
              // A new draft was started from an existing vertex; match the
              // color picker to that polygon's color as a convenience.
              ref.read(selectedFillColorProvider.notifier).state = matchedColor;
            }
          },
          child: CustomPaint(
            size: size,
            painter: PolygonPainter(artwork: artwork, mode: mode),
          ),
        );
      },
    );
  }
}
