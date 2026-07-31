import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/utils/documents_path.dart';

void main() {
  group('toDocumentsRelativePath', () {
    test('strips the documents root prefix', () {
      expect(
        toDocumentsRelativePath('/documents/underlays/a1.jpg', '/documents'),
        'underlays/a1.jpg',
      );
    });

    test('normalizes backslashes before comparing', () {
      expect(
        toDocumentsRelativePath(r'C:\Users\me\docs\underlays\a1.jpg', r'C:\Users\me\docs'),
        'underlays/a1.jpg',
      );
    });

    test('falls back to underlays/ suffix when path is not under documents', () {
      expect(
        toDocumentsRelativePath('/other/root/underlays/a1.jpg', '/documents'),
        'underlays/a1.jpg',
      );
    });
  });

  group('resolveDocumentsAbsolutePath', () {
    test('joins relative paths onto the documents root', () {
      expect(
        resolveDocumentsAbsolutePath('underlays/a1.jpg', '/documents'),
        '/documents/underlays/a1.jpg',
      );
    });

    test('returns legacy absolute paths unchanged', () {
      expect(
        resolveDocumentsAbsolutePath('/documents/underlays/a1.jpg', '/documents'),
        '/documents/underlays/a1.jpg',
      );
    });
  });
}
