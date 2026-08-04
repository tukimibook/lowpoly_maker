import 'package:flutter/foundation.dart';

/// Presentation-only fill alpha for Draw/Edit polygon chrome.
///
/// Core shading / hit-testing must not read these constants. Swap or tune
/// appearance here (or via a theme later) without touching geometry code.
/// Deliberately omits chromatic colors and dashed strokes (Phase Select).
/// Shade / preview modes paint fully opaque fills and do not use this style.
@immutable
class PolygonHighlightStyle {
  const PolygonHighlightStyle({
    required this.fillAlpha,
  });

  /// Default neutral chrome: ~30% fill (underlay for Draw/Edit).
  static const neutral = PolygonHighlightStyle(
    fillAlpha: 77,
  );

  /// Normal (unselected) polygon fill opacity 0–255 for Draw/Edit.
  final int fillAlpha;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PolygonHighlightStyle && other.fillAlpha == fillAlpha);
  }

  @override
  int get hashCode => fillAlpha.hashCode;
}
