import 'package:flutter/foundation.dart';

/// Presentation-only fill alpha for Draw/Edit underlays and Shade X-Ray
/// (Select tool). Preview and Shade Solid/Light paint opaque fills and do
/// not use this style.
///
/// Core shading / hit-testing must not read these constants. Swap or tune
/// appearance here (or via a theme later) without touching geometry code.
/// Deliberately omits chromatic colors and dashed strokes (Phase Select).
@immutable
class PolygonHighlightStyle {
  const PolygonHighlightStyle({
    required this.fillAlpha,
  });

  /// Default neutral chrome: ~30% fill (Draw/Edit + Shade X-Ray underlay).
  static const neutral = PolygonHighlightStyle(
    fillAlpha: 77,
  );

  /// Underlay fill opacity 0–255 shared by Draw/Edit and Shade X-Ray.
  final int fillAlpha;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PolygonHighlightStyle && other.fillAlpha == fillAlpha);
  }

  @override
  int get hashCode => fillAlpha.hashCode;
}
