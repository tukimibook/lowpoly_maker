// Poly2Tri Copyright (c) 2009-2018, Poly2Tri Contributors
// https://github.com/jhasse/poly2tri
//
// Pure Dart port of poly2tri/sweep/sweep ( Domiter–Žalik sweep-line CDT ).

import '../common/edge.dart';
import '../common/point.dart';
import '../common/triangle.dart';
import '../common/utils.dart';
import 'advancing_front.dart';
import 'sweep_context.dart';

/// Sweep-line constrained Delaunay triangulation algorithm.
class Sweep {
  /// Triangulate after contour / holes / Steiner points are registered.
  static void triangulate(SweepContext tcx) {
    tcx.initTriangulation();
    tcx.createAdvancingFront();
    _sweepPoints(tcx);
    _finalizationPolygon(tcx);
  }
}

void _sweepPoints(SweepContext tcx) {
  final len = tcx.pointCount;
  for (var i = 1; i < len; i++) {
    final point = tcx.getPoint(i);
    final node = _pointEvent(tcx, point);
    final edges = point.edgeList;
    for (final edge in edges) {
      _edgeEventByEdge(tcx, edge, node);
    }
  }
}

void _finalizationPolygon(SweepContext tcx) {
  var t = tcx.front!.head.next!.triangle!;
  final p = tcx.front!.head.next!.point;
  while (!t.getConstrainedEdgeCW(p)) {
    t = t.neighborCCW(p)!;
  }
  tcx.meshClean(t);
}

P2tFrontNode _pointEvent(SweepContext tcx, P2tPoint point) {
  final node = tcx.locateNode(point)!;
  final newNode = _newFrontTriangle(tcx, point, node);

  if (point.x <= node.point.x + kP2tEpsilon) {
    _fill(tcx, node);
  }

  _fillAdvancingFront(tcx, newNode);
  return newNode;
}

void _edgeEventByEdge(SweepContext tcx, P2tEdge edge, P2tFrontNode node) {
  tcx.edgeEvent.constrainedEdge = edge;
  tcx.edgeEvent.right = edge.p.x > edge.q.x;

  if (_isEdgeSideOfTriangle(node.triangle!, edge.p, edge.q)) {
    return;
  }

  _fillEdgeEvent(tcx, edge, node);
  _edgeEventByPoints(tcx, edge.p, edge.q, node.triangle!, edge.q);
}

void _edgeEventByPoints(
  SweepContext tcx,
  P2tPoint ep,
  P2tPoint eq,
  P2tTriangle triangle,
  P2tPoint point,
) {
  if (_isEdgeSideOfTriangle(triangle, ep, eq)) {
    return;
  }

  final p1 = triangle.pointCCW(point)!;
  final o1 = orient2d(eq, p1, ep);
  if (o1 == P2tOrientation.collinear) {
    throw P2tException('EdgeEvent: Collinear not supported!', [eq, p1, ep]);
  }

  final p2 = triangle.pointCW(point)!;
  final o2 = orient2d(eq, p2, ep);
  if (o2 == P2tOrientation.collinear) {
    throw P2tException('EdgeEvent: Collinear not supported!', [eq, p2, ep]);
  }

  if (o1 == o2) {
    final next = o1 == P2tOrientation.cw
        ? triangle.neighborCCW(point)
        : triangle.neighborCW(point);
    _edgeEventByPoints(tcx, ep, eq, next!, point);
  } else {
    _flipEdgeEvent(tcx, ep, eq, triangle, point);
  }
}

bool _isEdgeSideOfTriangle(P2tTriangle triangle, P2tPoint ep, P2tPoint eq) {
  final index = triangle.edgeIndex(ep, eq);
  if (index != -1) {
    triangle.markConstrainedEdgeByIndex(index);
    final t = triangle.getNeighbor(index);
    if (t != null) {
      t.markConstrainedEdgeByPoints(ep, eq);
    }
    return true;
  }
  return false;
}

