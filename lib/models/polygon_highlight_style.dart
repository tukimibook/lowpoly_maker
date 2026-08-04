import 'package:flutter/foundation.dart';

/// Presentation-only fill alphas for polygon selection chrome.
///
/// Core shading / hit-testing must not read these constants. Swap or tune
/// appearance here (or via a theme later) without touching geometry code.
/// Deliberately omits chromatic colors and dashed strokes (Phase Select).
@immutable
class PolygonHighlightStyle {
  const PolygonHighlightStyle({
    required this.fillAlpha,
    required this.selectedFillAlpha,
  });

  /// Default neutral chrome: ~30% fill, ~63% when selected.
  static const neutral = PolygonHighlightStyle(
    fillAlpha: 77,
    selectedFillAlpha: 160,
  );

  /// Normal (unselected) polygon fill opacity 0–255.
  final int fillAlpha;

  /// Shade-selection (and similar) fill opacity 0–255.
  final int selectedFillAlpha;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PolygonHighlightStyle &&
            other.fillAlpha == fillAlpha &&
            other.selectedFillAlpha == selectedFillAlpha);
  }

  @override
  int get hashCode => Object.hash(fillAlpha, selectedFillAlpha);
}
