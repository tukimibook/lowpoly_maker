import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../geometry/underlay_fit.dart';
import 'canvas_size_provider.dart';
import 'underlay_layout_provider.dart';
import 'underlay_provider.dart';

/// Decodes [underlayProvider]'s current `imagePath` into a paintable
/// [ui.Image], re-decoding whenever a new photo is picked.
///
/// Kept as its own `FutureProvider` (rather than decoding inline in a
/// widget's `build`) so the decode only ever runs once per picked photo —
/// Riverpod caches the result and every watcher shares it — instead of
/// once per rebuild/repaint.
final underlayImageProvider = FutureProvider<ui.Image?>((ref) async {
  final path = ref.watch(underlayProvider.select((state) => state.imagePath));
  if (path == null) return null;

  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
});

/// Recomputes and applies the underlay's fit-to-canvas [UnderlayLayout]
/// (`fitUnderlayToCanvas`) whenever a new photo finishes decoding, or the
/// canvas is resized (e.g. device rotation).
///
/// This provider's *value* is never read — it exists purely to register
/// the side effects below exactly once. Watch/read it from somewhere that
/// lives for the whole editing session (`UnderlayLayer`) to wire it up;
/// nothing else needs to depend on it.
final underlayFitCoordinatorProvider = Provider<void>((ref) {
  void refit() {
    final image = ref.read(underlayImageProvider).valueOrNull;
    if (image == null) return;

    final canvasSize = ref.read(canvasSizeProvider).value;
    if (canvasSize.isEmpty) return;

    final layoutController = ref.read(underlayLayoutProvider);
    final current = layoutController.value;
    layoutController.setLayout(
      fitUnderlayToCanvas(
        imageSize: ui.Size(image.width.toDouble(), image.height.toDouble()),
        canvasSize: canvasSize,
        opacity: current.opacity,
        visible: current.visible,
      ),
    );
  }

  ref.listen(underlayImageProvider, (previous, next) {
    if (next.valueOrNull != null) refit();
  });

  // `canvasSizeProvider`'s value lives on a plain `ValueNotifier` (Phase Hγ,
  // #9 — moved out of `Artwork`/`canvasProvider` so it can never re-enter
  // the undo stack), not a `StateNotifierProvider`'s state, so it can't be
  // observed via `ref.listen(...select(...))` the way `canvasProvider` used
  // to be. `addListener`/`removeListener` is the same pattern this file
  // already relies on implicitly through `ValueNotifier`-backed controllers
  // elsewhere (`underlayLayoutProvider`).
  final canvasSizeController = ref.read(canvasSizeProvider);
  canvasSizeController.addListener(refit);
  ref.onDispose(() => canvasSizeController.removeListener(refit));
});
