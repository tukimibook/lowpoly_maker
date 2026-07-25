import 'dart:ui';

import 'vendor/poly2tri/poly2tri.dart';

/// Coarse constrained Delaunay mesh from an outer [boundary] and optional
/// [holes] (world-space [Offset] rings).
///
/// Used by `tessellation_service.triangulate` to bridge
/// `TessellationRequest` ↔ vendored poly2tri [CDT]. Steiner refinement
/// (`maxEdge` / `minEdge`) is intentionally not applied here.
///
/// Duplicate / near-duplicate coordinates (within [kP2tEpsilon]) share one
/// [P2tPoint] instance. Returned [points] still list every input slot in
/// contract order: [boundary], then each hole ring flattened. Triangle
/// indices prefer the first slot that mapped to each [P2tPoint].
({List<Offset> points, List<(int, int, int)> triangleIndices}) runPoly2TriCdt({
  required List<Offset> boundary,
  List<List<Offset>> holes = const [],
}) {
  if (boundary.length < 3) {
    throw ArgumentError.value(
      boundary.length,
      'boundary',
      'needs at least 3 vertices',
    );
  }

  final cache = _P2tPointCache();
  final contour = <P2tPoint>[
    for (final o in boundary) cache.getOrCreate(o),
  ];

  final cdt = CDT(contour);
  for (final hole in holes) {
    if (hole.length < 3) continue;
    cdt.addHole([for (final o in hole) cache.getOrCreate(o)]);
  }

  cdt.triangulate();

  final points = <Offset>[
    ...boundary,
    for (final hole in holes) ...hole,
  ];

  final firstIndex = <P2tPoint, int>{};
  var slot = 0;
  for (final o in boundary) {
    firstIndex.putIfAbsent(cache.getOrCreate(o), () => slot);
    slot++;
  }
  for (final hole in holes) {
    for (final o in hole) {
      firstIndex.putIfAbsent(cache.getOrCreate(o), () => slot);
      slot++;
    }
  }

  final triangleIndices = <(int, int, int)>[
    for (final t in cdt.getTriangles())
      (
        firstIndex[t.getPoint(0)]!,
        firstIndex[t.getPoint(1)]!,
        firstIndex[t.getPoint(2)]!,
      ),
  ];

  return (points: points, triangleIndices: triangleIndices);
}

/// Merges near-equal [Offset]s onto a single [P2tPoint] (reference reuse).
class _P2tPointCache {
  final List<P2tPoint> _points = <P2tPoint>[];

  P2tPoint getOrCreate(Offset offset) {
    final x = offset.dx;
    final y = offset.dy;
    for (final p in _points) {
      if ((p.x - x).abs() <= kP2tEpsilon && (p.y - y).abs() <= kP2tEpsilon) {
        return p;
      }
    }
    final created = P2tPoint(x, y);
    _points.add(created);
    return created;
  }
}
