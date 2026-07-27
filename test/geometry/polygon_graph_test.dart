import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/polygon_graph.dart';
import 'package:polygon_art_app/models/polygon_shape.dart';
import 'package:polygon_art_app/models/vertex.dart';

PolygonShape _polygon(String id, List<String> vertexIds) {
  return PolygonShape(
    id: id,
    vertexIds: vertexIds,
    fillColor: const Color(0xFF000000),
    strokeColor: const Color(0xFF000000),
    strokeWidth: 1,
  );
}

Vertex _vertex(String id, Offset position) => Vertex(id: id, position: position);

void main() {
  group('buildPolygonEdgeGraph', () {
    test('links every consecutive pair of vertices in a ring, including wrap-around', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(10, 0)),
        'c': _vertex('c', const Offset(10, 10)),
      };
      final graph = buildPolygonEdgeGraph(
        [_polygon('p1', const ['a', 'b', 'c'])],
        vertices,
      );

      expect(graph['a']!.map((e) => e.$1), containsAll(['b', 'c']));
      expect(graph['b']!.map((e) => e.$1), containsAll(['a', 'c']));
      expect(graph['c']!.map((e) => e.$1), containsAll(['a', 'b']));
    });

    test('weights each edge by the on-screen distance between its endpoints', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(3, 4)),
      };
      final graph = buildPolygonEdgeGraph(
        [_polygon('p1', const ['a', 'b'])],
        vertices,
      );

      final edge = graph['a']!.firstWhere((e) => e.$1 == 'b');
      expect(edge.$2, 5.0);
    });

    test('merges edges from two polygons sharing a welded vertex into one graph', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(10, 0)),
        'c': _vertex('c', const Offset(10, 10)),
        'd': _vertex('d', const Offset(0, 10)),
      };
      final graph = buildPolygonEdgeGraph(
        [
          _polygon('p1', const ['a', 'b', 'c']),
          _polygon('p2', const ['a', 'c', 'd']),
        ],
        vertices,
      );

      expect(graph['a']!.map((e) => e.$1), containsAll(['b', 'c', 'd']));
      expect(graph['c']!.map((e) => e.$1), containsAll(['a', 'b', 'd']));
    });

    test('silently skips an edge whose endpoint vertex is missing from the pool', () {
      final vertices = {'a': _vertex('a', const Offset(0, 0))};
      final graph = buildPolygonEdgeGraph(
        [_polygon('p1', const ['a', 'missing'])],
        vertices,
      );

      expect(graph.containsKey('a'), isFalse);
      expect(graph.containsKey('missing'), isFalse);
    });

    test('returns an empty graph for no polygons at all', () {
      expect(buildPolygonEdgeGraph(const [], const {}), isEmpty);
    });
  });

  group('findShortestBoundaryPath', () {
    test('returns a single-element path when fromId equals toId', () {
      final graph = buildPolygonEdgeGraph(
        [_polygon('p1', const ['a', 'b', 'c'])],
        {
          'a': _vertex('a', const Offset(0, 0)),
          'b': _vertex('b', const Offset(10, 0)),
          'c': _vertex('c', const Offset(10, 10)),
        },
      );

      final path = findShortestBoundaryPath(
        'a',
        'a',
        graph: graph,
        draftVertexIds: const {},
      );

      expect(path, ['a']);
    });

    test('returns null when either endpoint is absent from the graph', () {
      final graph = buildPolygonEdgeGraph(
        [_polygon('p1', const ['a', 'b', 'c'])],
        {
          'a': _vertex('a', const Offset(0, 0)),
          'b': _vertex('b', const Offset(10, 0)),
          'c': _vertex('c', const Offset(10, 10)),
        },
      );

      expect(
        findShortestBoundaryPath('a', 'z', graph: graph, draftVertexIds: const {}),
        isNull,
      );
    });

    test('picks the shorter of a single polygon\'s two boundary arcs', () {
      // Square a-b-c-d: a->b->c (long arc, 3 edges via d not taken) vs a->d->c
      // is designed so the direct short arc a->b->c wins over a->d->c.
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(1, 0)),
        'c': _vertex('c', const Offset(2, 0)),
        'd': _vertex('d', const Offset(1, 100)),
      };
      final graph = buildPolygonEdgeGraph(
        [_polygon('p1', const ['a', 'b', 'c', 'd'])],
        vertices,
      );

      final path = findShortestBoundaryPath(
        'a',
        'c',
        graph: graph,
        draftVertexIds: const {},
      );

      expect(path, ['a', 'b', 'c']);
    });

    test('routes across a chain of polygons sharing welded vertices', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(1, 0)),
        'c': _vertex('c', const Offset(2, 0)),
        'd': _vertex('d', const Offset(3, 0)),
      };
      final graph = buildPolygonEdgeGraph(
        [
          _polygon('p1', const ['a', 'b']),
          _polygon('p2', const ['b', 'c']),
          _polygon('p3', const ['c', 'd']),
        ],
        vertices,
      );

      final path = findShortestBoundaryPath(
        'a',
        'd',
        graph: graph,
        draftVertexIds: const {},
      );

      expect(path, ['a', 'b', 'c', 'd']);
    });

    test(
      'allows on-graph draft vertices as mid-path hops (boundary tracing) '
      'and still allows toId itself',
      () {
        // Chain a-b, b-c, c-d across separate polygons: 'b' and 'c' are each
        // the *only* route between their neighbors (no ring closure shortcut,
        // unlike a single polygon's own ring).
        final vertices = {
          'a': _vertex('a', const Offset(0, 0)),
          'b': _vertex('b', const Offset(1, 0)),
          'c': _vertex('c', const Offset(2, 0)),
          'd': _vertex('d', const Offset(3, 0)),
        };
        final graph = buildPolygonEdgeGraph(
          [
            _polygon('p1', const ['a', 'b']),
            _polygon('p2', const ['b', 'c']),
            _polygon('p3', const ['c', 'd']),
          ],
          vertices,
        );

        // On-graph draft IDs must remain traversable — blocking them would
        // seal the short arc the artist just traced along the boundary.
        expect(
          findShortestBoundaryPath(
            'a',
            'd',
            graph: graph,
            draftVertexIds: const {'a', 'b', 'c', 'd'},
          ),
          ['a', 'b', 'c', 'd'],
        );

        // Freehand-only draft IDs (absent from the graph) are ignored as
        // hops in practice — they never appear as neighbors — and must not
        // prevent a real on-graph path.
        expect(
          findShortestBoundaryPath(
            'a',
            'd',
            graph: graph,
            draftVertexIds: const {'freehand'},
          ),
          ['a', 'b', 'c', 'd'],
        );

        // toId itself may be in draftVertexIds without being blocked.
        final path = findShortestBoundaryPath(
          'a',
          'b',
          graph: graph,
          draftVertexIds: const {'b'},
        );
        expect(path, ['a', 'b']);
      },
    );

    test(
      'returns the short boundary arc even when its mid vertices are already '
      'listed in draftVertexIds',
      () {
        final vertices = {
          'a': _vertex('a', const Offset(0, 0)),
          'b': _vertex('b', const Offset(1, 0)),
          'c': _vertex('c', const Offset(2, 0)),
          'd': _vertex('d', const Offset(1, 100)),
        };
        final graph = buildPolygonEdgeGraph(
          [_polygon('p1', const ['a', 'b', 'c', 'd'])],
          vertices,
        );

        // Artist snapped a -> b -> c along the short top edge; closing from
        // c back to a must still see that short arc (via b), not null.
        expect(
          findShortestBoundaryPath(
            'c',
            'a',
            graph: graph,
            draftVertexIds: const {'a', 'b', 'c'},
          ),
          ['c', 'b', 'a'],
        );
      },
    );

    test('returns null when the graph has no connection between the two vertices', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(1, 0)),
        'c': _vertex('c', const Offset(10, 10)),
        'd': _vertex('d', const Offset(11, 10)),
      };
      final graph = buildPolygonEdgeGraph(
        [
          _polygon('p1', const ['a', 'b']),
          _polygon('p2', const ['c', 'd']),
        ],
        vertices,
      );

      expect(
        findShortestBoundaryPath('a', 'c', graph: graph, draftVertexIds: const {}),
        isNull,
      );
    });
  });

  group('findBoundaryPathViaWaypoints', () {
    test('concatenates shortest legs through each waypoint in order', () {
      // a-b-c is uniquely short (length 2); a-d-c is long (≈101). Forcing
      // via d must yield the long arc even though shortest alone uses b.
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(1, 0)),
        'c': _vertex('c', const Offset(2, 0)),
        'd': _vertex('d', const Offset(1, 100)),
      };
      final graph = buildPolygonEdgeGraph(
        [_polygon('p1', const ['a', 'b', 'c', 'd'])],
        vertices,
      );

      expect(
        findShortestBoundaryPath(
          'a',
          'c',
          graph: graph,
          draftVertexIds: const {},
        ),
        ['a', 'b', 'c'],
      );

      expect(
        findBoundaryPathViaWaypoints(
          'a',
          'c',
          waypoints: const ['d'],
          graph: graph,
          draftVertexIds: const {},
        ),
        ['a', 'd', 'c'],
      );
    });

    test('supports multiple waypoints by chaining legs', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(1, 0)),
        'c': _vertex('c', const Offset(2, 0)),
        'd': _vertex('d', const Offset(3, 0)),
      };
      final graph = buildPolygonEdgeGraph(
        [
          _polygon('p1', const ['a', 'b']),
          _polygon('p2', const ['b', 'c']),
          _polygon('p3', const ['c', 'd']),
        ],
        vertices,
      );

      expect(
        findBoundaryPathViaWaypoints(
          'a',
          'd',
          waypoints: const ['b', 'c'],
          graph: graph,
          draftVertexIds: const {},
        ),
        ['a', 'b', 'c', 'd'],
      );
    });

    test('returns null when any leg is disconnected', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(1, 0)),
        'c': _vertex('c', const Offset(10, 10)),
        'd': _vertex('d', const Offset(11, 10)),
      };
      final graph = buildPolygonEdgeGraph(
        [
          _polygon('p1', const ['a', 'b']),
          _polygon('p2', const ['c', 'd']),
        ],
        vertices,
      );

      // a→b is fine, but b→c has no edge.
      expect(
        findBoundaryPathViaWaypoints(
          'a',
          'd',
          waypoints: const ['b', 'c'],
          graph: graph,
          draftVertexIds: const {},
        ),
        isNull,
      );
    });

    test('empty waypoints reduces to a plain shortest path', () {
      final vertices = {
        'a': _vertex('a', const Offset(0, 0)),
        'b': _vertex('b', const Offset(1, 0)),
        'c': _vertex('c', const Offset(2, 0)),
        'd': _vertex('d', const Offset(1, 100)),
      };
      final graph = buildPolygonEdgeGraph(
        [_polygon('p1', const ['a', 'b', 'c', 'd'])],
        vertices,
      );

      expect(
        findBoundaryPathViaWaypoints(
          'a',
          'c',
          waypoints: const [],
          graph: graph,
          draftVertexIds: const {},
        ),
        findShortestBoundaryPath(
          'a',
          'c',
          graph: graph,
          draftVertexIds: const {},
        ),
      );
    });
  });
}
