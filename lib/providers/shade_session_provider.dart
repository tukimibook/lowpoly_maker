import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/shade_tool.dart';

/// Active sub-tool while [canvasModeProvider] is `CanvasMode.shade`.
/// Survives round-trips through draw/edit (same pattern as [drawModeProvider]).
final shadeToolProvider = StateProvider<ShadeTool>((ref) {
  return ShadeTool.select;
});

/// Last tapped preset from [kDefaultPolygonPalette] while in Shade mode.
/// Drives the inline accordion (lighter left / darker right of that base).
/// `null` = collapsed. Cleared by [clearShadeSessionUi].
final activeBaseColorProvider = StateProvider<Color?>((ref) => null);
