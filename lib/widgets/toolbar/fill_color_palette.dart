import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../providers/canvas_provider.dart' show kClearFillColor;

/// Rough per-item stride for the Stage-2 scroll fallback only.
/// Intentionally not a precise layout model — [Scrollable.ensureVisible]
/// owns the final pixel position after the target is built.
const double _kRoughSwatchStride = 40.0;

/// Expanded [ListView] cache so accordion members near the viewport are
/// usually already laid out when Stage-1 [Scrollable.ensureVisible] runs.
const double _kPaletteCacheExtentPixels = 500.0;

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
/// family into view after expansion via a two-stage strategy (ensureVisible
/// when built, else rough [ScrollController.animateTo] then ensureVisible).
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
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FillColorPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollToIndex != null &&
        widget.scrollToIndex != oldWidget.scrollToIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollAnchorIntoView(widget.scrollToIndex!);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.scrollToIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollAnchorIntoView(widget.scrollToIndex!);
      });
    }
  }

  /// Two-stage scroll: prefer measured [Scrollable.ensureVisible]; if the
  /// anchor is not built yet, rough-jump then ensureVisible once. No retry
  /// loop — missing context after the jump is a quiet no-op.
  Future<void> _scrollAnchorIntoView(int index) async {
    if (_tryEnsureVisible()) return;

    if (!_scrollController.hasClients) return;

    final max = _scrollController.position.maxScrollExtent;
    final rough = (index * _kRoughSwatchStride).clamp(0.0, max);
    await _scrollController.animateTo(
      rough,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
    if (!mounted) return;

    // One more frame so the ListView can build the newly nearby children.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _tryEnsureVisible();
  }

  bool _tryEnsureVisible() {
    final ctx = _scrollAnchorKey.currentContext;
    if (ctx == null) return false;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
    return true;
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
    return ListView.separated(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      scrollCacheExtent: const ScrollCacheExtent.pixels(_kPaletteCacheExtentPixels),
      itemCount: widget.colors.length,
      separatorBuilder: (context, index) {
        final tight = _inFamily(index) && _inFamily(index + 1);
        final gap = tight ? 4.0 : 10.0;
        return SizedBox(
          width: gap,
          child: tight
              ? const ColoredBox(color: Color(0x14000000))
              : null,
        );
      },
      itemBuilder: (context, index) => _buildSwatch(index),
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
