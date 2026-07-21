import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/widgets/versioned_file_image.dart';

void main() {
  // Paths need not exist on disk — equality only inspects `file.path`
  // (and version/scale), never opens the file.
  final fileA = File('/documents/thumbnails/a1.png');
  final fileB = File('/documents/thumbnails/a2.png');
  final v1 = DateTime.utc(2026, 7, 20, 12);
  final v2 = DateTime.utc(2026, 7, 21, 15);

  group('VersionedFileImage equality (ImageCache key)', () {
    test('same path + same version + same scale are equal and share a hashCode', () {
      final a = VersionedFileImage(fileA, v1);
      final b = VersionedFileImage(File('/documents/thumbnails/a1.png'), v1);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test(
      'same path + different version are not equal — that is what forces a '
      'cache miss (and therefore a reload) after an in-place thumbnail overwrite',
      () {
        final older = VersionedFileImage(fileA, v1);
        final newer = VersionedFileImage(fileA, v2);

        expect(older, isNot(equals(newer)));
        expect(older.hashCode, isNot(newer.hashCode));
      },
    );

    test('different path + same version are not equal', () {
      final a = VersionedFileImage(fileA, v1);
      final b = VersionedFileImage(fileB, v1);

      expect(a, isNot(equals(b)));
    });

    test('same path + same version + different scale are not equal', () {
      final a = VersionedFileImage(fileA, v1);
      final b = VersionedFileImage(fileA, v1, scale: 2.0);

      expect(a, isNot(equals(b)));
    });
  });
}
