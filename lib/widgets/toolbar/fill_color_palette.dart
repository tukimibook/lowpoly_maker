import 'package:flutter/material.dart';

/// Horizontal strip of circular fill-color swatches.
///
/// Presentation-only: callers decide what [highlightedColor] means (pen
/// color in draw mode, target polygon fill in edit mode) and what
/// [onColorSelected] does. Keeps toolbar rows free of duplicated swatch
/// markup while leaving [CanvasNotifier] / providers out of this widget.
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
        final isSelected = color == highlightedColor;
        return Tooltip(
          message: 'Fill color',
          child: GestureDetector(
            onTap: () => onColorSelected(color),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.black87 : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
