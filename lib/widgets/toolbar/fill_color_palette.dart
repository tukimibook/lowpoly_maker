import 'package:flutter/material.dart';

import '../../providers/canvas_provider.dart' show kClearFillColor;

/// Horizontal strip of circular fill-color swatches.
///
/// Presentation-only: callers decide what [highlightedColor] means (pen
/// color in draw mode, target polygon fill in edit mode) and what
/// [onColorSelected] does. Keeps toolbar rows free of duplicated swatch
/// markup while leaving [CanvasNotifier] / providers out of this widget.
///
/// [kClearFillColor] swatches render as a Figma-style "no fill" glyph
/// (light disc + diagonal slash) instead of an invisible transparent circle.
class FillColorPalette extends StatelessWidget {
  const FillColorPalette({
    super.key,
    required this.colors,
    required this.onColorSelected,
    this.highlightedColor,
  });

  final List<Color> colors;
  final Color? highlightedColor;
  final ValueChanged<Color> onColorSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: colors.length,
      separatorBuilder: (context, index) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        final color = colors[index];
        final isClear = color == kClearFillColor;
        final isSelected = color == highlightedColor;
        return Tooltip(
          message: isClear ? 'No fill' : 'Fill color',
          child: GestureDetector(
            onTap: () => onColorSelected(color),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isClear ? Colors.white : color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? Colors.black87
                      : (isClear ? Colors.black26 : Colors.transparent),
                  width: isSelected || isClear ? (isSelected ? 3 : 1) : 3,
                ),
              ),
              child: isClear
                  ? const CustomPaint(painter: _ClearSwatchPainter())
                  : null,
            ),
          ),
        );
      },
    );
  }
}

/// Diagonal red slash over a clear swatch — Figma "no fill" cue.
class _ClearSwatchPainter extends CustomPainter {
  const _ClearSwatchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE53935)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final inset = size.shortestSide * 0.22;
    canvas.drawLine(
      Offset(inset, size.height - inset),
      Offset(size.width - inset, inset),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ClearSwatchPainter oldDelegate) => false;
}
