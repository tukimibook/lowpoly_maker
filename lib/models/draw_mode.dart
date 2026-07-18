/// Sub-mode of [CanvasMode.draw] (Phase F, `.cursor/plans/plan_phase_F.md`):
/// how a 1-finger gesture on the canvas turns into draft vertices.
///
/// - [tap]: the original behavior — each tap/drag-and-release places (or
///   snaps/welds) exactly one point (see `CanvasNotifier.handleDrawTap`).
/// - [trace]: "なぞりモード" — a single continuous finger-down stroke is
///   resampled into evenly spaced points along its length (see
///   `generateTracePoints`/`CanvasNotifier.commitTraceStroke`) and
///   committed as one batch the moment the finger lifts. A pseudo
///   double-tap never implicitly closes a shape in this mode — closing
///   stays an explicit toolbar action either way.
enum DrawMode { tap, trace }