P2tFrontNode _newFrontTriangle(
  SweepContext tcx,
  P2tPoint point,
  P2tFrontNode node,
) {
  final triangle = P2tTriangle(point, node.point, node.next!.point);
  triangle.markNeighbor(node.triangle!);
  tcx.addToMap(triangle);

  final newNode = P2tFrontNode(point);
  newNode.next = node.next;
  newNode.prev = node;
  node.next!.prev = newNode;
  node.next = newNode;

  if (!_legalize(tcx, triangle)) {
    tcx.mapTriangleToNodes(triangle);
  }
  return newNode;
}

void _fill(SweepContext tcx, P2tFrontNode node) {
  final triangle =
      P2tTriangle(node.prev!.point, node.point, node.next!.point);
  triangle.markNeighbor(node.prev!.triangle!);
  triangle.markNeighbor(node.triangle!);
  tcx.addToMap(triangle);

  node.prev!.next = node.next;
  node.next!.prev = node.prev;

  if (!_legalize(tcx, triangle)) {
    tcx.mapTriangleToNodes(triangle);
  }
}

void _fillAdvancingFront(SweepContext tcx, P2tFrontNode n) {
  var node = n.next;
  while (node != null && node.next != null) {
    if (isAngleObtuse(node.point, node.next!.point, node.prev!.point)) {
      break;
    }
    _fill(tcx, node);
    node = node.next;
  }

  node = n.prev;
  while (node != null && node.prev != null) {
    if (isAngleObtuse(node.point, node.next!.point, node.prev!.point)) {
      break;
    }
    _fill(tcx, node);
    node = node.prev;
  }

  if (n.next != null && n.next!.next != null) {
    if (_isBasinAngleRight(n)) {
      _fillBasin(tcx, n);
    }
  }
}

bool _isBasinAngleRight(P2tFrontNode node) {
  final ax = node.point.x - node.next!.next!.point.x;
  final ay = node.point.y - node.next!.next!.point.y;
  assert(ay >= 0, 'unordered y');
  return ax >= 0 || ax.abs() < ay;
}

bool _legalize(SweepContext tcx, P2tTriangle t) {
  for (var i = 0; i < 3; i++) {
    if (t.delaunayEdge[i]) continue;

    final ot = t.getNeighbor(i);
    if (ot == null) continue;

    final p = t.getPoint(i);
    final op = ot.oppositePoint(t, p)!;
    final oi = ot.index(op);

    if (ot.constrainedEdge[oi] || ot.delaunayEdge[oi]) {
      t.constrainedEdge[i] = ot.constrainedEdge[oi];
      continue;
    }

    final inside = inCircle(p, t.pointCCW(p)!, t.pointCW(p)!, op);
    if (inside) {
      t.delaunayEdge[i] = true;
      ot.delaunayEdge[oi] = true;

      _rotateTrianglePair(t, p, ot, op);

      if (!_legalize(tcx, t)) {
        tcx.mapTriangleToNodes(t);
      }
      if (!_legalize(tcx, ot)) {
        tcx.mapTriangleToNodes(ot);
      }

      t.delaunayEdge[i] = false;
      ot.delaunayEdge[oi] = false;
      return true;
    }
  }
  return false;
}

