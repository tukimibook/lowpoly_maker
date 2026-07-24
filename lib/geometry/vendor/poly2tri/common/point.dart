// Poly2Tri Copyright (c) 2009-2018, Poly2Tri Contributors
// https://github.com/jhasse/poly2tri
//
// Pure Dart port of poly2tri/common/shapes Point.

import 'edge.dart';

/// A 2D point used by the poly2tri sweep-line CDT.
///
/// **Identity is by object reference, not by coordinates.** Two instances with
/// the same `(x, y)` are distinct vertices unless the caller reuses the same
/// object. Do not override [operator ==] / [hashCode] with coordinate equality.
class P2tPoint {
  P2tPoint([this.x = 0.0, this.y = 0.0]);

  double x;
  double y;

  /// Edges for which this point is the upper endpoint (`q` after Edge
  /// normalization). Populated by [P2tEdge]'s constructor.
  final List<P2tEdge> edgeList = <P2tEdge>[];

  void setZero() {
    x = 0.0;
    y = 0.0;
  }

  void set(double x_, double y_) {
    x = x_;
    y = y_;
  }

  /// Coordinate equality helper (not used for mesh topology).
  bool coordinatesEqual(P2tPoint other) => x == other.x && y == other.y;

  @override
  String toString() => '($x;$y)';
}
