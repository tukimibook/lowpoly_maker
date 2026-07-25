// Poly2Tri Copyright (c) 2009-2018, Poly2Tri Contributors
// https://github.com/jhasse/poly2tri
//
// Pure Dart port of poly2tri/sweep/advancing_front.

import '../common/point.dart';
import '../common/triangle.dart';

/// Node on the advancing front linked list / search cursor.
class P2tFrontNode {
  P2tFrontNode(this.point, [this.triangle]) : value = point.x;

  P2tPoint point;
  P2tTriangle? triangle;
  P2tFrontNode? next;
  P2tFrontNode? prev;

  /// Cached `point.x` for locate searches (upstream `Node::value`).
  double value;
}

/// Advancing front: doubly-linked list of [P2tFrontNode]s with a search hint.
class AdvancingFront {
  AdvancingFront(this.head, this.tail) : searchNode = head;

  P2tFrontNode head;
  P2tFrontNode tail;

  /// Search cursor hint for [locateNode] / [locatePoint].
  P2tFrontNode searchNode;

  /// Locate the node whose x-span contains [x] (search from hint).
  P2tFrontNode? locateNode(double x) {
    var node = searchNode;

    if (x < node.value) {
      var prev = node.prev;
      while (prev != null) {
        node = prev;
        if (x >= node.value) {
          searchNode = node;
          return node;
        }
        prev = node.prev;
      }
    } else {
      var next = node.next;
      while (next != null) {
        node = next;
        if (x < node.value) {
          final result = node.prev!;
          searchNode = result;
          return result;
        }
        next = node.next;
      }
    }
    return null;
  }

  /// Locate the front node holding [point] by reference identity.
  P2tFrontNode? locatePoint(P2tPoint point) {
    final px = point.x;
    P2tFrontNode? node = searchNode;
    final nx = node.point.x;

    if (px == nx) {
      if (!identical(point, node.point)) {
        if (node.prev != null && identical(point, node.prev!.point)) {
          node = node.prev;
        } else if (node.next != null && identical(point, node.next!.point)) {
          node = node.next;
        } else {
          throw StateError('AdvancingFront.locatePoint: point not found');
        }
      }
    } else if (px < nx) {
      var prev = node.prev;
      node = null;
      while (prev != null) {
        if (identical(point, prev.point)) {
          node = prev;
          break;
        }
        prev = prev.prev;
      }
    } else {
      var next = node.next;
      node = null;
      while (next != null) {
        if (identical(point, next.point)) {
          node = next;
          break;
        }
        next = next.next;
      }
    }

    if (node != null) {
      searchNode = node;
    }
    return node;
  }
}