void _rotateTrianglePair(
  P2tTriangle t,
  P2tPoint p,
  P2tTriangle ot,
  P2tPoint op,
) {
  final n1 = t.neighborCCW(p);
  final n2 = t.neighborCW(p);
  final n3 = ot.neighborCCW(op);
  final n4 = ot.neighborCW(op);

  final ce1 = t.getConstrainedEdgeCCW(p);
  final ce2 = t.getConstrainedEdgeCW(p);
  final ce3 = ot.getConstrainedEdgeCCW(op);
  final ce4 = ot.getConstrainedEdgeCW(op);

  final de1 = t.getDelaunayEdgeCCW(p);
  final de2 = t.getDelaunayEdgeCW(p);
  final de3 = ot.getDelaunayEdgeCCW(op);
  final de4 = ot.getDelaunayEdgeCW(op);

  t.legalize(p, op);
  ot.legalize(op, p);

  ot.setDelaunayEdgeCCW(p, de1);
  t.setDelaunayEdgeCW(p, de2);
  t.setDelaunayEdgeCCW(op, de3);
  ot.setDelaunayEdgeCW(op, de4);

  ot.setConstrainedEdgeCCW(p, ce1);
  t.setConstrainedEdgeCW(p, ce2);
  t.setConstrainedEdgeCCW(op, ce3);
  ot.setConstrainedEdgeCW(op, ce4);

  t.clearNeighbors();
  ot.clearNeighbors();
  if (n1 != null) ot.markNeighbor(n1);
  if (n2 != null) t.markNeighbor(n2);
  if (n3 != null) t.markNeighbor(n3);
  if (n4 != null) ot.markNeighbor(n4);
  t.markNeighbor(ot);
}

void _fillBasin(SweepContext tcx, P2tFrontNode node) {
  if (orient2d(node.point, node.next!.point, node.next!.next!.point) ==
      P2tOrientation.ccw) {
    tcx.basin.leftNode = node.next!.next;
  } else {
    tcx.basin.leftNode = node.next;
  }

  tcx.basin.bottomNode = tcx.basin.leftNode;
  while (tcx.basin.bottomNode!.next != null &&
      tcx.basin.bottomNode!.point.y >=
          tcx.basin.bottomNode!.next!.point.y) {
    tcx.basin.bottomNode = tcx.basin.bottomNode!.next;
  }
  if (identical(tcx.basin.bottomNode, tcx.basin.leftNode)) {
    return;
  }

  tcx.basin.rightNode = tcx.basin.bottomNode;
  while (tcx.basin.rightNode!.next != null &&
      tcx.basin.rightNode!.point.y < tcx.basin.rightNode!.next!.point.y) {
    tcx.basin.rightNode = tcx.basin.rightNode!.next;
  }
  if (identical(tcx.basin.rightNode, tcx.basin.bottomNode)) {
    return;
  }

  tcx.basin.width =
      tcx.basin.rightNode!.point.x - tcx.basin.leftNode!.point.x;
  tcx.basin.leftHighest =
      tcx.basin.leftNode!.point.y > tcx.basin.rightNode!.point.y;

  _fillBasinReq(tcx, tcx.basin.bottomNode!);
}

void _fillBasinReq(SweepContext tcx, P2tFrontNode node) {
  if (_isShallow(tcx, node)) return;

  _fill(tcx, node);

  if (identical(node.prev, tcx.basin.leftNode) &&
      identical(node.next, tcx.basin.rightNode)) {
    return;
  } else if (identical(node.prev, tcx.basin.leftNode)) {
    final o =
        orient2d(node.point, node.next!.point, node.next!.next!.point);
    if (o == P2tOrientation.cw) return;
    node = node.next!;
  } else if (identical(node.next, tcx.basin.rightNode)) {
    final o =
        orient2d(node.point, node.prev!.point, node.prev!.prev!.point);
    if (o == P2tOrientation.ccw) return;
    node = node.prev!;
  } else {
    if (node.prev!.point.y < node.next!.point.y) {
      node = node.prev!;
    } else {
      node = node.next!;
    }
  }

  _fillBasinReq(tcx, node);
}

bool _isShallow(SweepContext tcx, P2tFrontNode node) {
  final height = tcx.basin.leftHighest
      ? tcx.basin.leftNode!.point.y - node.point.y
      : tcx.basin.rightNode!.point.y - node.point.y;
  return tcx.basin.width > height;
}

void _fillEdgeEvent(SweepContext tcx, P2tEdge edge, P2tFrontNode node) {
  if (tcx.edgeEvent.right) {
    _fillRightAboveEdgeEvent(tcx, edge, node);
  } else {
    _fillLeftAboveEdgeEvent(tcx, edge, node);
  }
}

