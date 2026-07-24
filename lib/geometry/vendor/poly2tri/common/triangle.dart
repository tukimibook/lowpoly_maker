// Poly2Tri Copyright (c) 2009-2018, Poly2Tri Contributors
// https://github.com/jhasse/poly2tri
//
// Pure Dart port of poly2tri/common/shapes Triangle.

import 'edge.dart';
import 'point.dart';

/// Triangle in the poly2tri mesh.
///
/// Vertices and neighbor links are compared by **reference identity**
/// ([identical]), never by coordinate value — matching upstream poly2tri.
class P2tTriangle {
  P2tTriangle(P2tPoint a, P2tPoint b, P2tPoint c)
      : _points = <P2tPoint>[a, b, c],
        _neighbors = <P2tTriangle?>[null, null, null],
        constrainedEdge = <bool>[false, false, false],
        delaunayEdge = <bool>[false, false, false];

  final List<P2tPoint> _points;
  final List<P2tTriangle?> _neighbors;

  /// Edge opposite vertex `i` is a constrained edge.
  final List<bool> constrainedEdge;

  /// Edge opposite vertex `i` is marked Delaunay (legalize scratch).
  final List<bool> delaunayEdge;

  bool _interior = false;

  P2tPoint getPoint(int index) => _points[index];

  List<P2tPoint> get points => _points;

  P2tTriangle? getNeighbor(int index) => _neighbors[index];

  bool get isInterior => _interior;

  set isInterior(bool value) => _interior = value;

  /// Whether [point] is one of this triangle's vertices (by reference).
  bool containsPoint(P2tPoint point) =>
      identical(point, _points[0]) ||
      identical(point, _points[1]) ||
      identical(point, _points[2]);

  bool containsEdge(P2tEdge edge) =>
      containsPoint(edge.p) && containsPoint(edge.q);

  bool containsPoints(P2tPoint p1, P2tPoint p2) =>
      containsPoint(p1) && containsPoint(p2);

  /// Wire neighbor across the edge `[p1, p2]` (by reference).
  void markNeighborPointers(P2tPoint p1, P2tPoint p2, P2tTriangle t) {
    if ((identical(p1, _points[2]) && identical(p2, _points[1])) ||
        (identical(p1, _points[1]) && identical(p2, _points[2]))) {
      _neighbors[0] = t;
    } else if ((identical(p1, _points[0]) && identical(p2, _points[2])) ||
        (identical(p1, _points[2]) && identical(p2, _points[0]))) {
      _neighbors[1] = t;
    } else if ((identical(p1, _points[0]) && identical(p2, _points[1])) ||
        (identical(p1, _points[1]) && identical(p2, _points[0]))) {
      _neighbors[2] = t;
    } else {
      throw StateError('P2tTriangle.markNeighborPointers: edge not found');
    }
  }

  /// Exhaustive search to update neighbor pointers between [this] and [t].
  void markNeighbor(P2tTriangle t) {
    if (t.containsPoints(_points[1], _points[2])) {
      _neighbors[0] = t;
      t.markNeighborPointers(_points[1], _points[2], this);
    } else if (t.containsPoints(_points[0], _points[2])) {
      _neighbors[1] = t;
      t.markNeighborPointers(_points[0], _points[2], this);
    } else if (t.containsPoints(_points[0], _points[1])) {
      _neighbors[2] = t;
      t.markNeighborPointers(_points[0], _points[1], this);
    }
  }

  void clearNeighbors() {
    _neighbors[0] = null;
    _neighbors[1] = null;
    _neighbors[2] = null;
  }

  void clearNeighbor(P2tTriangle triangle) {
    if (identical(_neighbors[0], triangle)) {
      _neighbors[0] = null;
    } else if (identical(_neighbors[1], triangle)) {
      _neighbors[1] = null;
    } else {
      _neighbors[2] = null;
    }
  }

  void clearDelaunayEdges() {
    delaunayEdge[0] = false;
    delaunayEdge[1] = false;
    delaunayEdge[2] = false;
  }

  /// Point clockwise from [p] among this triangle's vertices.
  P2tPoint? pointCW(P2tPoint p) {
    if (identical(p, _points[0])) return _points[2];
    if (identical(p, _points[1])) return _points[0];
    if (identical(p, _points[2])) return _points[1];
    return null;
  }

  /// Point counter-clockwise from [p].
  P2tPoint? pointCCW(P2tPoint p) {
    if (identical(p, _points[0])) return _points[1];
    if (identical(p, _points[1])) return _points[2];
    if (identical(p, _points[2])) return _points[0];
    return null;
  }

  P2tTriangle? neighborCW(P2tPoint p) {
    if (identical(p, _points[0])) return _neighbors[1];
    if (identical(p, _points[1])) return _neighbors[2];
    return _neighbors[0];
  }

  P2tTriangle? neighborCCW(P2tPoint p) {
    if (identical(p, _points[0])) return _neighbors[2];
    if (identical(p, _points[1])) return _neighbors[0];
    return _neighbors[1];
  }

  P2tTriangle? neighborAcross(P2tPoint p) {
    if (identical(p, _points[0])) return _neighbors[0];
    if (identical(p, _points[1])) return _neighbors[1];
    return _neighbors[2];
  }

