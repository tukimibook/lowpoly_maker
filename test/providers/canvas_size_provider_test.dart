import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/providers/canvas_size_provider.dart';

void main() {
  group('CanvasSizeController', () {
    test('starts at Size.zero (nothing laid out yet)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(canvasSizeProvider).value, Size.zero);
    });

    test('setSize replaces the value', () {
      final controller = ProviderContainer().read(canvasSizeProvider);

      controller.setSize(const Size(400, 800));

      expect(controller.value, const Size(400, 800));
    });

    test('setSize is a no-op (no listener notification) when unchanged', () {
      final controller = ProviderContainer().read(canvasSizeProvider);
      controller.setSize(const Size(400, 800));

      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.setSize(const Size(400, 800));

      expect(notifications, 0);
    });

    test('the provider hands out the same controller instance on repeated reads', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(canvasSizeProvider),
        same(container.read(canvasSizeProvider)),
      );
    });
  });

  group('CanvasSizeController vs. CanvasNotifier undo (Phase Hγ, #9)', () {
    test(
      'canvas size is untouched by Artwork undo/redo — it is no longer part '
      'of Artwork at all, so it can never be part of an undo snapshot',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(canvasProvider.notifier);
        final sizeController = container.read(canvasSizeProvider);

        // A size recorded while the draft below is still empty — analogous
        // to the layout captured just before an undo-tracked edit.
        sizeController.setSize(const Size(300, 600));

        notifier.handleDrawTap(const Offset(0, 0), fillColor: Colors.red);
        notifier.handleDrawTap(const Offset(100, 0), fillColor: Colors.red);

        // The device rotates (or the toolbar's height changes) between the
        // edit above and the undo below — the kind of change that used to
        // get silently reverted by `undo()` while `canvasSize` still lived
        // on `Artwork` itself.
        sizeController.setSize(const Size(600, 300));

        expect(notifier.undo(), isTrue);
        expect(notifier.state.draftVertexIds, hasLength(1));
        expect(sizeController.value, const Size(600, 300));
      },
    );
  });
}
