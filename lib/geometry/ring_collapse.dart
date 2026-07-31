/// Removes consecutive duplicate IDs from a closed polygon ring. When the
/// first and last entries match after collapse, drops the trailing one.
List<String> collapseConsecutiveRingIds(List<String> ids) {
  if (ids.length < 2) return ids;
  final result = <String>[ids.first];
  for (var i = 1; i < ids.length; i++) {
    if (ids[i] != result.last) result.add(ids[i]);
  }
  if (result.length > 1 && result.first == result.last) {
    result.removeLast();
  }
  return result;
}

/// Removes consecutive duplicate IDs from an open draft polyline.
List<String> collapseConsecutiveOpenIds(List<String> ids) {
  if (ids.isEmpty) return ids;
  final result = <String>[ids.first];
  for (var i = 1; i < ids.length; i++) {
    if (ids[i] != result.last) result.add(ids[i]);
  }
  return result;
}

/// True when [ids] — already collapsed of merely *consecutive* duplicates
/// by [collapseConsecutiveRingIds] / [collapseConsecutiveOpenIds] — still
/// contains the same ID more than once, e.g. `[A, keep, B, keep, C]`. For a
/// closed polygon ring this means the shape revisits the same point
/// non-consecutively: a self-touching "figure-8"/bowtie, such as pinching
/// two opposite corners of a quadrilateral together. That's silently
/// allowed by the *consecutive*-only collapse above (which only catches a
/// point immediately welded to its own ring neighbor), yet it breaks the
/// "one simple closed curve per polygon" assumption later stages —
/// notably Phase G's tessellation — rely on. Callers refuse any merge that
/// would produce one rather than let degenerate geometry into the shared
/// pool.
bool hasNonConsecutiveDuplicate(List<String> ids) {
  return ids.toSet().length != ids.length;
}

/// Debug-only invariant for a **confirmed** polygon ring: no duplicate IDs
/// (consecutive or otherwise), and no explicit trailing wrap of the start
/// (`[A, B, C, A]`). Call at close / load / tessellation commit sites.
///
/// Do **not** apply this to [Artwork.draftVertexIds] — drafts may legally
/// contain duplicates such as a self-close snap `[S, …, S]`.
void assertConfirmedRingIds(List<String> ids) {
  assert(!hasNonConsecutiveDuplicate(ids));
  assert(ids.length < 2 || ids.first != ids.last);
}
