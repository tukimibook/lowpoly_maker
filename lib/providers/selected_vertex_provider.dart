import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The vertex currently highlighted for editing in [CanvasMode.edit], or
/// `null` when nothing is selected. Cleared when leaving edit mode.
final selectedVertexProvider = StateProvider<String?>((ref) => null);
