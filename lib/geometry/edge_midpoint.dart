import 'dart:ui';

/// The midpoint of the straight segment from [start] to [end] — the
/// insertion point [CanvasNotifier.insertVertexAtEdge] places a new vertex
/// at when subdividing one of a polygon's edges (edit mode's "➕ ここに追加"
/// button, see `.cursor/plans/plan_phase_H_alpha.md`, 2026-07-16 検討メモ).
///
/// Deliberately its own top-level function — like `findNearestPoint`/
/// `fitUnderlayToCanvas` — even though the computation itself is a single
/// line: keeping it pure and separate from [CanvasNotifier] means it can be
/// unit-tested directly, with no `Artwork`/vertex-pool setup required.
Offset edgeMidpoint(Offset start, Offset end) => (start + end) / 2;
