import 'package:file/memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/providers/artwork_repository_provider.dart';
import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/providers/underlay_provider.dart';
import 'package:polygon_art_app/repositories/artwork_repository.dart';
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

ProviderContainer _container({
  required MemoryFileSystem fs,
  required ArtworkRepository repository,
  required _FakeUnderlayPicker picker,
}) {
  return ProviderContainer(
    overrides: [
      underlayPickerProvider.overrideWithValue(picker),
      artworkRepositoryProvider.overrideWith((ref) async => repository),
    ],
  );
}

Future<void> _writeSource(MemoryFileSystem fs, String path, [List<int> bytes = const [1, 2, 3]]) async {
  await fs.file(path).create(recursive: true);
  await fs.file(path).writeAsBytes(bytes);
}

void main() {
  late MemoryFileSystem fs;
  late ArtworkRepository repository;

  setUp(() {
    fs = MemoryFileSystem();
    repository = ArtworkRepository(fileSystem: fs, documentsPath: '/documents');
  });

  group('UnderlayController.pickImage', () {
    test(
      'a successful pick copies into underlays/ and stores that documents path',
      () async {
        await _writeSource(fs, '/tmp/photo.jpg');
        final picker = _FakeUnderlayPicker()..nextPath = '/tmp/photo.jpg';
        final container = _container(fs: fs, repository: repository, picker: picker);
        addTearDown(container.dispose);

        final artworkId = container.read(canvasProvider).id;
        await container.read(underlayProvider.notifier).pickImage();

        final state = container.read(underlayProvider);
        expect(state.imagePath, repository.underlayPathFor(artworkId, '/tmp/photo.jpg'));
        expect(state.imagePath, contains('/documents/underlays/'));
        expect(state.errorMessage, isNull);
        expect(await fs.file(state.imagePath!).exists(), isTrue);
        expect(await fs.file(state.imagePath!).readAsBytes(), [1, 2, 3]);
        // Original picker path is left in place (copy, not move).
        expect(await fs.file('/tmp/photo.jpg').exists(), isTrue);
      },
    );

    test('cancelling the picker (null path) leaves the state unchanged', () async {
      await _writeSource(fs, '/tmp/first.jpg');
      final picker = _FakeUnderlayPicker()..nextPath = '/tmp/first.jpg';
      final container = _container(fs: fs, repository: repository, picker: picker);
      addTearDown(container.dispose);

      await container.read(underlayProvider.notifier).pickImage();
      final firstCopied = container.read(underlayProvider).imagePath;
      expect(firstCopied, isNotNull);

      // Re-pick, but this time the user backs out of the picker.
      picker.nextPath = null;
      await container.read(underlayProvider.notifier).pickImage();

      final state = container.read(underlayProvider);
      expect(state.imagePath, firstCopied);
      expect(state.errorMessage, isNull);
    });

    test(
      'a picker failure surfaces a user-facing error without clearing a '
      'previously imported photo',
      () async {
        await _writeSource(fs, '/tmp/existing.jpg');
        final picker = _FakeUnderlayPicker()..nextPath = '/tmp/existing.jpg';
        final container = _container(fs: fs, repository: repository, picker: picker);
        addTearDown(container.dispose);

        await container.read(underlayProvider.notifier).pickImage();
        final existing = container.read(underlayProvider).imagePath;
        expect(existing, isNotNull);

        picker
          ..nextPath = null
          ..nextError = Exception('permission denied');
        await container.read(underlayProvider.notifier).pickImage();

        final state = container.read(underlayProvider);
        expect(state.imagePath, existing);
        expect(state.errorMessage, contains('permission denied'));
      },
    );

    test(
      'a copy failure does not store the picker’s transient path as imagePath',
      () async {
        // Source file does not exist → copyUnderlayImage throws.
        final picker = _FakeUnderlayPicker()..nextPath = '/tmp/missing.jpg';
        final container = _container(fs: fs, repository: repository, picker: picker);
        addTearDown(container.dispose);

        await container.read(underlayProvider.notifier).pickImage();

        final state = container.read(underlayProvider);
        expect(state.imagePath, isNull);
        expect(state.errorMessage, isNotNull);
        expect(state.errorMessage, contains('Could not load image'));
      },
    );

    test('a fresh, never-picked state has no image path and no error', () {
      final container = _container(
        fs: fs,
        repository: repository,
        picker: _FakeUnderlayPicker(),
      );
      addTearDown(container.dispose);

      final state = container.read(underlayProvider);
      expect(state.imagePath, isNull);
      expect(state.errorMessage, isNull);
    });
  });

  group('UnderlayController.setImagePath (Phase Hγ — gallery 新規作成/開く)', () {
    test('sets the image path directly, without going through the picker', () {
      final container = _container(
        fs: fs,
        repository: repository,
        picker: _FakeUnderlayPicker(),
      );
      addTearDown(container.dispose);

      container.read(underlayProvider.notifier).setImagePath('/documents/underlays/a1.jpg');

      final state = container.read(underlayProvider);
      expect(state.imagePath, '/documents/underlays/a1.jpg');
      expect(state.errorMessage, isNull);
    });

    test('a null argument clears a previously set image path (for a new artwork)', () async {
      await _writeSource(fs, '/tmp/photo.jpg');
      final picker = _FakeUnderlayPicker()..nextPath = '/tmp/photo.jpg';
      final container = _container(fs: fs, repository: repository, picker: picker);
      addTearDown(container.dispose);
      await container.read(underlayProvider.notifier).pickImage();
      expect(container.read(underlayProvider).imagePath, isNotNull);

      container.read(underlayProvider.notifier).setImagePath(null);

      expect(container.read(underlayProvider).imagePath, isNull);
    });

    test('clears a previous error even though it does not touch imagePath', () async {
      final picker = _FakeUnderlayPicker()..nextError = Exception('boom');
      final container = _container(fs: fs, repository: repository, picker: picker);
      addTearDown(container.dispose);
      await container.read(underlayProvider.notifier).pickImage();
      expect(container.read(underlayProvider).errorMessage, isNotNull);

      container.read(underlayProvider.notifier).setImagePath('/documents/underlays/a1.jpg');

      expect(container.read(underlayProvider).errorMessage, isNull);
    });
  });
}
