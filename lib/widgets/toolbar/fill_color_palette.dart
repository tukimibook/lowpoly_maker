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
///
/// Role-stable [itemKeys] prevent [AnimatedContainer] color morphing when
/// the list inserts/removes accordion stops mid-strip. Optional
/// [familyStart]/[familyEnd] tighten separators and paint a shared chip
/// behind the expanded Shade accordion; [scrollToIndex] scrolls that
/// family into view after expansion.
///
/// Uses a [Row] inside [SingleChildScrollView] (not [ListView]) so every
/// swatch is always built — the strip is short (≤ ~12 items) and tests /
/// [Scrollable.ensureVisible] need stable element keys off-screen.
class FillColorPalette extends StatefulWidget {
  const FillColorPalette({
    super.key,
    required this.colors,
    required this.onColorSelected,
    this.highlightedColor,
    this.itemKeys,
    this.familyStart,
    this.familyEnd,
    this.scrollToIndex,
  }) : assert(
          itemKeys == null || itemKeys.length == colors.length,
          'itemKeys length must match colors',
        );

  final List<Color> colors;
  final Color? highlightedColor;
  final ValueChanged<Color> onColorSelected;

  /// Stable keys per swatch (role + color). When null, keys are derived
  /// from color only (fine for static Draw/Edit palettes).
  final List<Key>? itemKeys;

  /// Inclusive index range of the Shade accordion family, or both null.
  final int? familyStart;
  final int? familyEnd;

  /// When this index changes (accordion expand / base switch), scroll so
  /// the swatch at that index is visible.
  final int? scrollToIndex;

  @override
  State<FillColorPalette> createState() => _FillColorPaletteState();
}

class _FillColorPaletteState extends State<FillColorPalette> {
  /// Single anchor for [Scrollable.ensureVisible] — not used as identity
  /// for every row (that would fight index shifts).
  final GlobalKey _scrollAnchorKey = GlobalKey();

  @override
  void didUpdateWidget(covariant FillColorPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollToIndex != null &&
        widget.scrollToIndex != oldWidget.scrollToIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureScrollAnchorVisible();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.scrollToIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureScrollAnchorVisible();
      });
    }
  }

  void _ensureScrollAnchorVisible() {
    final ctx = _scrollAnchorKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  bool _inFamily(int index) {
    final start = widget.familyStart;
    final end = widget.familyEnd;
    if (start == null || end == null) return false;
    return index >= start && index <= end;
  }

  Widget _buildSwatch(int index) {
    final color = widget.colors[index];
    final isClear = color == kClearFillColor;
    final isSelected = color == widget.highlightedColor;
    final inFamily = _inFamily(index);
    final isFamilyAnchor = inFamily &&
        widget.scrollToIndex != null &&
        index == widget.scrollToIndex;
    final isRamp = inFamily && !isFamilyAnchor && !isClear;
    final itemKeys = widget.itemKeys;
    final swatchKey = itemKeys?[index] ?? ValueKey(('swatch', color));
    final size = isRamp ? 34.0 : 40.0;

    Widget swatch = Tooltip(
      message: isClear ? 'No fill' : 'Fill color',
      child: GestureDetector(
        key: swatchKey,
        onTap: () => widget.onColorSelected(color),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isClear ? Colors.white : color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Colors.black87
                  : (isFamilyAnchor
                      ? Colors.black54
                      : (isClear ? Colors.black26 : Colors.transparent)),
              width: isSelected
                  ? 3
                  : (isFamilyAnchor || isClear ? 1.5 : 3),
            ),
          ),
          child: isClear
              ? const CustomPaint(painter: _ClearSwatchPainter())
              : null,
        ),
      ),
    );

    if (inFamily) {
      swatch = ColoredBox(
        color: const Color(0x14000000),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Center(child: swatch),
        ),
      );
    }

    if (isFamilyAnchor) {
      swatch = KeyedSubtree(
        key: _scrollAnchorKey,
        child: swatch,
      );
    }

    return swatch;
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < widget.colors.length; i++) {
      if (i > 0) {
        final tight = _inFamily(i - 1) && _inFamily(i);
        final gap = tight ? 4.0 : 10.0;
        children.add(
          SizedBox(
            width: gap,
            child: tight
                ? const ColoredBox(color: Color(0x14000000))
                : null,
          ),
        );
      }
      children.add(_buildSwatch(i));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: children,
      ),
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
