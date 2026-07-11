import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Background brightness of the canvas *editing surface* itself —
/// deliberately independent of the app's own light/dark theme (see
/// `PolygonArtApp` in `app.dart`, which follows the OS setting).
///
/// Content-creation apps (Procreate, Photoshop, ...) commonly keep the
/// canvas's own background stable regardless of the OS theme, since
/// switching it changes how an artist perceives the colors they're
/// placing. Here it's instead left as an explicit choice the artist can
/// flip at will (see the toggle in `EditorScreen`'s app bar), defaulting to
/// light so a fresh canvas always starts the same way regardless of the
/// device's OS setting.
///
/// This is session-only: it resets to [Brightness.light] on next launch.
/// Persisting it across restarts is deferred to Phase H+, alongside the
/// general settings/save persistence introduced there — see the
/// 検討メモ（2026-07-10）in
/// `.cursor/plans/ポリゴンアプリ再設計_e54196e6.plan.md`.
///
/// [PolygonPainter] reads this to keep the draft/vertex-hint overlay colors
/// (which are UI chrome, not artwork content) visible against whichever
/// background is currently chosen — a plain black dot would otherwise
/// vanish against a dark canvas.
final canvasBackgroundProvider = StateProvider<Brightness>((ref) {
  return Brightness.light;
});
