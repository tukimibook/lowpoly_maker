import 'dart:ui';

import '../services/coordinate_transform.dart';

/// Lower/upper bounds [applyPinchPan] clamps [ViewportTransform.scale] to,
/// so a pinch can't zoom the artwork away to an unusable speck or blow it
/// up past the point where dragging around a single edge stops being
/// useful. Phase Hβ (`.cursor/plans/plan_phase_H_beta.md`).
const double kMinViewportScale = 0.2;
const double kMaxViewportScale = 8.0;

/// Computes the [ViewportTransform] a pinch/pan gesture update should
/// produce this frame.
///
/// [baselineTransform]/[baselineFocalPoint] are the viewport and
/// screen-space focal point captured once, at the start of the *current
/// gesture sub-cycle* — see `ViewportGestureBaseline`'s doc
/// (`providers/viewport_gesture_provider.dart`) for why "sub-cycle" rather
/// than "gesture": Flutter's own `ScaleGestureRecognizer` re-baselines its
/// own `scale`/`focalPoint` (and synthesizes an `onEnd`+`onStart` pair)
/// every time the number of fingers down changes, so by the time this is
/// called, [scale] and [focalPoint] are already relative to that same
/// fresh baseline — no manual jump-avoidance math needed here beyond using
/// the matching baseline.
///
/// The formula keeps the world point that sat under the fingers at the
/// start of the sub-cycle ([baselineTransform.screenToWorld]-ing
/// [baselineFocalPoint]) pinned under wherever [focalPoint] has moved to
/// since, while scaling around that same point — the standard "pinch to
/// zoom" feel, and exactly how a plain one-finger pan (`scale == 1`) falls
/// out of the same formula for free.
ViewportTransform applyPinchPan({
  required ViewportTransform baselineTransform,
  required Offset baselineFocalPoint,
  required double scale,
  required Offset focalPoint,
  double minScale = kMinViewportScale,
  double maxScale = kMaxViewportScale,
}) {
  final newScale = (baselineTransform.scale * scale).clamp(minScale, maxScale);
  final focalWorld = baselineTransform.screenToWorld(baselineFocalPoint);
  return ViewportTransform(
    scale: newScale,
    offset: focalPoint - focalWorld * newScale,
  );
}
