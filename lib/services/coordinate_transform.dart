import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Pure screen&lt;-&gt;world coordinate mapping for the canvas viewport
/// (pan + zoom). Rotation is intentionally not supported — polygon art
/// doesn't need it, and leaving it out keeps the transform (and every call
/// site that uses it) simple.
///
/// Vertices are always stored in world coordinates ([Vertex.position]); this
/// is the single seam every screen-space input (taps, drags) and every
/// screen-space render (canvas drawing) is meant to go through, so a later
/// pinch-zoom/pan gesture only ever needs to update the [ViewportTransform]
/// itself rather than touching drawing or hit-testing logic.
///
/// As of Phase B this seam exists but is not yet driven by any gesture —
/// [ViewportController] (see `viewport_provider.dart`) is pinned to
/// [identity], so screen and world coordinates coincide exactly as they did
/// before. Pinch-zoom/pan wiring is added in a later phase.
@immutable
class ViewportTransform {
  const ViewportTransform({this.scale = 1.0, this.offset = Offset.zero});

  /// Identity transform: screen coordinates equal world coordinates.
  static const ViewportTransform identity = ViewportTransform();

  /// Zoom factor applied to world coordinates when rendering (world units
  /// per screen pixel is `1 / scale`).
  final double scale;

  /// Screen-space translation applied *after* scaling, i.e. the screen
  /// position that world coordinate (0, 0) currently renders at.
  final Offset offset;

  /// Converts a point in screen (widget-local) coordinates into world
  /// coordinates — the inverse of [worldToScreen]. Used to interpret taps
  /// and drags, which always arrive in screen space, as positions on the
  /// artwork.
  Offset screenToWorld(Offset screenPosition) {
    return (screenPosition - offset) / scale;
  }

  /// Converts a point in world coordinates into screen (widget-local)
  /// coordinates — the inverse of [screenToWorld]. Matches the
  /// `canvas.translate(offset)` + `canvas.scale(scale)` applied when
  /// painting (see `PolygonPainter`), so this and the painter never drift
  /// apart.
  Offset worldToScreen(Offset worldPosition) {
    return worldPosition * scale + offset;
  }

  ViewportTransform copyWith({double? scale, Offset? offset}) {
    return ViewportTransform(
      scale: scale ?? this.scale,
      offset: offset ?? this.offset,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ViewportTransform &&
            other.scale == scale &&
            other.offset == offset);
  }

  @override
  int get hashCode => Object.hash(scale, offset);

  @override
  String toString() => 'ViewportTransform(scale: $scale, offset: $offset)';
}
