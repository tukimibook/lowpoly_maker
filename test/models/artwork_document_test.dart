import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/artwork_document.dart';
import 'package:polygon_art_app/models/underlay_layout.dart';

Artwork _artwork({String id = 'a1'}) => Artwork.empty(id: id, title: '作品');

void main() {
  group('ArtworkDocument.toJson / fromJson', () {
    test('round-trips an artwork with no underlay — the "underlay" key is omitted', () {
      final document = ArtworkDocument(artwork: _artwork());

      final json = document.toJson();
      expect(json.containsKey('underlay'), isFalse);

      final restored = ArtworkDocument.fromJson(json);
      expect(restored.artwork, document.artwork);
      expect(restored.underlayImagePath, isNull);
      expect(restored.underlayLayout, isNull);
    });

    test('round-trips an artwork with an underlay reference and its placement', () {
      const layout = UnderlayLayout(offset: Offset(5, -3), scale: 1.5, opacity: 0.6);
      final document = ArtworkDocument(
        artwork: _artwork(),
        underlayImagePath: '/documents/underlays/a1.jpg',
        underlayLayout: layout,
      );

      final restored = ArtworkDocument.fromJson(document.toJson());

      expect(restored.artwork, document.artwork);
      expect(restored.underlayImagePath, '/documents/underlays/a1.jpg');
      expect(restored.underlayLayout, layout);
    });

    test('an underlayImagePath without an explicit layout serializes UnderlayLayout.initial', () {
      final document = ArtworkDocument(
        artwork: _artwork(),
        underlayImagePath: '/documents/underlays/a1.jpg',
      );

      final restored = ArtworkDocument.fromJson(document.toJson());

      expect(restored.underlayLayout, UnderlayLayout.initial);
    });

    test('fromJson still parses the artwork geometry from a document with no underlay key at all', () {
      final json = _artwork().toJson();

      final restored = ArtworkDocument.fromJson(json);

      expect(restored.artwork, _artwork());
      expect(restored.underlayImagePath, isNull);
    });
  });
}
