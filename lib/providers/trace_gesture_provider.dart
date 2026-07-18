import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Grace window a fresh, still-unmoving single finger is given before
/// なぞりモード ("trace mode") commits to treating it as the start of a
/// trace stroke (Phase F, `.cursor/plans/plan_phase_F.md`) — see
/// [TraceGestureController]'s doc for the conflict this exists to resolve.
/// Tunable: most real strokes never wait this long, since
/// [kTraceGraceSlop] confirms early the moment deliberate movement is
/// detected; this mainly matters for a stroke that starts by holding
/// almost, but not perfectly, still.
const Duration kTraceGraceWindow = Duration(milliseconds: 120);

/// Screen-pixel movement (unscaled — like [kTraceGraceWindow], this is
/// about how far a finger has physically travelled, not artwork geometry,
/// so it does not follow the `/ viewport.scale` convention
/// `kVertexHitRadius` et al. use) beyond which a still-single finger is
/// unambiguously "drawing", confirming the trace lock immediately without
/// waiting for [kTraceGraceWindow] to elapse.
const double kTraceGraceSlop = 10.0;

enum TraceLockPhase {
  /// No finger currently down for a trace-mode gesture.
  idle,

  /// A single finger is down and might still turn out to be the start of
  /// a 2-finger pinch/pan — see [TraceGestureController.beginDisambiguation].
  awaitingDisambiguation,

  /// Confirmed as a genuine trace stroke. From here until the locked
  /// finger lifts, every *other* pointer is ignored outright — including
  /// for viewport pinch/pan purposes ("Lock & Ignore").
  locked,
}

/// Resolves the conflict between two UX goals that would otherwise fight
/// over the very first moment a finger touches down in trace mode:
/// - A genuine 2-finger pinch/pan (`ViewportGestureController`, Phase Hβ)
///   must still reliably trigger — but a real pinch's second finger almost
///   never lands in *exactly* the same frame as the first, so something
///   must give that second finger a brief chance to arrive before trace
///   mode commits to the first one alone.
/// - Once a trace stroke has clearly begun, every drawing app's standard
///   "Lock & Ignore" UX applies: further fingers touching down must be
///   ignored outright (no accidental zoom, no accidental second stroke)
///   until the traced finger itself lifts.
///
/// [PolygonCanvas]'s trace-mode gesture handling resolves this with a
/// short-lived [TraceLockPhase.awaitingDisambiguation] window — driven by
/// *this* controller's [beginDisambiguation]/[maybeConfirmBySlop] — during
/// which the *existing*, unmodified Hβ `isViewportGesture()` signal (see
/// `viewport_gesture_provider.dart`) is still free to hijack the gesture
/// into a pinch/pan, exactly as it already does for draw/eraser/edit
/// modes. Only once that window elapses (or the single finger moves
/// enough to be unambiguous) does this flip to [TraceLockPhase.locked],
/// at which point the *raw* pointer stream (a [Listener], bypassing the
/// gesture arena and `ScaleGestureRecognizer`'s multi-finger focal-point
/// fusion entirely) takes over sourcing the stroke's points, and every
/// pointer other than [isTrackedPointer]'s one is ignored until it lifts.
///
/// A plain class (not a [Listenable]) rather than a [ValueNotifier] like
/// `ViewportGestureController`/`DragPreviewController`: nothing needs to
/// rebuild or repaint off *this* controller's phase directly — only the
/// trace stroke's own points (`TraceStrokePreviewController`) matter for
/// rendering. It still lives behind a stable [Provider], never as a local
/// variable inside `PolygonCanvas.build()`, for the same reason every
/// other per-gesture controller does: `build()` reruns on any unrelated
/// `ref.watch` change, which would otherwise silently drop a `Timer`
/// reference or reset [phase] mid-gesture.
class TraceGestureController {
  TraceLockPhase _phase = TraceLockPhase.idle;
  int? _pendingPointerId;
  int? _lockedPointerId;
  Offset? _disambiguationStart;
  Timer? _graceTimer;

