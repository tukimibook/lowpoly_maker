import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/providers/underlay_image_provider.dart';
import 'package:polygon_art_app/providers/underlay_provider.dart';
import 'package:polygon_art_app/services/underlay_picker.dart';

class _FakeUnderlayPicker extends UnderlayPicker {
  @override
  Future<String?> pickUnderlayImagePath() async => null;
}

void main() {
  group('underlayImageProvider', () {
    test('returns null when there is no underlay path', () async {
      final container = ProviderContainer(
        overrides: [underlayPickerProvider.overrideWithValue(_FakeUnderlayPicker())],
      );
      addTearDown(container.dispose);

      final image = await container.read(underlayImageProvider.future);

      expect(image, isNull);
    });

    test(
      'surfaces UnderlayImageLoadException (AsyncError) when the file is missing',
      () async {
        final container = ProviderContainer(
          overrides: [underlayPickerProvider.overrideWithValue(_FakeUnderlayPicker())],
        );
        addTearDown(container.dispose);

        container
            .read(underlayProvider.notifier)
            .setImagePath('${Directory.systemTemp.path}/definitely-missing-underlay-xyz.jpg');

        await expectLater(
          container.read(underlayImageProvider.future),
          throwsA(isA<UnderlayImageLoadException>()),
        );

        final asyncValue = container.read(underlayImageProvider);
        expect(asyncValue.hasError, isTrue);
        expect(asyncValue.error, isA<UnderlayImageLoadException>());
      },
    );
  });
}
