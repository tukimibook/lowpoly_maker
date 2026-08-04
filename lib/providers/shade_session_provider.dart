import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/shade_tool.dart';

/// Active sub-tool while [canvasModeProvider] is `CanvasMode.shade`.
/// Survives round-trips through draw/edit (same pattern as [drawModeProvider]).
final shadeToolProvider = StateProvider<ShadeTool>((ref) {
  return ShadeTool.select;
});

/// Last shade ramp from `computeDistanceShading` for the toolbar hand-tune
/// strip. Low-frequency; empty until a light apply runs (later step).
final lastShadingRampProvider = StateProvider<List<Color>>((ref) {
  return const [];
});
