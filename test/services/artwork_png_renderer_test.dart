import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/polygon_shape.dart';
import 'package:polygon_art_app/models/vertex.dart';
import 'package:polygon_art_app/services/artwork_png_renderer.dart';

/// The first 8 bytes of any PNG file — see
/// `test/services/thumbnail_capture_service_test.dart` for why this is
/// asserted instead of an exact byte-for-byte fixture.
const List<int> _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

Artwork _artworkWithOneTriangle() {
  const a = Vertex(id: 'a', position: Offset(10, 10));
  const b = Vertex(id: 'b', position: Offset(90, 10));
  const c = Vertex(id: 'c', position: Offset(50, 90));
  return Artwork(
    id: 'art-1',
    title: 'test',
    vertices: {'a': a, 'b': b, 'c': c},
    polygons: [
      const PolygonShape(
        id: 'p1',
        vertexIds: ['a', 'b', 'c'],
        fillColor: Color(0xFF00FF00),
        strokeColor: Color(0xFF000000),
        strokeWidth: 2,
      ),
    ],
  );
}

void main() {
  group('ArtworkPngRenderer.render', () {
    // Plain `test()`, not `testWidgets()` — unlike `ThumbnailCaptureService`
    // (which needs a *mounted* `RepaintBoundary`, hence `testWidgets` +
    // `tester.runAsync`, see that service's test), this renderer builds its
    // own `PictureRecorder`/`Canvas` from scratch and needs no widget tree
    // at all, so there's no `FakeAsync` test zone here for `toImage()`/
    // `toByteData()`'s real engine callbacks to get stuck behind.
    test('renders a polygon into valid, non-empty PNG bytes', () async {
      final bytes = await ArtworkPngRenderer().render(
        _artworkWithOneTriangle(),
        const Size(100, 100),
      );

      expect(bytes, isNotNull);
      expect(bytes!.sublist(0, 8), _pngSignature);
    });

    test('returns null for an empty (zero) canvas size', () async {
      final bytes = await ArtworkPngRenderer().render(_artworkWithOneTriangle(), Size.zero);

      expect(bytes, isNull);
    });

    test('still renders (just the background) when there are no polygons', () async {
      final empty = Artwork.empty(id: 'empty');
      final bytes = await ArtworkPngRenderer().render(empty, const Size(50, 50));

      expect(bytes, isNotNull);
      expect(bytes!.sublist(0, 8), _pngSignature);
    });

    test('skips a "polygon" with fewer than 3 resolvable vertices without throwing', () async {
      const a = Vertex(id: 'a', position: Offset(0, 0));
      final degenerate = Artwork(
        id: 'art-2',
        title: 'degenerate',
        vertices: {'a': a},
        polygons: const [
          PolygonShape(
            id: 'p1',
            vertexIds: ['a', 'missing-b', 'missing-c'],
            fillColor: Color(0xFFFF0000),
            strokeColor: Color(0xFF000000),
            strokeWidth: 1,
          ),
        ],
      );

      final bytes = await ArtworkPngRenderer().render(degenerate, const Size(20, 20));

      expect(bytes, isNotNull);
      expect(bytes!.sublist(0, 8), _pngSignature);
    });

    test('a larger canvas produces a larger (or equal) PNG payload', () async {
      final small = await ArtworkPngRenderer().render(
        _artworkWithOneTriangle(),
        const Size(20, 20),
      );
      final large = await ArtworkPngRenderer().render(
        _artworkWithOneTriangle(),
        const Size(400, 400),
      );

      expect(small, isNotNull);
      expect(large, isNotNull);
      expect(small!.length, lessThan(large!.length));
    });
  });
}
