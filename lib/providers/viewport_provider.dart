import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/coordinate_transform.dart';

/// Holds the canvas's current [ViewportTransform] (pan + zoom) as a
/// [ValueNotifier] rather than plain Riverpod state.
///
/// [CustomPainter]s can subscribe to a [ValueNotifier] directly via their
/// `repaint` listenable and get repainted whenever the transform changes,
/// without the surrounding widget tree (toolbar, etc.) needing to rebuild —
/// only the canvas layer repaints. Widgets that read the transform to
/// convert a one-off tap/drag position should read [value] directly rather
/// than watching [viewportProvider] in `build`, so they don't rebuild every
/// time the viewport moves either.
class ViewportController extends ValueNotifier<ViewportTransform> {
  ViewportController() : super(ViewportTransform.identity);
}

/// Provides the single, stable [ViewportController] instance for the
/// current artwork editing session. The provider itself never changes value
/// (it's watched only to obtain the controller), so widgets that `watch` it
/// are not rebuilt when the transform inside changes.
///
/// Phase B introduces this seam with the controller pinned to
/// [ViewportTransform.identity] — no gesture updates it yet. Pinch-zoom/pan
/// support is added in a later phase by having a gesture handler call
/// `ref.read(viewportProvider).value = ...`.
final viewportProvider = Provider<ViewportController>((ref) {
  final controller = ViewportController();
  ref.onDispose(controller.dispose);
  return controller;
});
