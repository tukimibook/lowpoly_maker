import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/models/polygon_shape.dart';
import 'package:polygon_art_app/models/vertex.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart' show kClearFillColor;
import 'package:polygon_art_app/services/artwork_png_renderer.dart';

/// The first 8 bytes of any PNG file — see
/// `test/services/thumbnail_capture_service_test.dart` for why this is
/// asserted instead of an exact byte-for-byte fixture.
const List<int> _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

Artwork _artworkWithOneTriangle({Color fillColor = const Color(0xFF00FF00)}) {
  const a = Vertex(id: 'a', position: Offset(10, 10));
  const b = Vertex(id: 'b', position: Offset(90, 10));
  const c = Vertex(id: 'c', position: Offset(50, 90));
  return Artwork(
    id: 'art-1',
    title: 'test',
    vertices: {'a': a, 'b': b, 'c': c},
    polygons: [
      PolygonShape(
        id: 'p1',
        vertexIds: const ['a', 'b', 'c'],
        fillColor: fillColor,
        strokeColor: const Color(0xFF000000),
        strokeWidth: 2,
      ),
    ],
  );
}

/// Reads IHDR width/height from a PNG byte buffer (big-endian at offset 16/20).
(int width, int height) _pngIhdrSize(Uint8List bytes) {
  expect(bytes.sublist(0, 8), _pngSignature);
  final width =
      (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
  final height =
      (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
  return (width, height);
}

void main() {
  group('exportOutputSizeFor', () {
    test('leaves sizes at or under the long-edge cap unchanged (scale 1)', () {
      final output = exportOutputSizeFor(const Size(800, 600));
      expect(output.scale, 1.0);
      expect(output.width, 800);
      expect(output.height, 600);
    });

    test('scales from a single long-edge factor — never clamps axes independently', () {
      // 4096×2048 → scale 0.5 → 2048×1024 (aspect preserved).
      final output = exportOutputSizeFor(const Size(4096, 2048));
      expect(output.scale, 0.5);
      expect(output.width, 2048);
      expect(output.height, 1024);
      expect(output.width / output.height, closeTo(4096 / 2048, 0.001));
    });

    test('portrait canvases scale from height as the long edge', () {
      final output = exportOutputSizeFor(const Size(1000, 4000));
      expect(output.scale, closeTo(2048 / 4000, 1e-9));
      expect(output.height, 2048);
      expect(output.width, (1000 * output.scale).round());
    });
  });

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

    test('OOM guard caps the long edge at kExportMaxLongEdgePx without aspect distortion', () async {
      const canvasSize = Size(4096, 2048);
      final bytes = await ArtworkPngRenderer().render(
        _artworkWithOneTriangle(),
        canvasSize,
      );

      expect(bytes, isNotNull);
      final (width, height) = _pngIhdrSize(bytes!);
      expect(width, 2048);
      expect(height, 1024);
      expect(width / height, closeTo(canvasSize.width / canvasSize.height, 0.001));
    });

    test('transparent background + clear-fill polygon still yields a valid PNG', () async {
      final bytes = await ArtworkPngRenderer().render(
        _artworkWithOneTriangle(fillColor: kClearFillColor),
        const Size(64, 64),
        backgroundColor: kExportTransparentBackgroundColor,
      );

      expect(bytes, isNotNull);
      expect(bytes!.sublist(0, 8), _pngSignature);
    });
  });
}