  TraceLockPhase get phase => _phase;
  bool get isLocked => _phase == TraceLockPhase.locked;
  bool get isAwaitingDisambiguation =>
      _phase == TraceLockPhase.awaitingDisambiguation;

  /// Records [pointerId] as the very first finger down for this gesture,
  /// if none has been recorded yet since the last [reset] — called from a
  /// raw [Listener.onPointerDown], which (unlike `ScaleStartDetails`) is
  /// the only place an actual per-pointer ID is available. A second (or
  /// later) finger touching down calls this too, but the `??=` makes it a
  /// no-op: only the first finger of the gesture is ever tracked.
  void onPointerDown(int pointerId) {
    _pendingPointerId ??= pointerId;
  }

  /// Starts the disambiguation window for a fresh single-finger touch,
  /// screen-space [startPosition] for [maybeConfirmBySlop] to measure
  /// movement from. [onGraceElapsed] fires once [kTraceGraceWindow]
  /// elapses with no earlier [confirmLock] (via slop) or [reset] (a real
  /// pinch hijacking the gesture, or an early release).
  void beginDisambiguation(Offset startPosition, VoidCallback onGraceElapsed) {
    _graceTimer?.cancel();
    _phase = TraceLockPhase.awaitingDisambiguation;
    _disambiguationStart = startPosition;
    _graceTimer = Timer(kTraceGraceWindow, onGraceElapsed);
  }

  /// Confirms early, without waiting for [kTraceGraceWindow] to elapse,
  /// once movement from [beginDisambiguation]'s `startPosition` exceeds
  /// [kTraceGraceSlop]. No-op outside [TraceLockPhase.awaitingDisambiguation]
  /// (including once already [locked], so a caller need not guard first).
  void maybeConfirmBySlop(Offset currentPosition) {
    if (!isAwaitingDisambiguation) return;
    final start = _disambiguationStart;
    if (start != null && (currentPosition - start).distance > kTraceGraceSlop) {
      confirmLock();
    }
  }

  /// Confirms this gesture as a genuine trace stroke, locking onto
  /// whichever pointer [onPointerDown] saw first. Idempotent — calling it
  /// again (e.g. the grace timer firing just after [maybeConfirmBySlop]
  /// already confirmed it) is a no-op.
  void confirmLock() {
    if (isLocked) return;
    _graceTimer?.cancel();
    _lockedPointerId = _pendingPointerId;
    _phase = TraceLockPhase.locked;
  }

  /// True while [pointerId] is the one pointer trace mode is currently
  /// paying attention to — either the not-yet-confirmed first finger
  /// ([TraceLockPhase.awaitingDisambiguation]) or the confirmed, locked one
  /// ([TraceLockPhase.locked]). Every other pointer — any second (or
  /// later) finger, at any point in the gesture — must be ignored outright
  /// by the caller: no preview update, no lock, no commit.
  bool isTrackedPointer(int pointerId) {
    if (isLocked) return pointerId == _lockedPointerId;
    if (isAwaitingDisambiguation) return pointerId == _pendingPointerId;
    return false;
  }

  /// Aborts back to [TraceLockPhase.idle] — either a real pinch/pan
  /// hijacked the gesture during disambiguation, the tracked finger lifted
  /// (confirmed or not), or the physical gesture otherwise ended.
  void reset() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _phase = TraceLockPhase.idle;
    _pendingPointerId = null;
    _lockedPointerId = null;
    _disambiguationStart = null;
  }

  /// Cancels any pending [Timer] — call from `ref.onDispose`, mirroring
  /// every other gesture controller's cleanup.
  void dispose() {
    _graceTimer?.cancel();
    _graceTimer = null;
  }
}

/// Provides the single, stable [TraceGestureController] instance for the
/// current editing session.
final traceGestureProvider = Provider<TraceGestureController>((ref) {
  final controller = TraceGestureController();
  ref.onDispose(controller.dispose);
  return controller;
});
