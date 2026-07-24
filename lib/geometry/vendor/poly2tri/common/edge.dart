// Poly2Tri Copyright (c) 2009-2018, Poly2Tri Contributors
// https://github.com/jhasse/poly2tri
//
// Pure Dart port of poly2tri/common/shapes Edge.

import 'point.dart';

/// A constrained polygon edge between two [P2tPoint]s.
///
/// Endpoints are stored as [p] (lower) and [q] (upper): primarily ordered by
/// ascending `y`, then ascending `x` when `y` is equal — matching upstream
/// poly2tri. The constructed edge is registered on [q]'s [P2tPoint.edgeList].
class P2tEdge {
  P2tEdge(P2tPoint p1, P2tPoint p2)
      : p = p1,
        q = p2 {
    if (p1.y > p2.y) {
      q = p1;
      p = p2;
    } else if (p1.y == p2.y) {
      if (p1.x > p2.x) {
        q = p1;
        p = p2;
      } else if (p1.x == p2.x) {
        throw ArgumentError('P2tEdge: repeated points (p1 == p2)');
      }
    }
    q.edgeList.add(this);
  }

  /// Lower endpoint after normalization.
  P2tPoint p;

  /// Upper endpoint after normalization.
  P2tPoint q;
}