  bool getConstrainedEdgeCW(P2tPoint p) {
    if (identical(p, _points[0])) return constrainedEdge[1];
    if (identical(p, _points[1])) return constrainedEdge[2];
    return constrainedEdge[0];
  }

  bool getConstrainedEdgeCCW(P2tPoint p) {
    if (identical(p, _points[0])) return constrainedEdge[2];
    if (identical(p, _points[1])) return constrainedEdge[0];
    return constrainedEdge[1];
  }

  bool getConstrainedEdgeAcross(P2tPoint p) {
    if (identical(p, _points[0])) return constrainedEdge[0];
    if (identical(p, _points[1])) return constrainedEdge[1];
    return constrainedEdge[2];
  }

  void setConstrainedEdgeCW(P2tPoint p, bool ce) {
    if (identical(p, _points[0])) {
      constrainedEdge[1] = ce;
    } else if (identical(p, _points[1])) {
      constrainedEdge[2] = ce;
    } else {
      constrainedEdge[0] = ce;
    }
  }

  void setConstrainedEdgeCCW(P2tPoint p, bool ce) {
    if (identical(p, _points[0])) {
      constrainedEdge[2] = ce;
    } else if (identical(p, _points[1])) {
      constrainedEdge[0] = ce;
    } else {
      constrainedEdge[1] = ce;
    }
  }

  bool getDelaunayEdgeCW(P2tPoint p) {
    if (identical(p, _points[0])) return delaunayEdge[1];
    if (identical(p, _points[1])) return delaunayEdge[2];
    return delaunayEdge[0];
  }

  bool getDelaunayEdgeCCW(P2tPoint p) {
    if (identical(p, _points[0])) return delaunayEdge[2];
    if (identical(p, _points[1])) return delaunayEdge[0];
    return delaunayEdge[1];
  }

  void setDelaunayEdgeCW(P2tPoint p, bool e) {
    if (identical(p, _points[0])) {
      delaunayEdge[1] = e;
    } else if (identical(p, _points[1])) {
      delaunayEdge[2] = e;
    } else {
      delaunayEdge[0] = e;
    }
  }

  void setDelaunayEdgeCCW(P2tPoint p, bool e) {
    if (identical(p, _points[0])) {
      delaunayEdge[2] = e;
    } else if (identical(p, _points[1])) {
      delaunayEdge[0] = e;
    } else {
      delaunayEdge[1] = e;
    }
  }

  P2tPoint? oppositePoint(P2tTriangle t, P2tPoint p) {
    final cw = t.pointCW(p);
    if (cw == null) return null;
    return pointCW(cw);
  }

  /// Rotate vertices clockwise around [opoint], replacing the far vertex with
  /// [npoint] (legalize step).
  void legalize(P2tPoint opoint, P2tPoint npoint) {
    if (identical(opoint, _points[0])) {
      _points[1] = _points[0];
      _points[0] = _points[2];
      _points[2] = npoint;
    } else if (identical(opoint, _points[1])) {
      _points[2] = _points[1];
      _points[1] = _points[0];
      _points[0] = npoint;
    } else if (identical(opoint, _points[2])) {
      _points[0] = _points[2];
      _points[2] = _points[1];
      _points[1] = npoint;
    } else {
      throw StateError('P2tTriangle.legalize: opoint not in triangle');
    }
  }

  /// Index of vertex [p] (by reference). Throws if not found.
  int index(P2tPoint p) {
    if (identical(p, _points[0])) return 0;
    if (identical(p, _points[1])) return 1;
    if (identical(p, _points[2])) return 2;
    throw StateError('P2tTriangle.index: point not in triangle');
  }

  /// Edge index opposite the shared edge of [p1]-[p2], or `-1` if missing.
  int edgeIndex(P2tPoint p1, P2tPoint p2) {
    if (identical(p1, _points[0])) {
      if (identical(p2, _points[1])) return 2;
      if (identical(p2, _points[2])) return 1;
    } else if (identical(p1, _points[1])) {
      if (identical(p2, _points[2])) return 0;
      if (identical(p2, _points[0])) return 2;
    } else if (identical(p1, _points[2])) {
      if (identical(p2, _points[0])) return 1;
      if (identical(p2, _points[1])) return 0;
    }
    return -1;
  }

  void markConstrainedEdgeByIndex(int index) {
    constrainedEdge[index] = true;
  }

  void markConstrainedEdgeByEdge(P2tEdge edge) {
    markConstrainedEdgeByPoints(edge.p, edge.q);
  }

  void markConstrainedEdgeByPoints(P2tPoint p, P2tPoint q) {
    if ((identical(q, _points[0]) && identical(p, _points[1])) ||
        (identical(q, _points[1]) && identical(p, _points[0]))) {
      constrainedEdge[2] = true;
    } else if ((identical(q, _points[0]) && identical(p, _points[2])) ||
        (identical(q, _points[2]) && identical(p, _points[0]))) {
      constrainedEdge[1] = true;
    } else if ((identical(q, _points[1]) && identical(p, _points[2])) ||
        (identical(q, _points[2]) && identical(p, _points[1]))) {
      constrainedEdge[0] = true;
    }
  }

  @override
  String toString() => '[${_points[0]}${_points[1]}${_points[2]}]';
}
