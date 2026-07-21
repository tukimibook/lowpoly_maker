import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/artwork_index.dart';
import 'package:polygon_art_app/models/artwork_summary.dart';

void main() {
  group('ArtworkSummary JSON (索引ファイル entry)', () {
    final summary = ArtworkSummary(
      id: 'artwork-1',
      title: 'テスト作品',
      updatedAt: DateTime.utc(2026, 7, 20, 12, 30),
      thumbnailPath: 'thumbnails/artwork-1.png',
      documentPath: 'artworks/artwork-1.json',
    );

    test('toJson serializes updatedAt as ISO-8601', () {
      expect(summary.toJson()['updatedAt'], '2026-07-20T12:30:00.000Z');
    });

    test('fromJson(toJson(...)) round-trips every field exactly', () {
      final restored = ArtworkSummary.fromJson(summary.toJson());

      expect(restored, summary);
    });
  });

  group('ArtworkIndex JSON (索引ファイル)', () {
    test('empty() starts with no artworks', () {
      expect(ArtworkIndex.empty().artworks, isEmpty);
    });

    test('toJson includes the current schemaVersion and every summary', () {
      final index = ArtworkIndex(
        artworks: [
          ArtworkSummary(
            id: 'a1',
            title: '作品1',
            updatedAt: DateTime.utc(2026, 7, 20),
            thumbnailPath: 'thumbnails/a1.png',
            documentPath: 'artworks/a1.json',
          ),
          ArtworkSummary(
            id: 'a2',
            title: '作品2',
            updatedAt: DateTime.utc(2026, 7, 19),
            thumbnailPath: 'thumbnails/a2.png',
            documentPath: 'artworks/a2.json',
          ),
        ],
      );

      final json = index.toJson();

      expect(json['schemaVersion'], kArtworkIndexSchemaVersion);
      expect(json['artworks'], hasLength(2));
    });

    test('fromJson(toJson(...)) round-trips the whole list, in order', () {
      final index = ArtworkIndex(
        artworks: [
          ArtworkSummary(
            id: 'a1',
            title: '作品1',
            updatedAt: DateTime.utc(2026, 7, 20),
            thumbnailPath: 'thumbnails/a1.png',
            documentPath: 'artworks/a1.json',
          ),
          ArtworkSummary(
            id: 'a2',
            title: '作品2',
            updatedAt: DateTime.utc(2026, 7, 19),
            thumbnailPath: 'thumbnails/a2.png',
            documentPath: 'artworks/a2.json',
          ),
        ],
      );

      final restored = ArtworkIndex.fromJson(index.toJson());

      expect(restored, index);
    });

    test('fromJson defaults to an empty list when artworks is missing', () {
      final restored = ArtworkIndex.fromJson({'schemaVersion': 1});

      expect(restored.artworks, isEmpty);
    });
  });
}
