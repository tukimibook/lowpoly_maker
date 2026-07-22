import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The vertex currently highlighted for editing in [CanvasMode.edit], or
/// `null` when nothing is selected. Cleared when leaving edit mode.
final selectedVertexProvider = StateProvider<String?>((ref) => null);

/// When `true`, the next tap on a *different* vertex in edit mode runs
/// [CanvasNotifier.weldVertices] (explicit weld arming via the toolbar).
/// Cleared after that attempt, on deselect, and on mode change — never
/// left armed across sessions.
final weldArmedProvider = StateProvider<bool>((ref) => false);
