import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/polygon_shape.dart';

/// Raw cycle position for the edit mode's "切り離す対象を切り替え"
/// (`Icons.autorenew`) button — see `.cursor/plans/plan_phase_H_alpha.md`,
/// 2026-07-16 検討メモ.
///
/// Deliberately an unclamped counter rather than a validated "current
/// target" value: [resolveDetachTarget] always takes it modulo the
/// *current* candidate count, so every read is safe no matter how stale the
/// counter is (e.g. right after a detach shrinks the candidate list by
/// one) — nothing here ever needs to reach into `CanvasNotifier`'s artwork
/// just to keep this counter in range. Call sites still reset it to `0`
/// whenever the selected vertex changes, or right after a detach fires —
/// not because leaving it stale would misbehave, but so a *fresh*
/// selection predictably starts at the first candidate instead of
/// wherever a previous selection happened to leave it.
final detachCycleIndexProvider = StateProvider<int>((ref) => 0);

/// One "owner" a shared vertex can be detached from: either a confirmed
/// polygon (identified by [polygonId]) or the in-progress draft
/// ([isDraft]). Exactly one of the two is meaningful at a time.
typedef DetachTarget = ({String? polygonId, bool isDraft});

/// Resolves which owner [rawCycleIndex] currently points at, out of
/// [referencingPolygons] followed by the open draft (if [draftReferences]).
///
/// A pure function — like `fitUnderlayToCanvas`/`findNearestPoint` — so
/// both the toolbar's cycle/execute buttons ([EditorToolbar]) and
/// [PolygonPainter]'s highlight always agree on the exact same target;
/// neither ever builds its own candidate ordering, which is what keeps the
/// on-canvas highlight and the "切り離し実行" button from ever disagreeing
/// about which shape is currently selected.
///
/// Returns `null` only when there is nothing to detach from at all (an
/// empty candidate set) — callers should not be showing the detach
/// controls in that case to begin with.
DetachTarget? resolveDetachTarget({
  required List<PolygonShape> referencingPolygons,
  required bool draftReferences,
  required int rawCycleIndex,
}) {
  final total = referencingPolygons.length + (draftReferences ? 1 : 0);
  if (total == 0) return null;

  final index = rawCycleIndex % total;
  if (index < referencingPolygons.length) {
    return (polygonId: referencingPolygons[index].id, isDraft: false);
  }
  return (polygonId: null, isDraft: true);
}
