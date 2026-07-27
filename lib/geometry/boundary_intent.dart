/// Infers ordered boundary waypoints from a draft stroke so closing can
/// follow the arc the artist actually traced, not only the geometrically
/// shortest one.
///
/// Candidates are draft vertex IDs that already sit on [graph] (snapped /
/// welded boundary corners). Freehand-only IDs are ignored. [fromId] and
/// [toId] (the path endpoints — typically the draft's last and first) are
/// never returned.
///
/// Order: draft is walked start→…→end, while shared-boundary closure
/// searches [fromId]→[toId] (end→start). Mid waypoints are therefore
/// returned in **reverse draft order** so concatenating
/// `from → w1 → … → wk → to` follows the same arc the stroke walked.
List<String> inferBoundaryWaypoints({
  required List<String> draftVertexIds,
  required Map<String, List<(String, double)>> graph,
  required String fromId,
  required String toId,
}) {
  final seen = <String>{};
  final mids = <String>[];
  for (final id in draftVertexIds) {
    if (id == fromId || id == toId) continue;
    if (!graph.containsKey(id)) continue;
    if (!seen.add(id)) continue;
    mids.add(id);
  }
  return mids.reversed.toList();
}
