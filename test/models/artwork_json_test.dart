import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/polygon_shape.dart';
import 'package:polygon_art_app/models/vertex.dart';

void main() {
  group('Vertex JSON (ArtworkDocument v1)', () {
    test('toJson serializes only x/y — no id (carried by the map key instead)', () {
      const vertex = Vertex(id: 'v1', position: Offset(12.5, -3.25));

      final json = vertex.toJson();

      expect(json, {'x': 12.5, 'y': -3.25});
    });

    test('fromJson round-trips position and takes id from the explicit argument', () {
      const original = Vertex(id: 'v1', position: Offset(12.5, -3.25));

      final restored = Vertex.fromJson('v1', original.toJson());

      expect(restored, original);
    });

    test('fromJson accepts integer x/y (num, not just double) from a decoded JSON source', () {
      final restored = Vertex.fromJson('v2', {'x': 10, 'y': 20});

      expect(restored, const Vertex(id: 'v2', position: Offset(10, 20)));
    });
  });

  group('PolygonShape JSON (ArtworkDocument v1)', () {
    const polygon = PolygonShape(
      id: 'p1',
      vertexIds: ['v1', 'v2', 'v3'],
      fillColor: Color(0xFFEF5350),
      strokeColor: Color(0xFF212121),
      strokeWidth: 2.5,
    );

    test('toJson serializes colors as 32-bit ARGB ints', () {
      final json = polygon.toJson();

      expect(json, {
        'id': 'p1',
        'vertexIds': ['v1', 'v2', 'v3'],
        'fillColor': 0xFFEF5350,
        'strokeColor': 0xFF212121,
        'strokeWidth': 2.5,
      });
    });

    test('fromJson round-trips id, vertexIds, colors, and strokeWidth', () {
      final restored = PolygonShape.fromJson(polygon.toJson());

      expect(restored, polygon);
    });
  });

  group('Artwork JSON (geometry portion of ArtworkDocument v1)', () {
    final artwork = Artwork(
      id: 'artwork-1',
      title: 'テスト作品',
      vertices: const {
        'v1': Vertex(id: 'v1', position: Offset(0, 0)),
        'v2': Vertex(id: 'v2', position: Offset(100, 0)),
        'v3': Vertex(id: 'v3', position: Offset(50, 100)),
      },
      polygons: const [
        PolygonShape(
          id: 'p1',
          vertexIds: ['v1', 'v2', 'v3'],
          fillColor: Color(0xFFEF5350),
          strokeColor: Color(0xFF212121),
          strokeWidth: 2.5,
        ),
      ],
      draftVertexIds: const ['v4', 'v5'],
    );

    test('toJson is geometry/identity only — schemaVersion/timestamps live on ArtworkDocument', () {
      final json = artwork.toJson();
      expect(json.containsKey('schemaVersion'), isFalse);
      expect(json.containsKey('createdAt'), isFalse);
      expect(json.containsKey('updatedAt'), isFalse);
      expect(json.containsKey('underlay'), isFalse);
    });

    test('toJson never includes canvasSize — it is not a field on Artwork any more', () {
      expect(artwork.toJson().containsKey('canvasSize'), isFalse);
    });

    test('fromJson(toJson(...)) round-trips id/title/vertices/polygons exactly', () {
      final restored = Artwork.fromJson(artwork.toJson());

      expect(restored, artwork);
    });

    test(
      'fromJson round-trips draftVertexIds (Hγ decision: drafts are '
      'persisted so an in-progress shape survives kill + relaunch)',
      () {
        final restored = Artwork.fromJson(artwork.toJson());

        expect(restored.draftVertexIds, ['v4', 'v5']);
      },
    );

    test('fromJson defaults draftVertexIds to empty for a document missing the field '
        '(forward compatibility with a hypothetical older writer)', () {
      final json = artwork.toJson()..remove('draftVertexIds');

      final restored = Artwork.fromJson(json);

      expect(restored.draftVertexIds, isEmpty);
    });

    test('an empty artwork (fresh draft, nothing placed yet) round-trips too', () {
      final empty = Artwork.empty(id: 'artwork-2');

      final restored = Artwork.fromJson(empty.toJson());

      expect(restored, empty);
    });

    test('shared vertex references survive the round-trip (weld model preserved)', () {
      final shared = Artwork(
        id: 'artwork-3',
        title: '共有頂点',
        vertices: const {
          'v1': Vertex(id: 'v1', position: Offset(0, 0)),
          'v2': Vertex(id: 'v2', position: Offset(100, 0)),
          'v3': Vertex(id: 'v3', position: Offset(50, 100)),
          'v4': Vertex(id: 'v4', position: Offset(50, -100)),
        },
        polygons: const [
          PolygonShape(
            id: 'pA',
            vertexIds: ['v1', 'v2', 'v3'],
            fillColor: Color(0xFFEF5350),
            strokeColor: Color(0xFF212121),
            strokeWidth: 2.5,
          ),
          PolygonShape(
            id: 'pB',
            vertexIds: ['v1', 'v2', 'v4'],
            fillColor: Color(0xFF42A5F5),
            strokeColor: Color(0xFF212121),
            strokeWidth: 2.5,
          ),
        ],
      );

      final restored = Artwork.fromJson(shared.toJson());

      expect(restored.polygons[0].vertexIds[0], restored.polygons[1].vertexIds[0]);
      expect(restored, shared);
    });
  });
}
