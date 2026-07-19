import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/services/tessellation_service.dart';

void main() {
  group('CanvasNotifier.commitTessellationResult', () {
    test('replaces the original polygon with the result\'s triangles', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(10, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(10, 10), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(0, 10), fillColor: Colors.red);
      notifier.closePolygon(Colors.red);
      final polygonId = notifier.state.polygons.single.id;
      final ring = notifier.state.polygons.single.vertexIds;

      // 2 triangles from the same 4 boundary points, no new interior points.
      const result = TessellationResult(
        points: [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)],
        triangleIndices: [(0, 1, 2), (0, 2, 3)],
      );

      notifier.commitTessellationResult(
        polygonId: polygonId,
        boundaryRing: ring,
        result: result,
      );

      expect(notifier.state.polygons, hasLength(2));
      expect(notifier.state.polygons.any((p) => p.id == polygonId), isFalse);
    });

    test('reuses the original boundary vertex IDs (keeps welds to neighboring shapes intact)', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(10, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(10, 10), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(0, 10), fillColor: Colors.red);
      notifier.closePolygon(Colors.red);
      final polygonId = notifier.state.polygons.single.id;
      final ring = notifier.state.polygons.single.vertexIds;

      const result = TessellationResult(
        points: [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)],
        triangleIndices: [(0, 1, 2), (0, 2, 3)],
      );

      notifier.commitTessellationResult(
        polygonId: polygonId,
        boundaryRing: ring,
        result: result,
      );

      final allVertexIds = notifier.state.polygons.expand((p) => p.vertexIds).toSet();
      expect(allVertexIds, ring.toSet());
      expect(notifier.state.vertices.keys.toSet(), ring.toSet());
    });

    test('mints fresh vertex IDs for interior points beyond the boundary ring', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(10, 0), fillColor: Colors.blue);
      notifier.handleDrawTap(const Offset(10, 10), fillColor: Colors.blue);
      notifier.closePolygon(Colors.blue);
      final polygonId = notifier.state.polygons.single.id;
      final ring = notifier.state.polygons.single.vertexIds;

      const result = TessellationResult(
        points: [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 10),
          Offset(5, 5), // new interior point, index 3
        ],
        triangleIndices: [(0, 1, 3), (1, 2, 3), (2, 0, 3)],
      );

      notifier.commitTessellationResult(
        polygonId: polygonId,
        boundaryRing: ring,
        result: result,
      );

      expect(notifier.state.polygons, hasLength(3));
      expect(notifier.state.vertices, hasLength(4));
      final interiorId = notifier.state.vertices.keys.firstWhere((id) => !ring.contains(id));
      expect(notifier.state.vertices[interiorId]!.position, const Offset(5, 5));
    });

    test('every output triangle inherits the original polygon\'s styling', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(10, 0), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(10, 10), fillColor: Colors.green);
      notifier.handleDrawTap(const Offset(0, 10), fillColor: Colors.green);
      notifier.closePolygon(Colors.green);
      final polygonId = notifier.state.polygons.single.id;
      final ring = notifier.state.polygons.single.vertexIds;

      const result = TessellationResult(
        points: [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)],
        triangleIndices: [(0, 1, 2), (0, 2, 3)],
      );

      notifier.commitTessellationResult(
        polygonId: polygonId,
        boundaryRing: ring,
        result: result,
      );

      for (final triangle in notifier.state.polygons) {
        expect(triangle.fillColor, Colors.green);
        expect(triangle.strokeColor, CanvasNotifier.defaultStrokeColor);
        expect(triangle.strokeWidth, CanvasNotifier.defaultStrokeWidth);
      }
    });

    test('is a single undo entry — one undo() restores the original polygon', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(10, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(10, 10), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(0, 10), fillColor: Colors.red);
      notifier.closePolygon(Colors.red);
      final beforeState = notifier.state;
      final polygonId = notifier.state.polygons.single.id;
      final ring = notifier.state.polygons.single.vertexIds;

      const result = TessellationResult(
        points: [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)],
        triangleIndices: [(0, 1, 2), (0, 2, 3)],
      );

      notifier.commitTessellationResult(
        polygonId: polygonId,
        boundaryRing: ring,
        result: result,
      );
      expect(notifier.state.polygons, hasLength(2));

      final undone = notifier.undo();

      expect(undone, isTrue);
      expect(notifier.state, beforeState);
    });

    test('does nothing when polygonId no longer exists', () {
      final notifier = CanvasNotifier();
      notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(10, 0), fillColor: Colors.red);
      notifier.handleDrawTap(const Offset(10, 10), fillColor: Colors.red);
      notifier.closePolygon(Colors.red);
      final stateBefore = notifier.state;

      notifier.commitTessellationResult(
        polygonId: 'does-not-exist',
        boundaryRing: notifier.state.polygons.single.vertexIds,
        result: const TessellationResult(
          points: [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
          triangleIndices: [(0, 1, 2)],
        ),
      );

      expect(notifier.state, stateBefore);
    });
  });
}
