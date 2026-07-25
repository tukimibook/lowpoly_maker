// Poly2Tri Copyright (c) 2009-2018, Poly2Tri Contributors
// https://github.com/jhasse/poly2tri
//
// Pure Dart port of poly2tri/sweep/cdt.

import '../common/point.dart';
import '../common/triangle.dart';
import 'sweep.dart';
import 'sweep_context.dart';

/// Public facade for constrained Delaunay triangulation.
///
/// Usage order (same as upstream poly2tri):
/// 1. Construct with outer contour
/// 2. [addHole] / [addPoint] as needed
/// 3. [triangulate]
/// 4. [getTriangles]
class CDT {
  CDT(List<P2tPoint> contour) : _tcx = SweepContext(contour);

  final SweepContext _tcx;

  /// Add a hole polyline that does not touch the outer contour or other holes.
  void addHole(List<P2tPoint> polyline) => _tcx.addHole(polyline);

  /// Add a Steiner point inside the domain.
  void addPoint(P2tPoint point) => _tcx.addPoint(point);

  /// Run the sweep-line CDT.
  void triangulate() => Sweep.triangulate(_tcx);

  /// Interior triangles produced by the last [triangulate] call.
  List<P2tTriangle> getTriangles() => _tcx.getTriangles();

  /// Full triangle map (includes exterior helpers before mesh clean).
  List<P2tTriangle> getMap() => _tcx.map;
}
