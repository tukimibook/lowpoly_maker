// Poly2Tri Copyright (c) 2009-2018, Poly2Tri Contributors
// https://github.com/jhasse/poly2tri
//
// Pure Dart port of poly2tri/sweep/sweep_context.

import '../common/edge.dart';
import '../common/point.dart';
import '../common/triangle.dart';
import '../common/utils.dart';
import 'advancing_front.dart';
import 'sweep.dart';

/// Seed triangle extends 30% of point-set width to both left and right.
const double kP2tAlpha = 0.3;

/// Basin fill state used by [Sweep].
class P2tBasin {
  P2tFrontNode? leftNode;
  P2tFrontNode? bottomNode;
  P2tFrontNode? rightNode;
  double width = 0.0;
  bool leftHighest = false;

  void clear() {
    leftNode = null;
    bottomNode = null;
    rightNode = null;
    width = 0.0;
    leftHighest = false;
  }
}

/// Scratch state for an in-progress constrained edge event.
class P2tEdgeEvent {
  P2tEdge? constrainedEdge;
  bool right = false;
}

/// Triangulation context: points, constrained edges, advancing front, mesh.
class SweepContext {
  SweepContext(List<P2tPoint> contour)
      : _points = List<P2tPoint>.of(contour) {
    _initEdges(_points);
  }

  final List<P2tTriangle> _triangles = <P2tTriangle>[];
  final List<P2tTriangle> _map = <P2tTriangle>[];
  final List<P2tPoint> _points;
  final List<P2tEdge> edgeList = <P2tEdge>[];

  AdvancingFront? front;
  P2tPoint? head;
  P2tPoint? tail;

  final P2tBasin basin = P2tBasin();
  final P2tEdgeEvent edgeEvent = P2tEdgeEvent();

  List<P2tTriangle> get triangles => _triangles;

  List<P2tTriangle> get map => _map;

  int get pointCount => _points.length;

  P2tPoint getPoint(int index) => _points[index];

  /// Add a hole polyline (constrained edges + vertices).
  void addHole(List<P2tPoint> polyline) {
    _initEdges(polyline);
    _points.addAll(polyline);
  }

  /// Add a Steiner point.
  void addPoint(P2tPoint point) {
    _points.add(point);
  }

  void addPoints(List<P2tPoint> points) {
    _points.addAll(points);
  }

  /// Run the sweep-line triangulation.
  void triangulate() {
    Sweep.triangulate(this);
  }

  List<P2tTriangle> getTriangles() => _triangles;

  void addToMap(P2tTriangle triangle) {
    _map.add(triangle);
  }

  void removeFromMap(P2tTriangle triangle) {
    _map.remove(triangle);
  }

  P2tFrontNode? locateNode(P2tPoint point) => front!.locateNode(point.x);

  void initTriangulation() {
    var xmin = _points[0].x;
    var xmax = _points[0].x;
    var ymin = _points[0].y;
    var ymax = _points[0].y;

    for (var i = 1; i < _points.length; i++) {
      final p = _points[i];
      if (p.x > xmax) xmax = p.x;
      if (p.x < xmin) xmin = p.x;
      if (p.y > ymax) ymax = p.y;
      if (p.y < ymin) ymin = p.y;
    }

    final dx = kP2tAlpha * (xmax - xmin);
    final dy = kP2tAlpha * (ymax - ymin);
    head = P2tPoint(xmax + dx, ymin - dy);
    tail = P2tPoint(xmin - dx, ymin - dy);

    _points.sort(comparePoints);
  }

  void createAdvancingFront() {
    // Initial triangle: first sorted point + synthetic tail/head.
    final triangle = P2tTriangle(_points[0], tail!, head!);
    _map.add(triangle);

    final headNode = P2tFrontNode(triangle.getPoint(1), triangle);
    final middleNode = P2tFrontNode(triangle.getPoint(0), triangle);
    final tailNode = P2tFrontNode(triangle.getPoint(2));

    front = AdvancingFront(headNode, tailNode);
    headNode.next = middleNode;
    middleNode.next = tailNode;
    middleNode.prev = headNode;
    tailNode.prev = middleNode;
  }

  void mapTriangleToNodes(P2tTriangle t) {
    for (var i = 0; i < 3; i++) {
      if (t.getNeighbor(i) == null) {
        final cw = t.pointCW(t.getPoint(i));
        if (cw == null) continue;
        final n = front!.locatePoint(cw);
        if (n != null) {
          n.triangle = t;
        }
      }
    }
  }

  /// Depth-first collect of interior triangles from [triangle].
  void meshClean(P2tTriangle triangle) {
    final stack = <P2tTriangle?>[triangle];
    while (stack.isNotEmpty) {
      final t = stack.removeLast();
      if (t == null || t.isInterior) continue;
      t.isInterior = true;
      _triangles.add(t);
      for (var i = 0; i < 3; i++) {
        if (!t.constrainedEdge[i]) {
          final n = t.getNeighbor(i);
          if (n != null) stack.add(n);
        }
      }
    }
  }

  void _initEdges(List<P2tPoint> polyline) {
    final len = polyline.length;
    for (var i = 0; i < len; i++) {
      edgeList.add(P2tEdge(polyline[i], polyline[(i + 1) % len]));
    }
  }
}
