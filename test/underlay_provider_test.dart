import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/providers/underlay_provider.dart';
import 'package:polygon_art_app/services/underlay_picker.dart';

/// A fake [UnderlayPicker] that never touches a real platform channel.
///
/// [nextPath]/[nextError] are mutable so a single instance can simulate a
/// different outcome (success/cancel/failure) on each call within one
/// test, exactly like a real picker would across repeated user gestures.
class _FakeUnderlayPicker extends UnderlayPicker {
  String? nextPath;
  Object? nextError;

  @override
  Future<String?> pickUnderlayImagePath() async {
    if (nextError != null) throw nextError!;
    return nextPath;
  }
}

void main() {
  group('UnderlayController.pickImage', () {
    test('a successful pick stores the (already-downsampled) file path', () async {
      final picker = _FakeUnderlayPicker()..nextPath = '/tmp/photo.jpg';
      final container = ProviderContainer(
        overrides: [underlayPickerProvider.overrideWithValue(picker)],
      );
      addTearDown(container.dispose);

      await container.read(underlayProvider.notifier).pickImage();

      final state = container.read(underlayProvider);
      expect(state.imagePath, '/tmp/photo.jpg');
      expect(state.errorMessage, isNull);
    });

    test('cancelling the picker (null path) leaves the state unchanged', () async {
      final picker = _FakeUnderlayPicker()..nextPath = '/tmp/first.jpg';
      final container = ProviderContainer(
        overrides: [underlayPickerProvider.overrideWithValue(picker)],
      );
      addTearDown(container.dispose);

      await container.read(underlayProvider.notifier).pickImage();
      expect(container.read(underlayProvider).imagePath, '/tmp/first.jpg');

      // Re-pick, but this time the user backs out of the picker.
      picker.nextPath = null;
      await container.read(underlayProvider.notifier).pickImage();

      final state = container.read(underlayProvider);
      expect(state.imagePath, '/tmp/first.jpg');
      expect(state.errorMessage, isNull);
    });

    test(
      'a picker failure surfaces a user-facing error without clearing a '
      'previously imported photo',
      () async {
        final picker = _FakeUnderlayPicker()..nextPath = '/tmp/existing.jpg';
        final container = ProviderContainer(
          overrides: [underlayPickerProvider.overrideWithValue(picker)],
        );
        addTearDown(container.dispose);

        await container.read(underlayProvider.notifier).pickImage();
        expect(container.read(underlayProvider).imagePath, '/tmp/existing.jpg');

        picker
          ..nextPath = null
          ..nextError = Exception('permission denied');
        await container.read(underlayProvider.notifier).pickImage();

        final state = container.read(underlayProvider);
        expect(state.imagePath, '/tmp/existing.jpg');
        expect(state.errorMessage, contains('permission denied'));
      },
    );

    test('a fresh, never-picked state has no image path and no error', () {
      final container = ProviderContainer(
        overrides: [underlayPickerProvider.overrideWithValue(_FakeUnderlayPicker())],
      );
      addTearDown(container.dispose);

      final state = container.read(underlayProvider);
      expect(state.imagePath, isNull);
      expect(state.errorMessage, isNull);
    });
  });

  group('UnderlayController.setImagePath (Phase Hγ — gallery 新規作成/開く)', () {
    test('sets the image path directly, without going through the picker', () {
      final container = ProviderContainer(
        overrides: [underlayPickerProvider.overrideWithValue(_FakeUnderlayPicker())],
      );
      addTearDown(container.dispose);

      container.read(underlayProvider.notifier).setImagePath('/documents/underlays/a1.jpg');

      final state = container.read(underlayProvider);
      expect(state.imagePath, '/documents/underlays/a1.jpg');
      expect(state.errorMessage, isNull);
    });

    test('a null argument clears a previously set image path (for a new artwork)', () async {
      final picker = _FakeUnderlayPicker()..nextPath = '/tmp/photo.jpg';
      final container = ProviderContainer(
        overrides: [underlayPickerProvider.overrideWithValue(picker)],
      );
      addTearDown(container.dispose);
      await container.read(underlayProvider.notifier).pickImage();
      expect(container.read(underlayProvider).imagePath, isNotNull);

      container.read(underlayProvider.notifier).setImagePath(null);

      expect(container.read(underlayProvider).imagePath, isNull);
    });

    test('clears a previous error even though it does not touch imagePath', () async {
      final picker = _FakeUnderlayPicker()..nextError = Exception('boom');
      final container = ProviderContainer(
        overrides: [underlayPickerProvider.overrideWithValue(picker)],
      );
      addTearDown(container.dispose);
      await container.read(underlayProvider.notifier).pickImage();
      expect(container.read(underlayProvider).errorMessage, isNotNull);

      container.read(underlayProvider.notifier).setImagePath('/documents/underlays/a1.jpg');

      expect(container.read(underlayProvider).errorMessage, isNull);
    });
  });
}
