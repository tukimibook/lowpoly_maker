import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/boundary_intent.dart';

void main() {
  group('inferBoundaryWaypoints', () {
    // Minimal adjacency map — only keys matter for "on-graph" membership.
    final graph = <String, List<(String, double)>>{
      'a': [('b', 1)],
      'b': [('a', 1), ('c', 1)],
      'c': [('b', 1), ('d', 1)],
      'd': [('c', 1)],
    };

    test('returns on-graph draft mids in reverse draft order for end→start', () {
      // Draft walked a → b → c → d; closing searches d → a, so waypoints
      // should be c then b (reverse of the mids).
      expect(
        inferBoundaryWaypoints(
          draftVertexIds: const ['a', 'b', 'c', 'd'],
          graph: graph,
          fromId: 'd',
          toId: 'a',
        ),
        ['c', 'b'],
      );
    });

    test('excludes fromId and toId even when they appear mid-draft', () {
      expect(
        inferBoundaryWaypoints(
          draftVertexIds: const ['a', 'b', 'a', 'c', 'd'],
          graph: graph,
          fromId: 'd',
          toId: 'a',
        ),
        ['c', 'b'],
      );
    });

    test('ignores freehand IDs absent from the graph', () {
      expect(
        inferBoundaryWaypoints(
          draftVertexIds: const ['a', 'freehand', 'c', 'd'],
          graph: graph,
          fromId: 'd',
          toId: 'a',
        ),
        ['c'],
      );
    });

    test('returns an empty list when the draft has no on-graph mids', () {
      expect(
        inferBoundaryWaypoints(
          draftVertexIds: const ['a', 'freehand', 'd'],
          graph: graph,
          fromId: 'd',
          toId: 'a',
        ),
        isEmpty,
      );
    });

    test('dedupes a repeated mid ID, keeping first draft encounter', () {
      expect(
        inferBoundaryWaypoints(
          draftVertexIds: const ['a', 'b', 'c', 'b', 'd'],
          graph: graph,
          fromId: 'd',
          toId: 'a',
        ),
        // First encounter order was b then c; reversed → c, b.
        ['c', 'b'],
      );
    });
  });
}
