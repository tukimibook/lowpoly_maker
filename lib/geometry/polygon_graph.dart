import 'package:collection/collection.dart';

import '../models/polygon_shape.dart';
import '../models/vertex.dart';

/// Builds an undirected graph over every confirmed polygon's own ring of
/// edges (each vertex linked to its immediate neighbors within each
/// polygon it belongs to), weighted by on-screen distance between them.
/// Used by [findShortestBoundaryPath] to route a closing edge along
/// whatever boundary is already there instead of cutting straight
/// through it.
Map<String, List<(String, double)>> buildPolygonEdgeGraph(
  List<PolygonShape> polygons,
  Map<String, Vertex> vertices,
) {
  final graph = <String, List<(String, double)>>{};
  void addEdge(String a, String b) {
    final va = vertices[a];
    final vb = vertices[b];
    if (va == null || vb == null) return;
    final weight = (vb.position - va.position).distance;
    (graph[a] ??= []).add((b, weight));
    (graph[b] ??= []).add((a, weight));
  }

  for (final polygon in polygons) {
    final ids = polygon.vertexIds;
    for (var i = 0; i < ids.length; i++) {
      addEdge(ids[i], ids[(i + 1) % ids.length]);
    }
  }
  return graph;
}

/// Geometrically shortest path from [fromId] to [toId] that travels only
/// along the edges of [graph] (see [buildPolygonEdgeGraph]), weighted by
/// on-screen distance — or `null` when no such path exists.
///
/// This is what lets a new draft tile seamlessly against whatever it
/// touches: when [fromId] and [toId] are both corners of the *same*
/// polygon, this naturally reduces to whichever of that polygon's two
/// boundary arcs between them is shorter (the graph has no other edges to
/// offer there). When they belong to two *different* polygons that happen
/// to share a welded vertex somewhere — directly, or via a chain of
/// further shared vertices — this finds the route through that chain
/// instead, so drawing a shape from one existing corner to another never
/// cuts straight across a boundary that's actually already there.
///
/// Draft-only (freehand) IDs — those absent from [graph] — are excluded as
/// mid-path hops, while confirmed boundary vertices already in the draft
/// remain usable relays. Blocking every draft ID would seal the short arc
/// the artist just traced and force a null path (and a skewer chord).
/// [toId] itself is always allowed as the destination even when it is also
/// part of the draft.
List<String>? findShortestBoundaryPath(
  String fromId,
  String toId, {
  required Map<String, List<(String, double)>> graph,
  required Set<String> draftVertexIds,
}) {
  if (fromId == toId) return [fromId];
  if (!graph.containsKey(fromId) || !graph.containsKey(toId)) return null;

  // Only freehand draft IDs (not present on the boundary graph) are blocked.
  // On-graph draft vertices must stay traversable so a boundary-tracing
  // stroke can still close along the short arc it just walked.
  final blockedHops = draftVertexIds
      .where((id) => !graph.containsKey(id))
      .toSet()
    ..remove(toId);
  final best = <String, double>{fromId: 0};
  final previous = <String, String>{};
  final settled = <String>{};
  final queue = PriorityQueue<(double, String)>(
    (a, b) => a.$1.compareTo(b.$1),
  );
  queue.add((0.0, fromId));

  while (queue.isNotEmpty) {
    final (dist, current) = queue.removeFirst();
    if (!settled.add(current)) continue;
    if (current == toId) break;
    for (final (neighborId, weight)
        in graph[current] ?? const <(String, double)>[]) {
      if (blockedHops.contains(neighborId)) continue;
      final candidate = dist + weight;
      if (candidate < (best[neighborId] ?? double.infinity)) {
        best[neighborId] = candidate;
        previous[neighborId] = current;
        queue.add((candidate, neighborId));
      }
    }
  }

  if (!settled.contains(toId)) return null;
  final path = <String>[toId];
  var node = toId;
  while (node != fromId) {
    final prev = previous[node];
    if (prev == null) return null;
    path.add(prev);
    node = prev;
  }
  return path.reversed.toList();
}
