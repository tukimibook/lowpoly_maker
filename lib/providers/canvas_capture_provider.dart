import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The single, stable [GlobalKey] attached to `PolygonCanvas`'s outer
/// `RepaintBoundary` (which wraps *both* the underlay layer and the
/// polygon layer in one `Stack` — see that widget's `content` variable) —
/// so anything outside the widget tree (namely `autoSaveServiceProvider`,
/// via `ThumbnailCaptureService`) can capture the canvas's current on-screen
/// pixels as a gallery thumbnail without needing its own `BuildContext`.
///
/// A plain [Provider] whose value never changes for the lifetime of the
/// `ProviderContainer` — like `viewportProvider`/`underlayLayoutProvider` —
/// so reading it never itself triggers a rebuild.
final canvasRepaintBoundaryKeyProvider = Provider<GlobalKey>((ref) => GlobalKey());
