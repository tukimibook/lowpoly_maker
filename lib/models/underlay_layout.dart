import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// The current on-canvas placement of the (single, v1) underlay photo:
/// where it sits, how big it is, how visible it is, and how opaque it is.
///
/// **v1 scope** (Phase Hα, 検討メモ 2026-07-15): [offset]/[scale] are only
/// ever set by [fitUnderlayToCanvas] (`geometry/underlay_fit.dart`) — once
/// per import, and again if the canvas is resized. There is no pinch/pan
/// UI to move or resize the underlay independently in v1: giving the
/// underlay its own competing 2-finger gesture would collide with Phase
/// Hβ's planned whole-canvas pinch-zoom (`onScale*` + `pointerCount`, see
/// `.cursor/plans/plan_future_phases.md`), so manual placement is deferred
/// until the underlay can simply ride along with that gesture instead of
/// needing one of its own. [toMatrix]/[worldToLocal] exist regardless, so
/// that seam (screen/world position -> position *within the underlay
/// image*) is already in place for a future feature (e.g. an eyedropper)
/// without redesigning this class then.
///
/// Deliberately a plain, hand-written value class — like [ViewportTransform]
/// in `services/coordinate_transform.dart` — rather than `freezed`: this is
/// rendering/presentation state, not one of the core persisted artwork
/// models ([Vertex], [PolygonShape], ...), and (per 検討メモ) is
/// deliberately kept out of `CanvasNotifier`'s undo stack for the same
/// reason.
@immutable
class UnderlayLayout {
  const UnderlayLayout({
    required this.offset,
    required this.scale,
    this.opacity = 1.0,
    this.visible = true,
  });

  /// Before any photo has been imported/fit — a harmless identity
  /// placement; nothing is drawn until a decoded image exists regardless
  /// (see `UnderlayLayer`).
  static const UnderlayLayout initial = UnderlayLayout(offset: Offset.zero, scale: 1.0);

  /// Top-left of the underlay image, in *world* coordinates — i.e. before
  /// [ViewportTransform] is applied, exactly like [Vertex.position].
  final Offset offset;

  /// Uniform scale factor from the underlay image's own (downsampled)
  /// pixels to world units. No rotation, matching [ViewportTransform]'s own
  /// "polygon art doesn't need it" reasoning.
  final double scale;

  /// 0.0 (fully transparent) – 1.0 (fully opaque). The v1 bottom-sheet UI
  /// only ever writes one of five discrete steps (20/40/60/80/100%, see
  /// `UnderlaySettingsSheet`), but the model itself accepts any value.
  final double opacity;

  /// Whether the underlay is painted at all. Kept independent of [opacity]
  /// so toggling it off and back on doesn't lose whichever opacity step was
  /// chosen.
  final bool visible;

  UnderlayLayout copyWith({
    Offset? offset,
    double? scale,
    double? opacity,
    bool? visible,
  }) {
    return UnderlayLayout(
      offset: offset ?? this.offset,
      scale: scale ?? this.scale,
      opacity: opacity ?? this.opacity,
      visible: visible ?? this.visible,
    );
  }

  /// The world -> underlay-local transform (translate then scale) as a
  /// [Matrix4], for call sites that want to compose it with other
  /// `package:vector_math`/`Transform`-widget matrices. Prefer
  /// [worldToLocal] for a plain point conversion — inverting a general
  /// [Matrix4] is needless overhead for a translate+uniform-scale-only
  /// transform like this one.
  Matrix4 toMatrix() {
    return Matrix4.identity()
      ..translateByDouble(offset.dx, offset.dy, 0.0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
  }

  /// Converts a *world*-space position (i.e. already run through
  /// [ViewportTransform.screenToWorld]) into a position relative to the
  /// underlay image's own top-left corner, at the image's native
  /// (post-downsample) pixel scale.
  ///
  /// Not read by any UI yet in v1 (see class doc) — added now so a future
  /// feature that needs to sample the underlay (e.g. an eyedropper) has a
  /// single, already-tested seam to go through, the same way vertex
  /// hit-testing already has exactly one seam ([findNearestPoint]).
  Offset worldToLocal(Offset worldPosition) {
    return (worldPosition - offset) / scale;
  }

  /// Serializes the placement fields intended for session helpers / tests.
  /// Document persistence uses `UnderlayLayoutPersist` (`underlay_ref.dart`)
  /// instead. [visible] is deliberately excluded (session-only).
  Map<String, Object?> toMap() {
    return {'offsetX': offset.dx, 'offsetY': offset.dy, 'scale': scale, 'opacity': opacity};
  }

  factory UnderlayLayout.fromMap(Map<String, Object?> map) {
    return UnderlayLayout(
      offset: Offset((map['offsetX'] as num).toDouble(), (map['offsetY'] as num).toDouble()),
      scale: (map['scale'] as num).toDouble(),
      opacity: (map['opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }

  /// Alias of [toMap] — named to match the `toJson`/`fromJson` naming used
  /// by [Artwork]/[Vertex]/[PolygonShape]'s `ArtworkDocument` serialization
  /// (Phase Hγ). Kept as a thin alias rather than a rename so existing
  /// [toMap]/[fromMap] call sites and tests are unaffected.
  Map<String, Object?> toJson() => toMap();

  /// Alias of [fromMap] — see [toJson].
  factory UnderlayLayout.fromJson(Map<String, Object?> json) => UnderlayLayout.fromMap(json);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UnderlayLayout &&
            other.offset == offset &&
            other.scale == scale &&
            other.opacity == opacity &&
            other.visible == visible);
  }

  @override
  int get hashCode => Object.hash(offset, scale, opacity, visible);

  @override
  String toString() {
    return 'UnderlayLayout(offset: $offset, scale: $scale, opacity: $opacity, visible: $visible)';
  }
}
