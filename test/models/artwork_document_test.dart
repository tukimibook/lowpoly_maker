import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/artwork_document.dart';
import 'package:polygon_art_app/models/underlay_layout.dart';
import 'package:polygon_art_app/models/underlay_ref.dart';
import 'package:polygon_art_app/models/vertex.dart';

Artwork _artwork({String id = 'a1'}) => Artwork.empty(id: id, title: '作品');

final _fixedCreated = DateTime.utc(2026, 7, 20, 10);
final _fixedUpdated = DateTime.utc(2026, 7, 31, 12);

ArtworkDocument _doc({
  Artwork? artwork,
  UnderlayRef? underlay,
}) {
  return ArtworkDocument(
    artwork: artwork ?? _artwork(),
    underlay: underlay,
    createdAt: _fixedCreated,
    updatedAt: _fixedUpdated,
  );
}

void main() {
  group('ArtworkDocument.toJson / fromJson', () {
    test('round-trips metadata + geometry with no underlay — underlay key omitted', () {
      final document = _doc();

      final json = document.toJson();
      expect(json.containsKey('underlay'), isFalse);
      expect(json['schemaVersion'], kArtworkSchemaVersion);
      expect(json['createdAt'], '2026-07-20T10:00:00.000Z');
      expect(json['updatedAt'], '2026-07-31T12:00:00.000Z');
      expect(json.containsKey('canvasSize'), isFalse);

      final restored = ArtworkDocument.fromJson(json);
      expect(restored.artwork, document.artwork);
      expect(restored.schemaVersion, kArtworkSchemaVersion);
      expect(restored.createdAt, _fixedCreated);
      expect(restored.updatedAt, _fixedUpdated);
      expect(restored.underlay, isNull);
    });

    test('round-trips an underlay with documents-relative path + layout', () {
      final underlay = UnderlayRef(
        imageRelativePath: 'underlays/a1.jpg',
        layout: const UnderlayLayoutPersist(
          offsetX: 5,
          offsetY: -3,
          scale: 1.5,
          opacity: 0.6,
        ),
      );
      final document = _doc(underlay: underlay);

      final restored = ArtworkDocument.fromJson(document.toJson());

      expect(restored.artwork, document.artwork);
      expect(restored.underlay, underlay);
      expect(restored.underlay!.imageRelativePath, 'underlays/a1.jpg');
    });

    test('underlay without layout in JSON defaults to UnderlayLayoutPersist.initial', () {
      final json = _doc().toJson();
      json['underlay'] = {'imageRelativePath': 'underlays/a1.jpg'};

      final restored = ArtworkDocument.fromJson(json);

      expect(restored.underlay!.layout, UnderlayLayoutPersist.initial);
    });

    test('fromJson still parses geometry when underlay key is absent', () {
      final json = {
        'schemaVersion': 1,
        'createdAt': _fixedCreated.toIso8601String(),
        'updatedAt': _fixedUpdated.toIso8601String(),
        ..._artwork().toJson(),
      };

      final restored = ArtworkDocument.fromJson(json);

      expect(restored.artwork, _artwork());
      expect(restored.underlay, isNull);
    });

    test('fromJson accepts legacy underlay.imagePath (absolute) for compatibility', () {
      final json = _doc().toJson();
      json['underlay'] = {
        'imagePath': '/documents/underlays/a1.jpg',
        'layout': {'offsetX': 1.0, 'offsetY': 2.0, 'scale': 1.0, 'opacity': 1.0},
      };

      final restored = ArtworkDocument.fromJson(json);

      expect(restored.underlay!.imageRelativePath, '/documents/underlays/a1.jpg');
    });

    test('fromSession converts absolute underlay path to documents-relative', () {
      final document = ArtworkDocument.fromSession(
        artwork: _artwork(),
        documentsPath: '/documents',
        underlayAbsolutePath: '/documents/underlays/a1.jpg',
        underlayLayout: const UnderlayLayout(
          offset: Offset(10, 20),
          scale: 0.5,
          opacity: 0.7,
        ),
        createdAt: _fixedCreated,
        updatedAt: _fixedUpdated,
      );

      expect(document.underlay!.imageRelativePath, 'underlays/a1.jpg');
      expect(document.underlay!.layout.offsetX, 10);
      expect(document.resolvedUnderlayAbsolutePath('/documents'), '/documents/underlays/a1.jpg');
    });

    test('assertConfirmedRingIds rejects duplicate ids in confirmed polygons on load', () {
      final json = _doc().toJson();
      json['vertices'] = {
        'v1': {'x': 0, 'y': 0},
        'v2': {'x': 1, 'y': 0},
        'v3': {'x': 0, 'y': 1},
      };
      json['polygons'] = [
        {
          'id': 'p1',
          'vertexIds': ['v1', 'v2', 'v3', 'v1'],
          'fillColor': 0xFFEF5350,
          'strokeColor': 0xFF212121,
          'strokeWidth': 2.0,
        },
      ];

      expect(() => ArtworkDocument.fromJson(json), throwsA(isA<AssertionError>()));
    });

    test('draftVertexIds may contain duplicates and still round-trip', () {
      final artwork = Artwork(
        id: 'a1',
        title: '作品',
        vertices: const {
          'S': Vertex(id: 'S', position: Offset(0, 0)),
          'A': Vertex(id: 'A', position: Offset(10, 0)),
        },
        draftVertexIds: const ['S', 'A', 'S'],
      );
      final document = _doc(artwork: artwork);

      final restored = ArtworkDocument.fromJson(document.toJson());

      expect(restored.artwork.draftVertexIds, ['S', 'A', 'S']);
    });
  });
}