void _fillRightAboveEdgeEvent(
  SweepContext tcx,
  P2tEdge edge,
  P2tFrontNode node,
) {
  while (node.next!.point.x < edge.p.x) {
    if (orient2d(edge.q, node.next!.point, edge.p) == P2tOrientation.ccw) {
      _fillRightBelowEdgeEvent(tcx, edge, node);
    } else {
      node = node.next!;
    }
  }
}

void _fillRightBelowEdgeEvent(
  SweepContext tcx,
  P2tEdge edge,
  P2tFrontNode node,
) {
  if (node.point.x < edge.p.x) {
    if (orient2d(node.point, node.next!.point, node.next!.next!.point) ==
        P2tOrientation.ccw) {
      _fillRightConcaveEdgeEvent(tcx, edge, node);
    } else {
      _fillRightConvexEdgeEvent(tcx, edge, node);
      _fillRightBelowEdgeEvent(tcx, edge, node);
    }
  }
}

void _fillRightConcaveEdgeEvent(
  SweepContext tcx,
  P2tEdge edge,
  P2tFrontNode node,
) {
  _fill(tcx, node.next!);
  if (!identical(node.next!.point, edge.p)) {
    if (orient2d(edge.q, node.next!.point, edge.p) == P2tOrientation.ccw) {
      if (orient2d(node.point, node.next!.point, node.next!.next!.point) ==
          P2tOrientation.ccw) {
        _fillRightConcaveEdgeEvent(tcx, edge, node);
      }
    }
  }
}

void _fillRightConvexEdgeEvent(
  SweepContext tcx,
  P2tEdge edge,
  P2tFrontNode node,
) {
  if (orient2d(
        node.next!.point,
        node.next!.next!.point,
        node.next!.next!.next!.point,
      ) ==
      P2tOrientation.ccw) {
    _fillRightConcaveEdgeEvent(tcx, edge, node.next!);
  } else {
    if (orient2d(edge.q, node.next!.next!.point, edge.p) ==
        P2tOrientation.ccw) {
      _fillRightConvexEdgeEvent(tcx, edge, node.next!);
    }
  }
}

void _fillLeftAboveEdgeEvent(
  SweepContext tcx,
  P2tEdge edge,
  P2tFrontNode node,
) {
  while (node.prev!.point.x > edge.p.x) {
    if (orient2d(edge.q, node.prev!.point, edge.p) == P2tOrientation.cw) {
      _fillLeftBelowEdgeEvent(tcx, edge, node);
    } else {
      node = node.prev!;
    }
  }
}

void _fillLeftBelowEdgeEvent(
  SweepContext tcx,
  P2tEdge edge,
  P2tFrontNode node,
) {
  if (node.point.x > edge.p.x) {
    if (orient2d(node.point, node.prev!.point, node.prev!.prev!.point) ==
        P2tOrientation.cw) {
      _fillLeftConcaveEdgeEvent(tcx, edge, node);
    } else {
      _fillLeftConvexEdgeEvent(tcx, edge, node);
      _fillLeftBelowEdgeEvent(tcx, edge, node);
    }
  }
}

void _fillLeftConvexEdgeEvent(
  SweepContext tcx,
  P2tEdge edge,
  P2tFrontNode node,
) {
  if (orient2d(
        node.prev!.point,
        node.prev!.prev!.point,
        node.prev!.prev!.prev!.point,
      ) ==
      P2tOrientation.cw) {
    _fillLeftConcaveEdgeEvent(tcx, edge, node.prev!);
  } else {
    if (orient2d(edge.q, node.prev!.prev!.point, edge.p) ==
        P2tOrientation.cw) {
      _fillLeftConvexEdgeEvent(tcx, edge, node.prev!);
    }
  }
}

void _fillLeftConcaveEdgeEvent(
  SweepContext tcx,
  P2tEdge edge,
  P2tFrontNode node,
) {
  _fill(tcx, node.prev!);
  if (!identical(node.prev!.point, edge.p)) {
    if (orient2d(edge.q, node.prev!.point, edge.p) == P2tOrientation.cw) {
      if (orient2d(node.point, node.prev!.point, node.prev!.prev!.point) ==
          P2tOrientation.cw) {
        _fillLeftConcaveEdgeEvent(tcx, edge, node);
      }
    }
  }
}

