import '../models/polygon_shape.dart';
import '../models/vertex.dart';
import 'boundary_intent.dart';
import 'line_absorption.dart';
import 'polygon_graph.dart';

bool _isConfirmedPolygonVertex(
  String vertexId,
  List<PolygonShape> polygons,
) {
  return polygons.any((p) => p.vertexIds.contains(vertexId));
}

/// When [startId] and [endId] are connected by some chain of existing
/// polygons' own edges (see [findShortestBoundaryPath]), returns the
/// vertices strictly between them along the geometrically shortest such
/// chain, so the draft can close by following it rather than cutting
/// straight back to its start.
///
/// The returned IDs are appended after the draft's last point, so the
/// closing path runs `last -> boundary... -> first`. They are reused
/// vertex IDs (not copies), so every polygon along the chain genuinely
/// shares that edge in the [Artwork.vertices] pool ("weld").
///
/// Returns an empty list when no such chain exists (or the two points are
/// the same, or directly adjacent with nothing in between);
/// [closingEdgeVertices] then falls back to absorbing any existing
/// vertex that sits on the straight closing line instead of a shared
/// boundary.
///
/// Mid-path IDs already present in the draft are omitted so a boundary-
/// tracing stroke that already walked those corners is not duplicated into
/// a self-intersecting loop.
///
/// When the draft already snapped onto on-graph corners along one boundary
/// arc, those IDs become waypoints ([inferBoundaryWaypoints]) so closing
/// follows that arc rather than the geometrically shorter opposite one.
/// Missing waypoints or a failed via-waypoint search fall back to plain
/// [findShortestBoundaryPath].
///
/// If the raw path's midpoints mix draft-already-walked IDs with vertices
/// the stroke never touched, those leftovers are treated as a foreign
/// shortcut (which would append a detour spike on close) and this returns
/// an empty list so the draft closes last→first with no splice. A path
/// whose mids are entirely outside the draft is returned as-is (pure
/// boundary weld).
List<String> sharedBoundaryClosure(
  String startId,
  String endId, {
  required List<PolygonShape> polygons,
  required Map<String, Vertex> vertices,
  required List<String> draftVertexIds,
}) {
  final draftList = draftVertexIds;
  final draftIds = draftList.toSet();
  final graph = buildPolygonEdgeGraph(polygons, vertices);
  final waypoints = inferBoundaryWaypoints(
    draftVertexIds: draftList,
    graph: graph,
    fromId: endId,
    toId: startId,
  );
  final path = (waypoints.isEmpty
          ? null
          : findBoundaryPathViaWaypoints(
              endId,
              startId,
              waypoints: waypoints,
              graph: graph,
              draftVertexIds: draftIds,
            )) ??
      findShortestBoundaryPath(
        endId,
        startId,
        graph: graph,
        draftVertexIds: draftIds,
      );
  if (path == null || path.length <= 2) return const [];
  final mids = path.sublist(1, path.length - 1);
  final alreadyInDraft = [
    for (final id in mids)
      if (draftIds.contains(id)) id,
  ];
  final notInDraft = [
    for (final id in mids)
      if (!draftIds.contains(id)) id,
  ];
  // Mixed walked + foreign mids → refuse the foreign shortcut splice.
  if (alreadyInDraft.isNotEmpty && notInDraft.isNotEmpty) {
    return const [];
  }
  return notInDraft;
}

/// Resolves what, if anything, belongs *between* the draft's last point
/// ([endId]) and its first ([startId]) when closing:
/// - If there is any chain of existing polygons' own edges connecting
///   them, follow the geometrically shortest such chain (see
///   [sharedBoundaryClosure]) rather than cutting a straight edge.
/// - Otherwise fall back to [findVerticesAlongSegment].
///
/// The returned IDs are appended after the draft's last point, so the
/// closing path runs `last -> ...returned... -> first` either way.
List<String> closingEdgeVertices(
  String startId,
  String endId, {
  required List<PolygonShape> polygons,
  required Map<String, Vertex> vertices,
  required List<String> draftVertexIds,
  required double tolerance,
}) {
  final sharedBoundary = sharedBoundaryClosure(
    startId,
    endId,
    polygons: polygons,
    vertices: vertices,
    draftVertexIds: draftVertexIds,
  );
  if (sharedBoundary.isNotEmpty) return sharedBoundary;

  final startPosition = vertices[startId]!.position;
  final endPosition = vertices[endId]!.position;
  return findVerticesAlongSegment(
    endPosition,
    startPosition,
    vertices: vertices,
    polygons: polygons,
    draftVertexIds: draftVertexIds.toSet(),
    tolerance: tolerance,
  );
}

/// True when closing the draft from [startId] to [endId] right now, via
/// [closingEdgeVertices], would silently cut a straight, unwelded edge
/// between two *different* existing polygons that share no boundary or
/// welded chain.
bool wouldCloseWithUnweldedGap(
  String startId,
  String endId, {
  required List<PolygonShape> polygons,
  required Map<String, Vertex> vertices,
  required List<String> draftVertexIds,
  required double lineAbsorptionTolerance,
}) {
  if (startId == endId) return false;
  if (!_isConfirmedPolygonVertex(startId, polygons) ||
      !_isConfirmedPolygonVertex(endId, polygons)) {
    return false;
  }
  final graph = buildPolygonEdgeGraph(polygons, vertices);
  if (findShortestBoundaryPath(
        endId,
        startId,
        graph: graph,
        draftVertexIds: draftVertexIds.toSet(),
      ) !=
      null) {
    return false;
  }

  final startPosition = vertices[startId]!.position;
  final endPosition = vertices[endId]!.position;
  return findVerticesAlongSegment(
    endPosition,
    startPosition,
    vertices: vertices,
    polygons: polygons,
    draftVertexIds: draftVertexIds.toSet(),
    tolerance: lineAbsorptionTolerance,
  ).isEmpty;
}
