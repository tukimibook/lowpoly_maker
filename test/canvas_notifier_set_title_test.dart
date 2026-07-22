import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';

void main() {
  group('CanvasNotifier.setTitle', () {
    test('updates the artwork title', () {
      final notifier = CanvasNotifier();
      addTearDown(notifier.dispose);

      notifier.setTitle('夕焼け');

      expect(notifier.state.title, '夕焼け');
    });

    test('trims leading and trailing whitespace', () {
      final notifier = CanvasNotifier();
      addTearDown(notifier.dispose);

      notifier.setTitle('  海辺  ');

      expect(notifier.state.title, '海辺');
    });

    test('falls back to kDefaultArtworkTitle when the trimmed title is empty', () {
      final notifier = CanvasNotifier();
      addTearDown(notifier.dispose);
      notifier.setTitle('一時的な名前');

      notifier.setTitle('   ');

      expect(notifier.state.title, kDefaultArtworkTitle);
    });

    test('is a no-op when the resolved title equals the current title', () {
      final notifier = CanvasNotifier();
      addTearDown(notifier.dispose);
      final before = notifier.state;

      notifier.setTitle(kDefaultArtworkTitle);
      notifier.setTitle('  $kDefaultArtworkTitle  ');

      expect(identical(notifier.state, before) || notifier.state == before, isTrue);
      expect(notifier.state.title, kDefaultArtworkTitle);
    });

    test('does not push an undo entry (title is metadata, not geometry)', () {
      final notifier = CanvasNotifier();
      addTearDown(notifier.dispose);

      notifier.setTitle('Undo対象外');

      expect(notifier.canUndo, isFalse);
    });
  });
}