void _flipEdgeEvent(
  SweepContext tcx,
  P2tPoint ep,
  P2tPoint eq,
  P2tTriangle t,
  P2tPoint p,
) {
  final ot = t.neighborAcross(p);
  if (ot == null) {
    throw StateError('FLIP failed due to missing triangle');
  }

  final op = ot.oppositePoint(t, p)!;

  if (t.getConstrainedEdgeAcross(p)) {
    final index = t.index(p);
    throw P2tException('Intersecting Constraints', [
      p,
      op,
      t.getPoint((index + 1) % 3),
      t.getPoint((index + 2) % 3),
    ]);
  }

  if (inScanArea(p, t.pointCCW(p)!, t.pointCW(p)!, op)) {
    _rotateTrianglePair(t, p, ot, op);
    tcx.mapTriangleToNodes(t);
    tcx.mapTriangleToNodes(ot);

    if (identical(p, eq) && identical(op, ep)) {
      final ce = tcx.edgeEvent.constrainedEdge!;
      if (identical(eq, ce.q) && identical(ep, ce.p)) {
        t.markConstrainedEdgeByPoints(ep, eq);
        ot.markConstrainedEdgeByPoints(ep, eq);
        _legalize(tcx, t);
        _legalize(tcx, ot);
      }
    } else {
      final o = orient2d(eq, op, ep);
      final next = _nextFlipTriangle(tcx, o, t, ot, p, op);
      _flipEdgeEvent(tcx, ep, eq, next, p);
    }
  } else {
    final newP = _nextFlipPoint(ep, eq, ot, op);
    _flipScanEdgeEvent(tcx, ep, eq, t, ot, newP);
    _edgeEventByPoints(tcx, ep, eq, t, p);
  }
}

P2tTriangle _nextFlipTriangle(
  SweepContext tcx,
  P2tOrientation o,
  P2tTriangle t,
  P2tTriangle ot,
  P2tPoint p,
  P2tPoint op,
) {
  if (o == P2tOrientation.ccw) {
    final edgeIndex = ot.edgeIndex(p, op);
    ot.delaunayEdge[edgeIndex] = true;
    _legalize(tcx, ot);
    ot.clearDelaunayEdges();
    return t;
  }

  final edgeIndex = t.edgeIndex(p, op);
  t.delaunayEdge[edgeIndex] = true;
  _legalize(tcx, t);
  t.clearDelaunayEdges();
  return ot;
}

P2tPoint _nextFlipPoint(
  P2tPoint ep,
  P2tPoint eq,
  P2tTriangle ot,
  P2tPoint op,
) {
  final o2d = orient2d(eq, op, ep);
  if (o2d == P2tOrientation.cw) {
    return ot.pointCCW(op)!;
  }
  if (o2d == P2tOrientation.ccw) {
    return ot.pointCW(op)!;
  }
  throw P2tException(
    'nextFlipPoint: opposing point on constrained edge!',
    [eq, op, ep],
  );
}

void _flipScanEdgeEvent(
  SweepContext tcx,
  P2tPoint ep,
  P2tPoint eq,
  P2tTriangle flipTriangle,
  P2tTriangle t,
  P2tPoint p,
) {
  final ot = t.neighborAcross(p);
  if (ot == null) {
    throw StateError('FLIP failed due to missing triangle');
  }

  final op = ot.oppositePoint(t, p)!;

  if (inScanArea(
    eq,
    flipTriangle.pointCCW(eq)!,
    flipTriangle.pointCW(eq)!,
    op,
  )) {
    _flipEdgeEvent(tcx, eq, op, ot, op);
  } else {
    final newP = _nextFlipPoint(ep, eq, ot, op);
    _flipScanEdgeEvent(tcx, ep, eq, flipTriangle, ot, newP);
  }
}
